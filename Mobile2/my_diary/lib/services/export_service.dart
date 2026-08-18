import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart'; // Archive / ZipEncoder / ZipFileEncoder

/// 导出工具。
class ExportService {
  /// 构建「Markdown 备份」zip：`entries/**/*.md` + `settings.json`（内存中构建）。
  /// 返回 zip 字节；vault 中没有 .md 时返回 null。
  static Future<Uint8List?> buildMarkdownZip(String vaultRoot) async {
    final zip = Archive();
    final entriesDir = Directory('$vaultRoot/entries');
    if (entriesDir.existsSync()) {
      await for (final e
          in entriesDir.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        if (!e.path.toLowerCase().endsWith('.md')) continue;
        final rel =
            e.path.substring(vaultRoot.length + 1).replaceAll('\\', '/');
        final bytes = await e.readAsBytes();
        zip.addFile(ArchiveFile(rel, bytes.length, bytes));
      }
    }
    final settingsFile = File('$vaultRoot/settings.json');
    if (settingsFile.existsSync()) {
      final bytes = await settingsFile.readAsBytes();
      zip.addFile(ArchiveFile('settings.json', bytes.length, bytes));
    }
    if (zip.files.isEmpty) return null;
    return Uint8List.fromList(ZipEncoder().encode(zip));
  }

  /// 完整备份（流式）：把 entries / assets / versions / conflicts / settings.json /
  /// metadata/index.json 打包为 zip，**逐文件流式压缩**（InputFileStream 分块读 →
  /// ZipEncoder → 输出文件流），数据不整体载入内存，直接进压缩流。
  /// 排除 `metadata/sync.json`（同步状态不随备份迁移）。
  ///
  /// 返回写入的文件数。
  static Future<int> buildFullZip(String vaultRoot, String zipPath) async {
    final encoder = ZipFileEncoder();
    encoder.create(zipPath, level: ZipFileEncoder.gzip);
    var count = 0;
    await for (final e
        in Directory(vaultRoot).list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = e.path.substring(vaultRoot.length + 1).replaceAll('\\', '/');
      if (rel == 'metadata/sync.json') continue; // 同步状态不导出
      if (rel.startsWith('metadata/') && rel != 'metadata/index.json') {
        continue; // metadata 只带 index.json
      }
      await encoder.addFile(e, rel);
      count++;
    }
    await encoder.close();
    return count;
  }
}
