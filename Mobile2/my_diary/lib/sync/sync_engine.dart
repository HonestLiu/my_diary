import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:my_diary_mobile/models/sync_types.dart';
import 'package:my_diary_mobile/sync/auth_service.dart';
import 'package:my_diary_mobile/sync/crypto.dart';
import 'package:my_diary_mobile/sync/remote_storage.dart';
import 'package:my_diary_mobile/vault/local_vault.dart';
import 'package:my_diary_mobile/vault/vault_layout.dart';
import 'package:my_diary_mobile/s3_remote.dart';
import 'package:my_diary_mobile/sync/cloud_remote.dart';
import 'package:path/path.dart' as p;

/// 本地优先同步引擎。双向、冲突感知、绝不静默覆盖。
///
/// 协议（与桌面端 `engine.ts` 一致）：
///   1. 扫描本地文件，计算 SHA-256 + size
///   2. 获取远程清单（metadata/sync.json）
///   3. 对比本地基线（上次同步）+ 当前本地
///   4. 上传 / 下载新文件
///   5. 某文件自上次同步起两侧都被修改 → 冲突（写 conflicts/<...>.{local,remote}.md）
///
/// 内容范围：仅同步日记数据（entries/、assets/、versions/），
/// 排除 settings.json、metadata/index.json、metadata/sync.json、conflicts/，
/// 避免设备专属配置、凭据与本机基线跨设备互覆。
class SyncEngine {
  final LocalVault storage;
  final RemoteStorage remote;
  final String deviceId;

  SyncEngine(this.storage, this.remote, this.deviceId);

  /// 仅同步日记内容，排除设备专属文件。
  ///
  /// `metadata/sync.json` 是「本机上次同步基线」，属于设备本地状态，
  /// 绝不能跨设备同步 —— 否则会互相覆盖基线、破坏冲突检测。每台设备只维护自己的基线。
  static bool shouldSync(String path) {
    if (path == VaultLayout.settings) return false;
    if (path == VaultLayout.index) return false;
    if (path == VaultLayout.sync) return false;
    if (path == VaultLayout.hashCache) return false; // 本地哈希缓存，不进同步
    if (path.startsWith('${VaultLayout.conflicts}/')) return false;
    return true;
  }

  /// 扫描整个 vault，构建当前本地清单（仅内容范围）。
  ///
  /// 读取 + SHA-256 是 CPU 密集（assets 下可能有大量图片/视频），在后台
  /// isolate 中执行，避免同步时主线程被哈希计算占满导致 UI 卡顿。
  ///
  /// 增量优化：`assets/` 下的文件由 uuid 命名、落盘后从不原地改写
  /// （同步下载覆盖时 mtime 会变，会被重新哈希），因此用 size+mtime
  /// 命中本地哈希缓存即可跳过重复读取，无需逐次重算所有媒体文件；
  /// `entries/` / `versions/` 等会被原地改写的小文本始终重算，保证精确。
  Future<SyncManifest> buildLocalManifest() async {
    final files = (await storage.list(''))
        .where(shouldSync)
        .toList();
    final cache = await _loadHashCache();
    var cacheDirty = false;
    final toHash = <String>[];
    final resolvedHash = <String, String>{};
    final statByPath = <String, ({int size, int mtime})>{};

    for (final f in files) {
      FileStat st;
      try {
        st = await File(p.join(storage.root, f)).stat();
      } catch (_) {
        continue; // 读不到则跳过（与之前行为一致）
      }
      statByPath[f] = (size: st.size, mtime: st.modified.millisecondsSinceEpoch);
      final cached = cache[f];
      if (cached != null &&
          _isAsset(f) &&
          cached.size == st.size &&
          cached.mtime == st.modified.millisecondsSinceEpoch) {
        resolvedHash[f] = cached.hash; // 未变化，复用缓存哈希
      } else {
        toHash.add(f);
      }
    }

    for (final r in await computeLocalHashes(storage.root, toHash)) {
      resolvedHash[r.path] = r.hash;
      if (_isAsset(r.path)) {
        // 用首轮 stat 的 mtime 入缓存：若哈希期间文件被改动，下次同步的
        // stat 会对不上（mtime/size 变化），自然触发重算，保证精确。
        final st = statByPath[r.path];
        cache[r.path] = (size: r.size, mtime: st?.mtime ?? 0, hash: r.hash);
        cacheDirty = true;
      }
    }
    if (cacheDirty) await _saveHashCache(cache);

    final syncFiles = <SyncFile>[
      for (final f in files)
        if (resolvedHash[f] != null)
          SyncFile(
            path: f,
            hash: resolvedHash[f]!,
            size: statByPath[f]?.size ?? 0,
            updated: DateTime.now().millisecondsSinceEpoch,
          ),
    ];
    return SyncManifest(
      deviceId: deviceId,
      files: syncFiles,
      generatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 当前本地「尚未同步到远程」的文件路径集合。
  ///
  /// 判定：本地清单中某文件的 hash 与「本机基线」（metadata/sync.json，
  /// 上次同步完成时的本地状态）不一致，即自上次同步以来有改动、待上传；
  /// 基线中不存在的新文件（新条目/新资产）同样视为未同步。
  /// 仅本地计算，不发起任何网络请求。
  Future<Set<String>> unsyncedPaths() async {
    final local = await buildLocalManifest();
    final baseline = await readLocalBaseline();
    final baseHash = {
      for (final f in baseline?.files ?? []) f.path: f.hash,
    };
    return {
      for (final f in local.files)
        if (baseHash[f.path] != f.hash) f.path,
    };
  }

  Future<SyncManifest?> readLocalBaseline() async {
    if (!(await storage.exists(VaultLayout.sync))) return null;
    try {
      return SyncManifest.fromJson(jsonDecode(await storage.readText(VaultLayout.sync))
          as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeLocalBaseline(SyncManifest m) async {
    await storage.writeText(VaultLayout.sync, jsonEncode(m.toJson()));
  }

  /// 读取本地哈希缓存（metadata/hashes.json）。缺失/损坏一律按空缓存处理。
  Future<Map<String, ({int size, int mtime, String hash})>> _loadHashCache() async {
    if (!(await storage.exists(VaultLayout.hashCache))) return {};
    try {
      final map =
          jsonDecode(await storage.readText(VaultLayout.hashCache)) as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          e.key: (
            size: (e.value['s'] as num).toInt(),
            mtime: (e.value['m'] as num).toInt(),
            hash: e.value['h'] as String,
          ),
      };
    } catch (_) {
      return {};
    }
  }

  /// 写回哈希缓存。写失败不影响同步（下次全量重算即可）。
  Future<void> _saveHashCache(
      Map<String, ({int size, int mtime, String hash})> cache) async {
    try {
      await storage.writeText(
        VaultLayout.hashCache,
        jsonEncode({
          for (final e in cache.entries)
            e.key: {'s': e.value.size, 'm': e.value.mtime, 'h': e.value.hash},
        }),
      );
    } catch (_) {/* 缓存写失败忽略 */}
  }

  Future<SyncResult> sync() async {
    final local = await buildLocalManifest();
    final remoteObjects =
        (await remote.list('')).where(shouldSync).toList();
    final remoteManifest = await remote.fetchManifest();
    final remoteHash = Map.fromEntries(
      (remoteManifest?.files ?? []).map((f) => MapEntry(f.path, f.hash)),
    );
    final baseline = await readLocalBaseline();

    final localMap = Map.fromEntries(local.files.map((f) => MapEntry(f.path, f)));
    final baseMap = Map.fromEntries(
        (baseline?.files ?? []).map((f) => MapEntry(f.path, f)));

    final result = SyncResult();
    final allPaths = <String>{...localMap.keys, ...remoteObjects};

    for (final path in allPaths) {
      if (!shouldSync(path)) continue;
      final l = localMap[path];
      final rExists = remoteObjects.contains(path);
      final rHash = remoteHash[path];
      final b = baseMap[path];
      try {
        if (l != null && !rExists) {
          // 本地新增 → 上传。
          await remote.upload(path, await storage.readBytes(path));
          result.uploaded.add(path);
        } else if (l == null && rExists) {
          // 远程新增 → 下载（远程在此处为准）。
          await _downloadAndStore(path);
          result.downloaded.add(path);
        } else if (l != null && rExists) {
          if (rHash != null && l.hash == rHash) continue; // 内容相同
          final localChanged = b == null || b.hash != l.hash;
          // 无远程清单条目时，无法证明远程未变，保守假定其已变，避免静默覆盖并暴露冲突。
          final remoteChanged =
              rHash == null || b == null || b.hash != rHash;
          if (localChanged && remoteChanged) {
            // 两侧自上次同步起都改了 → 冲突（不覆盖）。
            await _writeConflict(path);
            result.conflicts.add(SyncConflict(
              path: path,
              local: l,
              remote: SyncFile(
                path: path,
                hash: rHash ?? '',
                size: 0,
                updated: DateTime.now().millisecondsSinceEpoch,
              ),
            ));
          } else if (localChanged) {
            await remote.upload(path, await storage.readBytes(path));
            result.uploaded.add(path);
          } else {
            await _downloadAndStore(path);
            result.downloaded.add(path);
          }
        }
      } catch (e) {
        result.errors.add('$path: $e');
      }
    }

    // 基线变为当前本地状态；远程更新清单。
    await writeLocalBaseline(local);
    try {
      await remote.pushManifest(local);
    } catch (e) {
      result.errors.add('manifest: $e');
    }
    return result;
  }

  Future<void> _downloadAndStore(String path) async {
    final data = await remote.download(path);
    await storage.writeBytes(path, data);
  }

  Future<void> _writeConflict(String path) async {
    // 以条目文件（而非日期）作 key：同一天多条条目冲突副本不互相覆盖。
    final key = conflictKeyFromPath(path);
    final localData = await storage.readBytes(path);
    final remoteData = await remote.download(path);
    await storage.writeBytes(conflictFilePath(key, 'local'), localData);
    await storage.writeBytes(conflictFilePath(key, 'remote'), remoteData);
  }

  /// 解决已检测到的冲突。"local" 推送本地副本；"remote" 用远程副本覆盖本地。
  /// 冲突副本被移除，该路径的基线被刷新。
  Future<void> resolveConflict(String path, ConflictResolution resolution) async {
    if (resolution == ConflictResolution.local) {
      await remote.upload(path, await storage.readBytes(path));
    } else {
      await _downloadAndStore(path);
    }
    final key = conflictKeyFromPath(path);
    for (final side in const ['local', 'remote']) {
      final cf = conflictFilePath(key, side);
      if (await storage.exists(cf)) await storage.delete(cf);
    }
    final baseline = await readLocalBaseline() ??
        SyncManifest(
          deviceId: deviceId,
          files: [],
          generatedAt: DateTime.now().millisecondsSinceEpoch,
        );
    final map = Map.fromEntries(baseline.files.map((f) => MapEntry(f.path, f)));
    final bytes = await storage.readBytes(path);
    map[path] = SyncFile(
      path: path,
      hash: sha256Hex(bytes),
      size: bytes.length,
      updated: DateTime.now().millisecondsSinceEpoch,
    );
    await writeLocalBaseline(SyncManifest(
      deviceId: baseline.deviceId,
      files: map.values.toList(),
      generatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }
}

/// 依据公开同步配置 + 安全凭据构建远程存储。
RemoteStorage buildRemoteStorage(
  SyncConfig publicConfig,
  AuthService auth,
) {
  if (publicConfig.isCloud) {
    if (!auth.isCloudAuthenticated) {
      throw StateError('云服务未登录，无法同步');
    }
    return CloudServiceRemote(auth);
  }
  if (publicConfig.isDirectStorage) {
    final accessKey = auth.s3AccessKey;
    final secretKey = auth.s3SecretKey;
    if (accessKey == null ||
        secretKey == null ||
        publicConfig.endpoint == null ||
        publicConfig.bucket == null) {
      throw StateError('对象存储凭据不完整，无法同步');
    }
    // MinIO 等 S3 兼容存储没有用户可填的 Region（服务端默认 us-east-1）；
    // 阿里云 OSS 的 SigV4 会严格校验 region，必须是 oss-cn-* 这类。见
    // [SyncConfig.effectiveRegion]。
    final region = publicConfig.effectiveRegion();
    return S3StorageProvider(S3Config(
      endpoint: publicConfig.endpoint!,
      bucket: publicConfig.bucket!,
      region: region,
      accessKey: accessKey,
      secretKey: secretKey,
      pathStyle: publicConfig.effectivePathStyle(),
    ));
  }
  throw StateError('同步未启用或提供者不支持');
}

/// 本地文件数超过该值时，哈希切到后台 isolate（否则内联，省 isolate 启动开销）。
const int _hashIsolateThreshold = 20;

/// 在后台 isolate 中计算一批文件的 SHA-256。
///
/// 读取大文件（图片/视频）并算哈希是 CPU + 内存密集——若在主 isolate 执行，
/// 同步期间 UI 会被占满。读取失败（文件被并发删除等）静默跳过，下次同步
/// 自然补齐。
Future<List<({String path, String hash, int size})>> computeLocalHashes(
    String root, List<String> files) async {
  if (files.length < _hashIsolateThreshold) {
    return _hashAllLocal(root, files);
  }
  return Isolate.run(() => _hashAllLocal(root, files));
}

/// 逐文件读取并计算 SHA-256（在后台 isolate 中运行，或小库内联）。
List<({String path, String hash, int size})> _hashAllLocal(
    String root, List<String> files) {
  final out = <({String path, String hash, int size})>[];
  for (final f in files) {
    try {
      final bytes = File(p.join(root, f)).readAsBytesSync();
      out.add((path: f, hash: sha256Hex(bytes), size: bytes.length));
    } catch (_) {
      // 读取失败跳过；与磁盘事实不冲突，下次同步会重新尝试。
    }
  }
  return out;
}

/// 资产文件（uuid 命名、落盘后不原地改写）才可安全地用 size+mtime 缓存跳过。
bool _isAsset(String path) => path.startsWith('assets/');
