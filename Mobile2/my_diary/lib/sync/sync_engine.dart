import 'dart:convert';

import 'package:my_diary_mobile/models/sync_types.dart';
import 'package:my_diary_mobile/sync/auth_service.dart';
import 'package:my_diary_mobile/sync/crypto.dart';
import 'package:my_diary_mobile/sync/remote_storage.dart';
import 'package:my_diary_mobile/vault/local_vault.dart';
import 'package:my_diary_mobile/vault/vault_layout.dart';
import 'package:my_diary_mobile/s3_remote.dart';
import 'package:my_diary_mobile/sync/cloud_remote.dart';

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
    if (path.startsWith('${VaultLayout.conflicts}/')) return false;
    return true;
  }

  Future<({String hash, int size})> _hashFile(String path) async {
    final bytes = await storage.readBytes(path);
    return (hash: sha256Hex(bytes), size: bytes.length);
  }

  /// 扫描整个 vault，构建当前本地清单（仅内容范围）。
  Future<SyncManifest> buildLocalManifest() async {
    final files = (await storage.list(''))
        .where(shouldSync)
        .toList();
    final syncFiles = <SyncFile>[];
    for (final f in files) {
      final hs = await _hashFile(f);
      syncFiles.add(SyncFile(
        path: f,
        hash: hs.hash,
        size: hs.size,
        updated: DateTime.now().millisecondsSinceEpoch,
      ));
    }
    return SyncManifest(
      deviceId: deviceId,
      files: syncFiles,
      generatedAt: DateTime.now().millisecondsSinceEpoch,
    );
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
        publicConfig.bucket == null ||
        publicConfig.region == null) {
      throw StateError('对象存储凭据不完整，无法同步');
    }
    return S3StorageProvider(S3Config(
      endpoint: publicConfig.endpoint!,
      bucket: publicConfig.bucket!,
      region: publicConfig.region!,
      accessKey: accessKey,
      secretKey: secretKey,
      pathStyle: publicConfig.pathStyle ?? false,
    ));
  }
  throw StateError('同步未启用或提供者不支持');
}
