import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:my_diary_mobile/vault/vault_layout.dart';
import 'package:path/path.dart' as p;

/// 本地文件系统存储适配器（移动端磁盘）。
///
/// 传入的路径都「相对于 vault 根」，因此与桌面端使用同一套布局，
/// Markdown 文件可直接移植。镜像桌面端 `StorageAdapter` 契约。
class LocalVault {
  /// vault 根的绝对路径。
  final String root;

  LocalVault(this.root);

  String _abs(String rel) => p.join(root, rel);

  /// 创建 vault 根与所需目录（若不存在）。
  Future<void> init() async {
    await Directory(root).create(recursive: true);
    for (final d in VaultLayout.requiredDirectories) {
      await Directory(_abs(d)).create(recursive: true);
    }
  }

  Future<String> readText(String rel) => File(_abs(rel)).readAsString();

  Future<void> writeText(String rel, String content) async {
    final f = File(_abs(rel));
    await f.parent.create(recursive: true);
    await f.writeAsString(content);
  }

  Future<Uint8List> readBytes(String rel) => File(_abs(rel)).readAsBytes();

  Future<void> writeBytes(String rel, Uint8List data) async {
    final f = File(_abs(rel));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(data);
  }

  Future<bool> exists(String rel) => File(_abs(rel)).exists();

  Future<void> delete(String rel) async {
    final f = File(_abs(rel));
    if (await f.exists()) await f.delete();
  }

  /// 列出 vault 根下（或某 prefix 下）的所有文件，返回相对路径，按字典序排序。
  Future<List<String>> list(String prefix) async {
    final dir = Directory(prefix.isEmpty ? root : _abs(prefix));
    if (!await dir.exists()) return [];
    final out = <String>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final rel = p.relative(entity.path, from: root).replaceAll('\\', '/');
        out.add(rel);
      }
    }
    return out..sort();
  }

  /// 将 vault 相对附件路径解析为本地文件（供 Image.file 等使用）。
  File resolveFile(String relPath) => File(_abs(relPath));

  /// 将 vault 相对附件路径解析为 file:// URI 字符串。
  Future<String> resolveUrl(String relPath) async =>
      Uri.file(_abs(relPath)).toString();
}
