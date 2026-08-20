import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

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
/// 协议（与桌面端 Rust `sync_vault` / `resolve_conflict` 一致）：
///   1. 扫描本地文件，计算 SHA-256 + size
///   2. 获取远程清单（metadata/sync.json）
///   3. 对比本机基线（上次同步）+ 当前本地
///   4. 上传 / 下载差异文件
///   5. 某文件自上次同步起两侧都被修改 → 冲突（写 conflicts/<...>.{local,remote}.md，
///      记录到 metadata/conflicts.json 待解决列表，保持本地为主文件，由用户显式解决）
///
/// 健壮性设计（此前「动不动就冲突」的根因修复）：
///   - 远端清单始终反映「桶内真实对象」，绝不写入单台设备的本地视图 —— 避免两台
///     设备互相踩踏清单、产生虚假冲突。
///   - 首次同步（无本机基线）不判冲突：没有共同基线就谈不上「两侧各自变更」，
///     以远端为准采纳，本地不同版本保留为冲突安全副本。
///   - 只对「成功对账」的路径推进基线；清单推送失败时回退上传路径的基线，下次同步
///     重传并自愈，绝不把自己刚上传的内容再下载回来覆盖。
///
/// 内容范围：仅同步日记数据（entries/、assets/、versions/、profile/），
/// 排除 settings.json、metadata/*、conflicts/，避免设备专属配置、凭据与本机基线跨设备互覆。
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
    if (path == VaultLayout.conflictsIndex) return false; // 待解决冲突索引，设备本地
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
  /// 待解决冲突的路径不计入（它们不是「未同步」，而是需要用户显式解决，同步不会
  /// 清除），避免出现「无论怎么同步都显示未同步」的假象。
  /// 仅本地计算，不发起任何网络请求。
  Future<Set<String>> unsyncedPaths() async {
    final local = await buildLocalManifest();
    final baseline = await readLocalBaseline();
    final baseHash = {
      for (final f in baseline?.files ?? []) f.path: f.hash,
    };
    final pending = await _loadPendingConflicts();
    return {
      for (final f in local.files)
        if (baseHash[f.path] != f.hash && !pending.contains(f.path)) f.path,
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
    final remoteObjects = (await remote.list('')).where(shouldSync).toSet();
    final remoteManifest = await remote.fetchManifest();

    // 上次推送的远程清单：只用作「远端上次记录的状态」参照。同步循环之后，我们
    // 重新从「桶内真实对象 + 本次确认结果」构建新清单，绝不把单台设备的本地视图
    // 原样写回 —— 那正是此前两台设备互相踩踏、误报冲突的根源。
    final oldManifestHash = Map<String, String>.fromEntries(
      (remoteManifest?.files ?? [])
          .where((f) => shouldSync(f.path))
          .map((f) => MapEntry(f.path, f.hash)),
    );
    final baseline = await readLocalBaseline();
    final oldBaselineMap = Map<String, SyncFile>.fromEntries(
        (baseline?.files ?? []).map((f) => MapEntry(f.path, f)));
    final pendingConflicts = await _loadPendingConflicts();

    final localMap = Map.fromEntries(local.files.map((f) => MapEntry(f.path, f)));

    // 本次同步后的「正确远端状态」：始终反映桶内真实对象。
    final newManifestHash = <String, String>{};
    // 本次同步后的本机基线：只推进「成功对账」的路径；失败路径保留旧值以便重试。
    final newBaseline = Map<String, SyncFile>.from(oldBaselineMap);
    // 本次成功上传的路径：若清单推送失败，需回退这些路径的基线，否则下次同步会把
    // 自己刚上传的内容误判成「远端变更」再下载回来覆盖。
    final uploadedPaths = <String>[];
    var changed = false;

    final result = SyncResult();
    final allPaths = <String>{...localMap.keys, ...remoteObjects};

    for (final path in allPaths) {
      if (!shouldSync(path)) continue;
      final l = localMap[path];
      final exists = remoteObjects.contains(path);
      final prevR = oldManifestHash[path];
      final prevB = oldBaselineMap[path];
      // 冲突尚未解决：保持本地为主文件（冲突副本已保存两侧），绝不自动覆盖。
      if (l != null && exists && pendingConflicts.contains(path)) {
        continue;
      }
      try {
        if (l != null && !exists) {
          // 本地新增 → 上传。
          await remote.upload(path, await storage.readBytes(path));
          newBaseline[path] = l;
          newManifestHash[path] = l.hash;
          uploadedPaths.add(path);
          result.uploaded.add(path);
          changed = true;
        } else if (l == null && exists) {
          // 远端新增 → 下载。
          final data = await remote.download(path);
          await storage.writeBytes(path, data);
          final h = sha256Hex(data);
          newBaseline[path] = _syncFile(path, h, data.length);
          newManifestHash[path] = h;
          result.downloaded.add(path);
          changed = true;
        } else if (l != null && exists) {
          // 两侧都存在：与远端清单记录一致 → 未变更。
          if (prevR == l.hash) {
            newBaseline[path] = l;
            newManifestHash[path] = l.hash;
            continue;
          }
          if (prevB == null) {
            // 本机从未同步过该路径（首次采纳）：没有共同基线，就谈不上「两侧各自
            // 变更」，绝不能一上来就批量判冲突。以远端为准下载；本地版本若不同则
            // 保留为冲突安全副本（conflicts/ 不参与同步，不会污染其他设备），但不
            // 作为需要人工处理的冲突上报。
            final localData = await storage.readBytes(path);
            final data = await remote.download(path);
            final h = sha256Hex(data);
            if (h != sha256Hex(localData)) {
              // 保留本地版本为安全副本（conflicts/ 不参与同步）。用 .replaced 后缀，
              // 避免被移动端「待解决冲突」列表误判成需要人工处理的冲突。
              await _writeConflictSide(path, 'replaced', localData);
            }
            await storage.writeBytes(path, data);
            newBaseline[path] = _syncFile(path, h, data.length);
            newManifestHash[path] = h;
            result.downloaded.add(path);
            changed = true;
            continue;
          }
          final localChanged = prevB.hash != l.hash;
          // 远端是否变更 = 本次清单哈希 与 本机基线哈希 是否不同；清单缺失时无法
          // 证明远端未变，保守视为已变（避免静默覆盖），但这只影响单个文件。
          final remoteChanged = prevR == null || prevB.hash != prevR;
          if (localChanged && remoteChanged) {
            // 两侧自上次同步起都变更 → 冲突：写冲突副本，绝不覆盖。
            final localData = await storage.readBytes(path);
            final remoteData = await remote.download(path);
            final key = conflictKeyFromPath(path);
            await storage.writeBytes(conflictFilePath(key, 'local'), localData);
            await storage.writeBytes(conflictFilePath(key, 'remote'), remoteData);
            // 清单必须反映桶内真实状态：记远端哈希，而不是被踩踏成本地视图。
            final rh = sha256Hex(remoteData);
            newBaseline[path] = l;
            newManifestHash[path] = rh;
            pendingConflicts.add(path);
            result.conflicts.add(SyncConflict(
              path: path,
              local: l,
              remote: _syncFile(path, rh, remoteData.length),
            ));
            changed = true;
          } else if (localChanged) {
            await remote.upload(path, await storage.readBytes(path));
            newBaseline[path] = l;
            newManifestHash[path] = l.hash;
            uploadedPaths.add(path);
            result.uploaded.add(path);
            changed = true;
          } else {
            // 仅远端变更（或清单缺失但本机有基线）→ 下载，远端在此处为准。
            final data = await remote.download(path);
            await storage.writeBytes(path, data);
            final h = sha256Hex(data);
            newBaseline[path] = _syncFile(path, h, data.length);
            newManifestHash[path] = h;
            result.downloaded.add(path);
            changed = true;
          }
        }
      } catch (e) {
        result.errors.add('$path: $e');
      }
    }

    // 清单保持「桶内全量」：对本次未触碰的远端对象，沿用上次已知哈希。
    for (final p in remoteObjects) {
      if (!newManifestHash.containsKey(p)) {
        final h = oldManifestHash[p];
        if (h != null) newManifestHash[p] = h;
      }
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (changed) {
      // 先推清单、再落基线：清单写成功，上传路径的远端状态才算被确认，基线可完整
      // 推进；清单写失败则回退上传路径的基线，让下次同步重传并自愈。
      final newManifest = SyncManifest(
        deviceId: deviceId,
        files: [
          for (final e in newManifestHash.entries)
            SyncFile(path: e.key, hash: e.value, size: 0, updated: nowMs),
        ],
        generatedAt: nowMs,
      );
      try {
        await remote.pushManifest(newManifest);
        await _writeBaseline(newBaseline, nowMs);
      } catch (e) {
        result.errors.add('manifest: $e');
        final reverted = Map<String, SyncFile>.from(newBaseline);
        for (final p in uploadedPaths) {
          final ob = oldBaselineMap[p];
          if (ob != null) {
            reverted[p] = ob;
          } else {
            reverted.remove(p);
          }
        }
        await _writeBaseline(reverted, nowMs);
      }
    } else if (!_sameBaseline(newBaseline, oldBaselineMap)) {
      // 没有上传/下载/冲突，但可能记录了「首次采纳」的基线（本地与远端一致的路径），
      // 仅在确有差异时落盘。
      await _writeBaseline(newBaseline, nowMs);
    }
    await _savePendingConflicts(pendingConflicts);
    return result;
  }

  Future<Set<String>> _loadPendingConflicts() async {
    if (!(await storage.exists(VaultLayout.conflictsIndex))) return {};
    try {
      final raw = await storage.readText(VaultLayout.conflictsIndex);
      final list = (jsonDecode(raw) as List<dynamic>? ?? [])
          .whereType<String>()
          .toList();
      return list.toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _savePendingConflicts(Set<String> pending) async {
    try {
      await storage.writeText(
        VaultLayout.conflictsIndex,
        jsonEncode(pending.toList()..sort()),
      );
    } catch (_) {/* 待解决索引写失败不影响主流程，下次同步会重新记录 */}
  }

  SyncFile _syncFile(String path, String hash, int size) => SyncFile(
        path: path,
        hash: hash,
        size: size,
        updated: DateTime.now().millisecondsSinceEpoch,
      );

  Future<void> _writeBaseline(Map<String, SyncFile> map, int nowMs) async {
    await writeLocalBaseline(SyncManifest(
      deviceId: deviceId,
      files: map.values.toList(),
      generatedAt: nowMs,
    ));
  }

  bool _sameBaseline(Map<String, SyncFile> a, Map<String, SyncFile> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      final o = b[e.key];
      if (o == null || o.hash != e.value.hash || o.size != e.value.size) {
        return false;
      }
    }
    return true;
  }

  Future<void> _writeConflictSide(
      String path, String side, Uint8List data) async {
    final key = conflictKeyFromPath(path);
    await storage.writeBytes(conflictFilePath(key, side), data);
  }

  Future<void> _downloadAndStore(String path) async {
    final data = await remote.download(path);
    await storage.writeBytes(path, data);
  }

  /// 解决已检测到的冲突。"local" 推送本地副本；"remote" 用远程副本覆盖本地。
  /// 冲突副本被移除，该路径从待解决列表摘除，基线与本机可见的远端清单都刷新为
  /// 已解决状态，避免下次同步又把该路径误判成冲突或覆盖回去。
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
    final pending = await _loadPendingConflicts();
    pending.remove(path);
    await _savePendingConflicts(pending);

    final baseline = await readLocalBaseline() ??
        SyncManifest(
          deviceId: deviceId,
          files: [],
          generatedAt: DateTime.now().millisecondsSinceEpoch,
        );
    final map = Map.fromEntries(baseline.files.map((f) => MapEntry(f.path, f)));
    final bytes = await storage.readBytes(path);
    final resolved = SyncFile(
      path: path,
      hash: sha256Hex(bytes),
      size: bytes.length,
      updated: DateTime.now().millisecondsSinceEpoch,
    );
    map[path] = resolved;
    await writeLocalBaseline(SyncManifest(
      deviceId: baseline.deviceId,
      files: map.values.toList(),
      generatedAt: DateTime.now().millisecondsSinceEpoch,
    ));

    // 让远端清单也反映已解决状态（否则下次同步会以为远端又变了）。
    // 清单推送失败不阻塞本地解决流程——本地已收敛到选定版本，清单下次同步会自愈。
    try {
      final manifest = await remote.fetchManifest();
      final files = (manifest?.files ?? []).where((f) => f.path != path).toList()
        ..add(resolved);
      await remote.pushManifest(SyncManifest(
        deviceId: deviceId,
        files: files,
        generatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    } catch (_) {
      // 静默：本地基线已更新，下次同步会自愈。
    }
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
