import 'package:my_diary_mobile/models/journal_entry.dart';

/// 编辑器文档模型 —— 「块 + 行内标记范围」。
///
/// 设计要点：
/// 1. 用户永远只看到 **渲染后的富文本**，不接触 Markdown 源码；
/// 2. 但落盘仍是标准 Markdown（见 `markdown_doc.dart`），与桌面端 TipTap 逐一对应：
///    - 块类型 ↔ TipTap 节点（paragraph / heading / blockquote / codeBlock / listItem / taskItem / image / attachment）
///    - 行内标记 ↔ TipTap marks（bold / italic / underline / strike / code）
/// 3. 标记以「字符区间」存储（相对块内纯文本），避免在文本里混入任何符号。

/// 块类型，与桌面端节点一一对应。
enum BlockKind {
  paragraph,
  heading1,
  heading2,
  heading3,
  quote,
  code,
  bullet,
  numbered,
  todo,
  divider,
  media,
}

extension BlockKindX on BlockKind {
  /// 是否为可编辑文本块（非分割线 / 媒体卡片）。
  bool get isText => this != BlockKind.divider && this != BlockKind.media;

  bool get isList =>
      this == BlockKind.bullet ||
      this == BlockKind.numbered ||
      this == BlockKind.todo;

  bool get isHeading =>
      this == BlockKind.heading1 ||
      this == BlockKind.heading2 ||
      this == BlockKind.heading3;

  String get label {
    switch (this) {
      case BlockKind.paragraph:
        return '正文';
      case BlockKind.heading1:
        return '标题 1';
      case BlockKind.heading2:
        return '标题 2';
      case BlockKind.heading3:
        return '标题 3';
      case BlockKind.quote:
        return '引用';
      case BlockKind.code:
        return '代码';
      case BlockKind.bullet:
        return '无序列表';
      case BlockKind.numbered:
        return '有序列表';
      case BlockKind.todo:
        return '待办';
      case BlockKind.divider:
        return '分割线';
      case BlockKind.media:
        return '媒体';
    }
  }
}

/// 行内标记类型。
enum MarkKind { bold, italic, underline, strike, code }

extension MarkKindX on MarkKind {
  String get label {
    switch (this) {
      case MarkKind.bold:
        return '加粗';
      case MarkKind.italic:
        return '斜体';
      case MarkKind.underline:
        return '下划线';
      case MarkKind.strike:
        return '删除线';
      case MarkKind.code:
        return '行内代码';
    }
  }
}

/// 半开区间 `[start, end)`，索引相对块内纯文本。
class InlineMark {
  final MarkKind kind;
  final int start;
  final int end;

  const InlineMark(this.kind, this.start, this.end);

  int get length => end - start;

  bool covers(int s, int e) => start <= s && end >= e;

  InlineMark shifted(int delta) =>
      InlineMark(kind, start + delta, end + delta);

  @override
  bool operator ==(Object other) =>
      other is InlineMark &&
      other.kind == kind &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(kind, start, end);

  @override
  String toString() => '${kind.name}[$start,$end)';
}

/// 媒体节点负载（图片 / 音频 / 视频 / 附件）。
class MediaPayload {
  final AssetKind kind;

  /// vault 根相对路径，例如 `assets/images/xxx.jpg`。
  final String src;
  final String name;
  final int size;

  /// 用户手动调整过的展示宽度（px），与桌面端 `width=N` / `data-width` 对应。
  final int? width;

  /// 图片的 alt 文本。
  final String alt;

  const MediaPayload({
    required this.kind,
    required this.src,
    this.name = '',
    this.size = 0,
    this.width,
    this.alt = '',
  });

  factory MediaPayload.fromAssetRef(AssetRef ref) => MediaPayload(
        kind: ref.kind,
        src: ref.path,
        name: ref.name ?? ref.path.split('/').last,
        size: ref.size ?? 0,
      );

  AssetRef toAssetRef() => AssetRef(
        kind: kind,
        path: src,
        name: name.isEmpty ? null : name,
        size: size > 0 ? size : null,
      );

  MediaPayload copyWith({
    AssetKind? kind,
    String? src,
    String? name,
    int? size,
    int? width,
    bool clearWidth = false,
    String? alt,
  }) =>
      MediaPayload(
        kind: kind ?? this.kind,
        src: src ?? this.src,
        name: name ?? this.name,
        size: size ?? this.size,
        width: clearWidth ? null : (width ?? this.width),
        alt: alt ?? this.alt,
      );
}

int _blockSeq = 0;

/// 一个可编辑块。为配合 `setState` 的就地更新，字段是可变的。
class DocBlock {
  final String id;
  BlockKind kind;

  /// 纯文本（不含任何 Markdown 符号）。代码块内可含换行。
  String text;
  List<InlineMark> marks;

  /// 待办勾选状态。
  bool checked;

  /// 代码块语言（可选）。
  String? language;

  /// 媒体块负载。
  MediaPayload? media;

  DocBlock({
    String? id,
    required this.kind,
    this.text = '',
    List<InlineMark>? marks,
    this.checked = false,
    this.language,
    this.media,
  })  : id = id ?? 'b${_blockSeq++}',
        marks = marks == null ? <InlineMark>[] : List.of(marks);

  factory DocBlock.paragraph([String text = '', List<InlineMark>? marks]) =>
      DocBlock(kind: BlockKind.paragraph, text: text, marks: marks);

  factory DocBlock.divider() => DocBlock(kind: BlockKind.divider);

  factory DocBlock.media(MediaPayload payload) =>
      DocBlock(kind: BlockKind.media, media: payload);

  bool get isEmptyText => text.trim().isEmpty;

  DocBlock copy() => DocBlock(
        kind: kind,
        text: text,
        marks: marks,
        checked: checked,
        language: language,
        media: media,
      );

  @override
  String toString() =>
      'DocBlock(${kind.name}, "${text.length > 24 ? '${text.substring(0, 24)}…' : text}", marks=$marks)';
}

// ---------------------------------------------------------------------------
// 标记区间运算
// ---------------------------------------------------------------------------

/// 规范化：裁剪越界、丢弃空区间、合并同类相邻/重叠区间、稳定排序。
List<InlineMark> normalizeMarks(List<InlineMark> marks, int textLength) {
  if (marks.isEmpty) return const <InlineMark>[];
  final byKind = <MarkKind, List<InlineMark>>{};
  for (final m in marks) {
    final s = m.start < 0 ? 0 : (m.start > textLength ? textLength : m.start);
    final e = m.end < 0 ? 0 : (m.end > textLength ? textLength : m.end);
    if (e <= s) continue;
    byKind.putIfAbsent(m.kind, () => <InlineMark>[]).add(InlineMark(m.kind, s, e));
  }
  final out = <InlineMark>[];
  for (final kind in MarkKind.values) {
    final list = byKind[kind];
    if (list == null || list.isEmpty) continue;
    list.sort((a, b) => a.start.compareTo(b.start));
    var cur = list.first;
    for (final m in list.skip(1)) {
      if (m.start <= cur.end) {
        cur = InlineMark(kind, cur.start, m.end > cur.end ? m.end : cur.end);
      } else {
        out.add(cur);
        cur = m;
      }
    }
    out.add(cur);
  }
  out.sort((a, b) => a.start != b.start
      ? a.start.compareTo(b.start)
      : a.kind.index.compareTo(b.kind.index));
  return out;
}

List<InlineMark> applyMark(
  List<InlineMark> marks,
  MarkKind kind,
  int start,
  int end, {
  required int textLength,
}) {
  if (end <= start) return normalizeMarks(marks, textLength);
  return normalizeMarks([...marks, InlineMark(kind, start, end)], textLength);
}

List<InlineMark> removeMark(
  List<InlineMark> marks,
  MarkKind kind,
  int start,
  int end, {
  required int textLength,
}) {
  if (end <= start) return normalizeMarks(marks, textLength);
  final out = <InlineMark>[];
  for (final m in marks) {
    if (m.kind != kind || m.end <= start || m.start >= end) {
      out.add(m);
      continue;
    }
    if (m.start < start) out.add(InlineMark(kind, m.start, start));
    if (m.end > end) out.add(InlineMark(kind, end, m.end));
  }
  return normalizeMarks(out, textLength);
}

/// `[start, end)` 是否被某类标记完整覆盖。
bool marksCover(List<InlineMark> marks, MarkKind kind, int start, int end) {
  if (end <= start) return false;
  final list = marks.where((m) => m.kind == kind).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  var pos = start;
  for (final m in list) {
    if (m.end <= pos) continue;
    if (m.start > pos) return false;
    pos = m.end;
    if (pos >= end) return true;
  }
  return pos >= end;
}

/// 光标处生效的标记集合（落在区间内，或紧贴区间右端 —— 与主流编辑器一致）。
Set<MarkKind> marksAt(List<InlineMark> marks, int offset) {
  final out = <MarkKind>{};
  for (final m in marks) {
    if (offset > m.start && offset <= m.end) out.add(m.kind);
  }
  return out;
}

/// 选区内「全部覆盖」的标记集合。
Set<MarkKind> marksCovering(List<InlineMark> marks, int start, int end) {
  if (end <= start) return marksAt(marks, start);
  return MarkKind.values
      .where((k) => marksCover(marks, k, start, end))
      .toSet();
}

/// 文本编辑的最小差异（公共前后缀之外的部分）。
class TextDiff {
  final int at;
  final int removed;
  final int inserted;
  const TextDiff({required this.at, required this.removed, required this.inserted});

  bool get isEmpty => removed == 0 && inserted == 0;

  @override
  String toString() => 'TextDiff(at=$at, -$removed, +$inserted)';
}

TextDiff computeTextDiff(String oldText, String newText) {
  final minLen =
      oldText.length < newText.length ? oldText.length : newText.length;
  var start = 0;
  while (start < minLen &&
      oldText.codeUnitAt(start) == newText.codeUnitAt(start)) {
    start++;
  }
  var oldEnd = oldText.length;
  var newEnd = newText.length;
  while (oldEnd > start &&
      newEnd > start &&
      oldText.codeUnitAt(oldEnd - 1) == newText.codeUnitAt(newEnd - 1)) {
    oldEnd--;
    newEnd--;
  }
  return TextDiff(at: start, removed: oldEnd - start, inserted: newEnd - start);
}

/// 文本变更后重映射标记区间。
///
/// - 插入点严格落在区间内部 → 区间自动扩张（继续保持样式）；
/// - 插入点正好在区间右端 → 默认不扩张；若 `extend` 含该类型则扩张（用于「接着输入保持加粗」）。
List<InlineMark> shiftMarks(
  List<InlineMark> marks, {
  required int at,
  required int removed,
  required int inserted,
  required int textLength,
  Set<MarkKind> extend = const <MarkKind>{},
}) {
  if (marks.isEmpty) return const <InlineMark>[];
  final delta = inserted - removed;
  final removeEnd = at + removed;

  int mapStart(int i) {
    if (i < at) return i;
    if (i >= removeEnd) return i + delta;
    return at;
  }

  int mapEnd(int i) {
    if (i <= at) return i;
    if (i >= removeEnd) return i + delta;
    return at;
  }

  final out = <InlineMark>[];
  for (final m in marks) {
    final s = mapStart(m.start);
    var e = mapEnd(m.end);
    if (m.end == at && inserted > 0 && extend.contains(m.kind)) {
      e = at + inserted;
    }
    if (e > s) out.add(InlineMark(m.kind, s, e));
  }
  return normalizeMarks(out, textLength);
}

List<InlineMark> shiftMarksBy(List<InlineMark> marks, int delta) =>
    marks.map((m) => m.shifted(delta)).toList();

/// 在 `offset` 处切分标记：`head` 保留 `[0, offset)`，`tail` 重基准到 0。
({List<InlineMark> head, List<InlineMark> tail}) splitMarks(
  List<InlineMark> marks,
  int offset, {
  int dropLength = 0,
}) {
  final tailBase = offset + dropLength;
  final head = <InlineMark>[];
  final tail = <InlineMark>[];
  for (final m in marks) {
    if (m.start < offset) {
      head.add(InlineMark(m.kind, m.start, m.end < offset ? m.end : offset));
    }
    if (m.end > tailBase) {
      final s = (m.start > tailBase ? m.start : tailBase) - tailBase;
      tail.add(InlineMark(m.kind, s, m.end - tailBase));
    }
  }
  return (head: head, tail: tail);
}
