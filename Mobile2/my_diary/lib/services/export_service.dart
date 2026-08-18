import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart'; // Archive / ZipEncoder / ZipFileEncoder

/// 导出工具。
///
/// 所有导出都在**后台 isolate**（[Isolate.run]）中执行：压缩是 CPU 密集
/// 操作，若在主 isolate 同步跑会把 UI 线程卡死。丢到后台 isolate 后
/// UI 保持流畅，导出只是"慢一点"。
class ExportService {
  /// 构建「Markdown 备份」zip：`entries/**/*.md` + `settings.json`
  /// + 正文引用到的资产文件。
  ///
  /// 资产引用会**改写为相对 .md 文件所在目录**的路径
  /// （如 `../../../assets/images/x.webp`），解压后在 Typora/Obsidian 等
  /// 编辑器中直接打开 .md 即可正常显示图片；zip 内资产仍按 vault 根
  /// 相对位置存放（`assets/...`），与改写后的引用路径对应。
  /// 返回 zip 字节；vault 中没有 .md 时返回 null。
  static Future<Uint8List?> buildMarkdownZip(String vaultRoot) async {
    return Isolate.run(() => _buildMarkdownZipSync(vaultRoot));
  }

  /// 完整备份（流式）：entries / assets / versions / conflicts /
  /// settings.json / metadata/index.json 打包为 zip，逐文件流式压缩，
  /// 数据不整体载入内存；排除 `metadata/sync.json`；压缩级别 1（最快档）。
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
        final text = utf8.decode(bytes, allowMalformed: true);
        // 先按原始 vault 相对路径收集引用，再把正文中的引用
        // 改写为相对 .md 所在目录的路径（frontmatter 保持原样），最后写入 zip。
        referenced.addAll(_collectAssetRefs(text));
        final rewritten = _rewriteBodyAssetRefs(text, _relativePrefix(rel));
        final out = utf8.encode(rewritten);
        zip.addFile(ArchiveFile(rel, out.length, out));
      }
    }
    final settingsFile = File('$vaultRoot/settings.json');
    if (settingsFile.existsSync()) {
      final bytes = settingsFile.readAsBytesSync();
      zip.addFile(ArchiveFile('settings.json', bytes.length, bytes));
    }
    // 被引用的资产一并打入 zip（保持 vault 根相对位置，文件存在才打包）。
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
      // 必须用同步 addFileSync：addFile 是 async（内部 await 文件流关闭），
      // 在同步函数里不 await 会 fire-and-forget，close 时数据未写完 → 1kb 空包。
      if (rel.toLowerCase().endsWith('.md')) {
        // .md：改写正文资产引用为相对路径（Typora 直接打开单个文件即可看图），
        // frontmatter 保持 vault 根相对原样（App 还原时按原路径解析）。
        final bytes = e.readAsBytesSync();
        final text = utf8.decode(bytes, allowMalformed: true);
        final rewritten = _rewriteBodyAssetRefs(text, _relativePrefix(rel));
        final out = utf8.encode(rewritten);
        encoder.addArchiveFile(ArchiveFile(rel, out.length, out));
      } else {
        encoder.addFileSync(e, rel);
      }
      count++;
    }
    encoder.closeSync(); // 同步 close，确保数据全部落盘
    return count;
  }

  static String _rel(String vaultRoot, String p) =>
      p.substring(vaultRoot.length + 1).replaceAll('\\', '/');

  /// md 相对 vault 根的目录层级数，生成对应数量的 `../`（资产在 vault 根）。
  /// `entries/2026/08/xxx.md` → 3 层 → `../../../`。
  static String _relativePrefix(String mdRel) {
    final dirs = mdRel.split('/').length - 1;
    return '../' * dirs;
  }

  /// 只改写**正文**（frontmatter 结束标记 `---` 之后）中的资产引用；
  /// frontmatter（`assets`/`path` 元数据）保持 vault 根相对原样，
  /// 供 App 按原路径解析（还原/导入不破坏）。
  static String _rewriteBodyAssetRefs(String text, String prefix) {
    if (!text.startsWith('---')) return _prefixAssetRefs(text, prefix);
    final end = text.indexOf('\n---', 3); // frontmatter 的结束 `---` 行
    if (end < 0) return _prefixAssetRefs(text, prefix);
    final head = text.substring(0, end + 4); // 含 `---\n` 结束标记
    final body = text.substring(end + 4);
    return head + _prefixAssetRefs(body, prefix);
  }

  /// 把文本中的 vault 相对资产引用改写为相对 .md 所在目录的路径：
  /// - 图片：`![alt](assets/...` → `![alt](../../../assets/...`
  /// - 附件 / frontmatter：`"assets/...` → `"../../../assets/...`
  ///   （`data-src="assets/` 与 `path: "assets/` 里的 `"assets/` 一并命中）
  static String _prefixAssetRefs(String text, String prefix) {
    var out = text.replaceAll('](assets/', '](${prefix}assets/');
    return out.replaceAll('"assets/', '"${prefix}assets/');
  }

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
