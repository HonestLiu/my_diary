import 'dart:typed_data';

import 'package:my_diary_mobile/models/sync_types.dart';

/// 远程存储抽象（provider 无关），镜像桌面端 `StorageProvider` 契约。
///
/// 路径传入「相对于 vault 根（或用户命名空间）」的键，因此同一套同步引擎可作用于
/// 直接对象存储或云服务预签名两种后端。
abstract class RemoteStorage {
  String get name;

  Future<void> upload(String remotePath, Uint8List data);
  Future<Uint8List> download(String remotePath);
  Future<void> delete(String remotePath);

  /// 列出对象（可选 prefix）。返回相对键。
  Future<List<String>> list([String prefix = '']);

  /// 获取远程同步清单（若存在）。
  Future<SyncManifest?> fetchManifest();

  /// 推送同步清单到远程。
  Future<void> pushManifest(SyncManifest manifest);
}
