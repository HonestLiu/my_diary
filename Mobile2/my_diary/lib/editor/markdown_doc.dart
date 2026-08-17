import 'package:my_diary_mobile/editor/doc_model.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';

/// Markdown ⇄ 文档模型 的双向编解码。
///
/// **落盘形态必须与桌面端（TipTap + tiptap-markdown）逐字对齐**，否则两端互通即破：
/// - 行内：`**加粗**`、`*斜体*`、`~~删除线~~`、`` `代码` ``、`<u>下划线</u>`
///   （下划线走内联 HTML，因为桌面端 `Markdown` 扩展以 `html: true` 运行）
/// - 图片：`![alt](assets/images/x.jpg "width=600")`
///   （宽度写进 Markdown 图片 title，见桌面 `ResolvedImage.addStorage`）
/// - 音频 / 视频 / 附件：`<attachment data-src=… data-name=… data-kind=… data-size=…></attachment>`
///   （见桌面 `Attachment` 节点的 parseHTML / renderHTML）
/// - 资产引用一律 **vault 根相对**（`assets/<kind>/<file>`）。

// ---------------------------------------------------------------------------
// 行内：解码
// ---------------------------------------------------------------------------

class InlineText {
  final String text;
  final List<InlineMark> marks;
  const InlineText(this.text, this.marks);
}

final RegExp _wordChar = RegExp(r'[0-9A-Za-z]');

/// `_` / `__` 只在非词内位置才当作强调分隔符（与 prosemirror-markdown 的转义规则镜像）。
bool _underscoreIsDelimiter(String raw, int i, int width) {
  final prev = i > 0 ? raw[i - 1] : ' ';
  final nextIdx = i + width;
  final next = nextIdx < raw.length ? raw[nextIdx] : ' ';
  return !(_wordChar.hasMatch(prev) && _wordChar.hasMatch(next));
}

/// 把一行（或多行）Markdown 行内文本解析成「纯文本 + 标记区间」。
InlineText decodeInline(String raw) {
  final sb = StringBuffer();
  var len = 0;
  final marks = <InlineMark>[];
  final pending = <MarkKind, int>{};

  void push(String s) {
    sb.write(s);
    len += s.length;
  }

  void toggle(MarkKind kind) {
    final opened = pending.remove(kind);
    if (opened != null) {
      if (len > opened) marks.add(InlineMark(kind, opened, len));
    } else {
      pending[kind] = len;
    }
  }

  var i = 0;
  while (i < raw.length) {
    final c = raw[i];

    // 反斜杠转义
    if (c == '\\' && i + 1 < raw.length) {
      push(raw[i + 1]);
      i += 2;
      continue;
    }

    // 行内代码：`code` / ``co`de``
    if (c == '`') {
      var fenceLen = 0;
      while (i + fenceLen < raw.length && raw[i + fenceLen] == '`') {
        fenceLen++;
      }
      final fence = '`' * fenceLen;
      final close = raw.indexOf(fence, i + fenceLen);
      if (close > 0) {
        var content = raw.substring(i + fenceLen, close);
        if (content.length >= 2 &&
            content.startsWith(' ') &&
            content.endsWith(' ')) {
          content = content.substring(1, content.length - 1);
        }
        if (content.isNotEmpty) {
          marks.add(InlineMark(MarkKind.code, len, len + content.length));
          push(content);
        }
        i = close + fenceLen;
        continue;
      }
    }

    // 下划线（内联 HTML）
    if (raw.startsWith('<u>', i)) {
      toggle(MarkKind.underline);
      i += 3;
      continue;
    }
    if (raw.startsWith('</u>', i)) {
      toggle(MarkKind.underline);
      i += 4;
      continue;
    }

    if (raw.startsWith('~~', i)) {
      toggle(MarkKind.strike);
      i += 2;
      continue;
    }
    if (raw.startsWith('**', i)) {
      toggle(MarkKind.bold);
      i += 2;
      continue;
    }
    if (raw.startsWith('__', i) && _underscoreIsDelimiter(raw, i, 2)) {
      toggle(MarkKind.bold);
      i += 2;
      continue;
    }
    if (c == '*') {
      toggle(MarkKind.italic);
      i += 1;
      continue;
    }
    if (c == '_' && _underscoreIsDelimiter(raw, i, 1)) {
      toggle(MarkKind.italic);
      i += 1;
      continue;
    }

    push(c);
    i++;
  }

  // 未闭合的分隔符：作用到行尾（比丢弃更符合直觉）
  for (final entry in pending.entries) {
    if (len > entry.value) {
      marks.add(InlineMark(entry.key, entry.value, len));
    }
  }

  final text = sb.toString();
  return InlineText(text, normalizeMarks(marks, text.length));
}

// ---------------------------------------------------------------------------
// 行内：编码
// ---------------------------------------------------------------------------

final RegExp _escapeChars = RegExp(r'[`*\\~\[\]<]');

String _escapeInline(String s) {
  final sb = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '_') {
      final prev = i > 0 ? s[i - 1] : '';
      final next = i + 1 < s.length ? s[i + 1] : '';
      final intraWord = _wordChar.hasMatch(prev) && _wordChar.hasMatch(next);
      sb.write(intraWord ? '_' : r'\_');
      continue;
    }
    if (_escapeChars.hasMatch(c)) sb.write('\\');
    sb.write(c);
  }
  return sb.toString();
}

String _wrapCodeSpan(String s) {
  if (!s.contains('`')) return '`$s`';
  var fence = '``';
  while (s.contains(fence)) {
    fence += '`';
  }
  final pad = (s.startsWith('`') || s.endsWith('`')) ? ' ' : '';
  return '$fence$pad$s$pad$fence';
}

String _wrapSegment(String raw, Set<MarkKind> kinds) {
  if (kinds.isEmpty) return _escapeInline(raw);

  // 强调符号不能包裹首尾空白，把空白挪到分隔符外面。
  final leadMatch = RegExp(r'^\s*').firstMatch(raw)!.group(0)!;
  final trailMatch = RegExp(r'\s*$').firstMatch(raw)!.group(0)!;
  final coreEnd = raw.length - trailMatch.length;
  if (coreEnd <= leadMatch.length) return _escapeInline(raw);
  final core = raw.substring(leadMatch.length, coreEnd);

  var body = kinds.contains(MarkKind.code)
      ? _wrapCodeSpan(core)
      : _escapeInline(core);
  if (kinds.contains(MarkKind.underline)) body = '<u>$body</u>';
  if (kinds.contains(MarkKind.strike)) body = '~~$body~~';
  if (kinds.contains(MarkKind.italic)) body = '*$body*';
  if (kinds.contains(MarkKind.bold)) body = '**$body**';
  return '${_escapeInline(leadMatch)}$body${_escapeInline(trailMatch)}';
}

/// 把「纯文本 + 标记区间」编码为 Markdown 行内文本。
String encodeInline(String text, List<InlineMark> marks) {
  if (text.isEmpty) return '';
  final norm = normalizeMarks(marks, text.length);
  if (norm.isEmpty) return _escapeInline(text);

  final cuts = <int>{0, text.length};
  for (final m in norm) {
    cuts.add(m.start);
    cuts.add(m.end);
  }
  final points = cuts.toList()..sort();

  // 先切段并合并「标记集合相同」的相邻段，避免产生 `**a****b**` 这类冗余。
  final segments = <({int start, int end, Set<MarkKind> kinds})>[];
  for (var i = 0; i < points.length - 1; i++) {
    final s = points[i];
    final e = points[i + 1];
    if (e <= s) continue;
    final kinds = norm
        .where((m) => m.start <= s && m.end >= e)
        .map((m) => m.kind)
        .toSet();
    if (segments.isNotEmpty &&
        _sameKinds(segments.last.kinds, kinds) &&
        segments.last.end == s) {
      final last = segments.removeLast();
      segments.add((start: last.start, end: e, kinds: last.kinds));
    } else {
      segments.add((start: s, end: e, kinds: kinds));
    }
  }

  final sb = StringBuffer();
  for (final seg in segments) {
    sb.write(_wrapSegment(text.substring(seg.start, seg.end), seg.kinds));
  }
  return sb.toString();
}

bool _sameKinds(Set<MarkKind> a, Set<MarkKind> b) =>
    a.length == b.length && a.containsAll(b);

// ---------------------------------------------------------------------------
// 块级：解码
// ---------------------------------------------------------------------------

final RegExp _fenceOpenRe = RegExp(r'^\s*(?:```|~~~)\s*([A-Za-z0-9+#._-]*)\s*$');
final RegExp _fenceCloseRe = RegExp(r'^\s*(?:```|~~~)\s*$');
final RegExp _dividerRe = RegExp(r'^\s*(?:-\s*){3,}$|^\s*(?:\*\s*){3,}$|^\s*(?:_\s*){3,}$');
final RegExp _headingRe = RegExp(r'^\s{0,3}(#{1,6})\s+(.*)$');
final RegExp _quoteRe = RegExp(r'^\s{0,3}>\s?(.*)$');
final RegExp _todoRe = RegExp(r'^\s*[-*+]\s+\[([ xX])\]\s*(.*)$');
final RegExp _bulletRe = RegExp(r'^\s*[-*+]\s+(.*)$');
final RegExp _numberedRe = RegExp(r'^\s*\d+[.)]\s+(.*)$');
final RegExp _imageLineRe =
    RegExp(r'^!\[([^\]]*)\]\(\s*([^\s)]+)(?:\s+"([^"]*)")?\s*\)$');
final RegExp _attachmentLineRe =
    RegExp(r'^<attachment\b([^>]*?)/?>\s*(?:</attachment>)?$',
        caseSensitive: false);
final RegExp _attrRe =
    RegExp('''([A-Za-z][A-Za-z0-9-]*)\\s*=\\s*(?:"([^"]*)"|'([^']*)')''');
final RegExp _widthTitleRe = RegExp(r'^width=(\d+)$');

String _unescapeHtml(String s) => s
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

DocBlock? _tryDecodeMediaLine(String line) {
  final img = _imageLineRe.firstMatch(line);
  if (img != null) {
    final alt = img.group(1) ?? '';
    final src = (img.group(2) ?? '').replaceAll(r'\(', '(').replaceAll(r'\)', ')');
    if (src.isEmpty) return null;
    final title = img.group(3);
    final w = title == null ? null : _widthTitleRe.firstMatch(title);
    return DocBlock.media(MediaPayload(
      kind: AssetKind.image,
      src: src,
      name: src.split('/').last,
      alt: alt,
      width: w == null ? null : int.tryParse(w.group(1)!),
    ));
  }

  final att = _attachmentLineRe.firstMatch(line);
  if (att != null) {
    final attrs = <String, String>{};
    for (final m in _attrRe.allMatches(att.group(1) ?? '')) {
      attrs[m.group(1)!.toLowerCase()] =
          _unescapeHtml(m.group(2) ?? m.group(3) ?? '');
    }
    final src = attrs['data-src'] ?? attrs['src'] ?? '';
    if (src.isEmpty) return null;
    final kindName = attrs['data-kind'] ?? attrs['kind'] ?? 'attachment';
    final kind = AssetKind.values.asNameMap()[kindName] ?? AssetKind.attachment;
    final sizeRaw = attrs['data-size'] ?? attrs['size'] ?? '0';
    final widthRaw = attrs['data-width'] ?? attrs['width'];
    return DocBlock.media(MediaPayload(
      kind: kind,
      src: src,
      name: attrs['data-name'] ?? attrs['name'] ?? src.split('/').last,
      size: int.tryParse(sizeRaw) ?? 0,
      width: widthRaw == null ? null : int.tryParse(widthRaw),
    ));
  }
  return null;
}

/// Markdown 正文 → 块列表。
List<DocBlock> decodeMarkdown(String markdown) {
  final lines = markdown.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final blocks = <DocBlock>[];
  final paragraph = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    final raw = paragraph.join('\n');
    paragraph.clear();
    final inline = decodeInline(raw);
    if (inline.text.trim().isEmpty) return;
    blocks.add(DocBlock(
      kind: BlockKind.paragraph,
      text: inline.text,
      marks: inline.marks,
    ));
  }

  DocBlock textBlock(BlockKind kind, String raw, {bool checked = false}) {
    final inline = decodeInline(raw);
    return DocBlock(
      kind: kind,
      text: inline.text,
      marks: inline.marks,
      checked: checked,
    );
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final trimmed = line.trim();

    if (trimmed.isEmpty) {
      flushParagraph();
      i++;
      continue;
    }

    // 围栏代码块
    final fence = _fenceOpenRe.firstMatch(line);
    if (fence != null) {
      flushParagraph();
      final lang = (fence.group(1) ?? '').trim();
      final buf = <String>[];
      i++;
      while (i < lines.length && !_fenceCloseRe.hasMatch(lines[i])) {
        buf.add(lines[i]);
        i++;
      }
      if (i < lines.length) i++; // 吃掉收尾围栏
      blocks.add(DocBlock(
        kind: BlockKind.code,
        text: buf.join('\n'),
        language: lang.isEmpty ? null : lang,
      ));
      continue;
    }

    if (_dividerRe.hasMatch(line)) {
      flushParagraph();
      blocks.add(DocBlock.divider());
      i++;
      continue;
    }

    final media = _tryDecodeMediaLine(trimmed);
    if (media != null) {
      flushParagraph();
      blocks.add(media);
      i++;
      continue;
    }

    final heading = _headingRe.firstMatch(line);
    if (heading != null) {
      flushParagraph();
      final level = heading.group(1)!.length;
      final kind = level <= 1
          ? BlockKind.heading1
          : (level == 2 ? BlockKind.heading2 : BlockKind.heading3);
      blocks.add(textBlock(kind, heading.group(2)!.trim()));
      i++;
      continue;
    }

    final quote = _quoteRe.firstMatch(line);
    if (quote != null) {
      flushParagraph();
      final buf = <String>[quote.group(1)!.trimRight()];
      i++;
      while (i < lines.length) {
        final next = _quoteRe.firstMatch(lines[i]);
        if (next == null) break;
        buf.add(next.group(1)!.trimRight());
        i++;
      }
      blocks.add(textBlock(BlockKind.quote, buf.join('\n').trim()));
      continue;
    }

    final todo = _todoRe.firstMatch(line);
    if (todo != null) {
      flushParagraph();
      final done = todo.group(1)!.toLowerCase() == 'x';
      blocks.add(
          textBlock(BlockKind.todo, todo.group(2)!.trim(), checked: done));
      i++;
      continue;
    }

    final bullet = _bulletRe.firstMatch(line);
    if (bullet != null) {
      flushParagraph();
      blocks.add(textBlock(BlockKind.bullet, bullet.group(1)!.trim()));
      i++;
      continue;
    }

    final numbered = _numberedRe.firstMatch(line);
    if (numbered != null) {
      flushParagraph();
      blocks.add(textBlock(BlockKind.numbered, numbered.group(1)!.trim()));
      i++;
      continue;
    }

    // 普通段落：连续非空行合并为一个块（用软换行保留结构）
    paragraph.add(line.trimRight());
    i++;
  }
  flushParagraph();
  return blocks;
}

// ---------------------------------------------------------------------------
// 块级：编码
// ---------------------------------------------------------------------------

String _escapeAttr(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String encodeMedia(MediaPayload m) {
  if (m.kind == AssetKind.image) {
    final src = m.src.replaceAll('(', r'\(').replaceAll(')', r'\)');
    final alt = m.alt.replaceAll('[', r'\[').replaceAll(']', r'\]');
    final title = m.width != null ? ' "width=${m.width}"' : '';
    return '![$alt]($src$title)';
  }
  final attrs = <String>[
    'data-src="${_escapeAttr(m.src)}"',
    'data-name="${_escapeAttr(m.name)}"',
    'data-kind="${m.kind.name}"',
    'data-size="${m.size}"',
    if (m.width != null) 'data-width="${m.width}"',
  ];
  return '<attachment ${attrs.join(' ')}></attachment>';
}

String _oneLine(DocBlock b) => encodeInline(b.text, b.marks).replaceAll('\n', ' ');

String _encodeBlock(DocBlock b, int ordinal) {
  switch (b.kind) {
    case BlockKind.divider:
      return '---';
    case BlockKind.media:
      final media = b.media;
      return media == null ? '' : encodeMedia(media);
    case BlockKind.code:
      final lang = b.language ?? '';
      return '```$lang\n${b.text}\n```';
    case BlockKind.quote:
      final inline = encodeInline(b.text, b.marks);
      return inline
          .split('\n')
          .map((l) => l.isEmpty ? '>' : '> $l')
          .join('\n');
    case BlockKind.heading1:
      return '# ${_oneLine(b)}';
    case BlockKind.heading2:
      return '## ${_oneLine(b)}';
    case BlockKind.heading3:
      return '### ${_oneLine(b)}';
    case BlockKind.bullet:
      return '- ${_oneLine(b)}';
    case BlockKind.numbered:
      return '$ordinal. ${_oneLine(b)}';
    case BlockKind.todo:
      return '- [${b.checked ? 'x' : ' '}] ${_oneLine(b)}';
    case BlockKind.paragraph:
      // 段落内换行用 Markdown 硬换行（两个空格），桌面端解析为 hardBreak。
      return encodeInline(b.text, b.marks).split('\n').join('  \n');
  }
}

/// 块列表 → Markdown 正文（落盘形态）。
String encodeMarkdown(List<DocBlock> blocks) {
  final kept = blocks
      .where((b) =>
          b.kind == BlockKind.divider ||
          (b.kind == BlockKind.media && b.media != null) ||
          b.text.trim().isNotEmpty)
      .toList();
  if (kept.isEmpty) return '';

  final chunks = <String>[];
  var ordinal = 0;
  for (var i = 0; i < kept.length; i++) {
    final b = kept[i];
    if (b.kind == BlockKind.numbered) {
      final prev = i > 0 ? kept[i - 1] : null;
      ordinal = (prev != null && prev.kind == BlockKind.numbered) ? ordinal + 1 : 1;
    }
    chunks.add(_encodeBlock(b, ordinal));
  }

  final sb = StringBuffer();
  for (var i = 0; i < chunks.length; i++) {
    if (i > 0) {
      final prev = kept[i - 1].kind;
      final cur = kept[i].kind;
      // 紧凑列表（与桌面端 tightLists: true 一致）
      final tight = prev.isList && cur.isList && prev == cur;
      sb.write(tight ? '\n' : '\n\n');
    }
    sb.write(chunks[i]);
  }
  return sb.toString().trim();
}

// ---------------------------------------------------------------------------
// 与条目模型的桥接
// ---------------------------------------------------------------------------

/// 收集正文中引用到的资产（按出现顺序，去重），用于同步 frontmatter 的 `assets`。
List<AssetRef> collectAssets(List<DocBlock> blocks) {
  final seen = <String>{};
  final out = <AssetRef>[];
  for (final b in blocks) {
    final m = b.media;
    if (b.kind != BlockKind.media || m == null) continue;
    if (m.src.isEmpty || !seen.add(m.src)) continue;
    out.add(m.toAssetRef());
  }
  return out;
}

/// 解码条目正文，并把「frontmatter 里存在但正文未引用」的历史资产补到末尾。
///
/// 早期版本（以及仅在 frontmatter 挂图的条目）不会把图片写进正文，
/// 这里做一次无损迁移，保证用户看得见、且再次保存后正文与 assets 自洽。
List<DocBlock> decodeEntryBody(String body, List<AssetRef> assets) {
  final blocks = decodeMarkdown(body);
  final referenced = blocks
      .where((b) => b.kind == BlockKind.media && b.media != null)
      .map((b) => b.media!.src)
      .toSet();
  for (final a in assets) {
    if (a.path.isEmpty || referenced.contains(a.path)) continue;
    blocks.add(DocBlock.media(MediaPayload.fromAssetRef(a)));
    referenced.add(a.path);
  }
  return blocks;
}
