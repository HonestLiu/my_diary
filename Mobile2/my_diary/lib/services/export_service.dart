import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// 导出工具：把 vault 中的 Markdown 日记与设置打包为 zip（内存中构建）。
/// 目录结构保持与 vault 一致（entries/YYYY/MM/...md + settings.json），
/// 解压后即为可直接阅读的明文日记库。
class ExportService {
  /// 构建「Markdown 备份」zip：`entries/**/*.md` + `settings.json`。
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
}
