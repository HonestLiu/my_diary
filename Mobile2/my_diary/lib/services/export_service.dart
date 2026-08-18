import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart'; // ZipFileEncoder / ArchiveFile

/// 导出工具。
///
/// 所有导出都在**后台 isolate**（[Isolate.run]）中执行：压缩是 CPU 密集
/// 操作，若在主 isolate 同步跑会把 UI 线程卡死。丢到后台 isolate 后
/// UI 保持流畅，导出只是"慢一点"。
class ExportService {
  /// 完整备份（流式）：entries / assets / versions / conflicts /
  /// settings.json / metadata/index.json 打包为 zip，逐文件流式压缩，
  /// 数据不整体载入内存；排除 `metadata/sync.json`；压缩级别 1（最快档）。
  ///
  /// 其中 `.md` 的正文资产引用会改写为相对文件所在目录的路径
  /// （如 `../../../assets/images/x.webp`），解压后在 Typora 等编辑器中
  /// 直接打开单个 .md 即可正常显示图片；frontmatter 保持 vault 根相对
  /// 原样（App 还原时按原路径解析）。
  /// 返回写入的文件数。
  static Future<int> buildFullZip(String vaultRoot, String zipPath) async {
    return Isolate.run(() => _buildFullZipSync(vaultRoot, zipPath));
  }

  // -------------------------------------------------------------------------
  // 以下为 isolate 内执行的同步实现（Isolate.run 闭包只捕获可发送的值）。
  // -------------------------------------------------------------------------

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
  /// - 附件：`"assets/...` → `"../../../assets/...`
  ///   （`data-src="assets/` 里的 `"assets/` 一并命中）
  static String _prefixAssetRefs(String text, String prefix) {
    var out = text.replaceAll('](assets/', '](${prefix}assets/');
    return out.replaceAll('"assets/', '"${prefix}assets/');
  }
}
