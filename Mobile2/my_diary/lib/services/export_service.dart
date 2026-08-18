import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart'; // Archive / ZipEncoder / ZipFileEncoder

/// 导出工具。
///
/// 所有导出都在**后台 isolate**（[Isolate.run]）中执行：压缩是 CPU 密集
/// 操作，若在主 isolate 同步跑会把 UI 线程卡死（用户体感：手机瞬间卡死）。
/// 丢到后台 isolate 后 UI 保持流畅，导出只是"慢一点"。
class ExportService {
  /// 构建「Markdown 备份」zip：`entries/**/*.md` + `settings.json`
  /// + **正文引用到的资产文件**（保持 vault 根相对路径）。
  ///
  /// 图片/附件在 Markdown 里以 `assets/...` 相对 vault 根引用，若 zip 里
  /// 只有 .md，引用必然悬空。这里把被引用的 assets 一并打包，解压整个
  /// 目录后在 Obsidian 等按库根解析的编辑器中即可正常显示。
  /// 返回 zip 字节；vault 中没有 .md 时返回 null。
  static Future<Uint8List?> buildMarkdownZip(String vaultRoot) async {
    return Isolate.run(() => _buildMarkdownZipSync(vaultRoot));
  }

  /// 完整备份（流式）：把 entries / assets / versions / conflicts /
  /// settings.json / metadata/index.json 打包为 zip，逐文件流式压缩
  /// （InputFileStream 分块读 → ZipEncoder → 输出文件流），数据不整体载入内存。
  /// 排除 `metadata/sync.json`。压缩级别 1（最快档）以降低 CPU 占用。
  /// 返回写入的文件数。
  static Future<int> buildFullZip(String vaultRoot, String zipPath) async {
    return Isolate.run(() => _buildFullZipSync(vaultRoot, zipPath));
  }

  // -------------------------------------------------------------------------
  // 以下为 isolate 内执行的同步实现（Isolate.run 闭包只捕获可发送的值）。
  // -------------------------------------------------------------------------

  static Uint8List? _buildMarkdownZipSync(String vaultRoot) {
    final zip = Archive();
    final referenced = <String>{};
    final entriesDir = Directory('$vaultRoot/entries');
    if (entriesDir.existsSync()) {
      for (final e
          in entriesDir.listSync(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        if (!e.path.toLowerCase().endsWith('.md')) continue;
        final rel = _rel(vaultRoot, e.path);
        final bytes = e.readAsBytesSync();
        zip.addFile(ArchiveFile(rel, bytes.length, bytes));
        // 收集该篇引用的资产（正文图片/附件 + frontmatter path 字段）。
        referenced.addAll(
            _collectAssetRefs(utf8.decode(bytes, allowMalformed: true)));
      }
    }
    final settingsFile = File('$vaultRoot/settings.json');
    if (settingsFile.existsSync()) {
      final bytes = settingsFile.readAsBytesSync();
      zip.addFile(ArchiveFile('settings.json', bytes.length, bytes));
    }
    // 被引用的资产一并打入 zip（保持 vault 根相对路径，文件存在才打包）。
    for (final rel in referenced) {
      final f = File('$vaultRoot/$rel');
      if (!f.existsSync()) continue;
      final bytes = f.readAsBytesSync();
      zip.addFile(ArchiveFile(rel, bytes.length, bytes));
    }
    if (zip.files.isEmpty) return null;
    return Uint8List.fromList(ZipEncoder().encode(zip));
  }

  static int _buildFullZipSync(String vaultRoot, String zipPath) {
    final encoder = ZipFileEncoder();
    encoder.create(zipPath, level: 1); // 1 = 最快档，CPU 占用低（宁慢勿卡）
    var count = 0;
    for (final e
        in Directory(vaultRoot).listSync(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = _rel(vaultRoot, e.path);
      if (rel == 'metadata/sync.json') continue; // 同步状态不导出
      if (rel.startsWith('metadata/') && rel != 'metadata/index.json') {
        continue; // metadata 只带 index.json
      }
      encoder.addFile(e, rel);
      count++;
    }
    encoder.close();
    return count;
  }

  static String _rel(String vaultRoot, String p) =>
      p.substring(vaultRoot.length + 1).replaceAll('\\', '/');

  // 图片：![alt](assets/... "width=600")（路径可含转义括号）
  static final RegExp _imgRefRe =
      RegExp(r'!\[[^\]]*\]\(\s*([^\s)]+)(?:\s+"[^"]*")?\s*\)');
  // 附件：<attachment data-src="assets/..." ...>
  static final RegExp _attachRefRe =
      RegExp(r'<attachment\b[^>]*\bsrc="([^"]+)"', caseSensitive: false);
  // frontmatter 资产：path: "assets/..."
  static final RegExp _fmPathRe =
      RegExp(r'^\s*path:\s*"([^"]+)"', multiLine: true);

  /// 从一篇 Markdown（含 frontmatter）收集「vault 相对资产引用」。
  /// 只保留 `assets/` 前缀的相对路径；http(s) 链接与空引用忽略。
  static Set<String> _collectAssetRefs(String text) {
    final out = <String>{};
    void add(String? raw) {
      if (raw == null || raw.isEmpty) return;
      var rel = raw.replaceAll(r'\(', '(').replaceAll(r'\)', ')');
      if (rel.startsWith('./')) rel = rel.substring(2); // ./assets/... 归一化
      if (rel.startsWith('http://') || rel.startsWith('https://')) return;
      if (!rel.startsWith('assets/')) return;
      out.add(rel);
    }

    for (final m in _imgRefRe.allMatches(text)) {
      add(m.group(1));
    }
    for (final m in _attachRefRe.allMatches(text)) {
      add(m.group(1));
    }
    for (final m in _fmPathRe.allMatches(text)) {
      add(m.group(1));
    }
    return out;
  }
}
