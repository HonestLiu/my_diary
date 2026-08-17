import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/vault/yaml_frontmatter.dart';

final RegExp _frontmatterRe = RegExp(r'^---\r?\n([\s\S]*?)\r?\n---\r?\n?');
final RegExp _leadingH1Re = RegExp(r'^\s*#\s+[^\n]*\r?\n?');

/// 解析原始 Markdown 文件（含 YAML frontmatter）为结构化 meta + body。
/// 开头的 `# 标题` 行被剥离 —— 规范标题存于 frontmatter，H1 仅为可读性而写。
({JournalMeta meta, String body}) parseEntryFile(String raw,
    {String? fallbackId}) {
  String metaText = '';
  var body = raw;

  final fm = _frontmatterRe.firstMatch(raw);
  if (fm != null && fm.group(1) != null) {
    metaText = fm.group(1)!;
    body = raw.substring(fm.group(0)!.length);
  }

  body = body.replaceFirst(_leadingH1Re, '');
  // Trim leading/trailing whitespace so a `# Title` blank line and trailing
  // newline don't surface as a blank paragraph in the rendered Markdown.
  // Mirrors `serializeEntryFile`, which trims before writing.
  return (meta: parseFrontmatter(metaText, fallbackId: fallbackId), body: body.trim());
}

/// 将条目序列化回磁盘 Markdown 表示。frontmatter 携带元数据；正文以 `# <标题>`
/// 开头便于阅读。本地文件即事实来源 —— 本输出对人类完全可读。
String serializeEntryFile(JournalEntry entry) {
  final yamlStr = encodeFrontmatter(entry);
  final body = entry.body.trim();
  return '---\n$yamlStr\n---\n\n# ${entry.title}\n\n$body\n';
}
