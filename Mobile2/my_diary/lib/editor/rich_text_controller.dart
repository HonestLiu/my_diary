import 'package:flutter/material.dart';
import 'package:my_diary_mobile/editor/doc_model.dart';
import 'package:my_diary_mobile/editor/inline_style.dart';

/// 带「行内标记」的文本控制器 —— 编辑器不暴露任何 Markdown 源码的关键。
///
/// 实现要点：
/// 1. 控制器里存的是**纯文本**，样式以标记区间（`InlineMark`）旁挂，
///    渲染时由 `buildTextSpan` 转成带样式的 span，所以用户看不到 `**` 之类符号；
/// 2. 每次文本变更用最小差异（`computeTextDiff`）重映射标记区间，
///    保证插入/删除后样式不错位，且在样式内部输入会自动延续样式；
/// 3. 文本首位插入一个零宽哨兵字符（U+200B）：
///    软键盘在行首按退格时会删掉哨兵 —— 这是移动端唯一稳定可检测「行首退格」的方式，
///    用于触发块合并（把当前块并入上一块）。哨兵零宽不可见，也不会进入落盘内容。
class RichTextController extends TextEditingController {
  static const String sentinel = '\u200B';

  final bool useSentinel;

  List<InlineMark> _marks;
  Set<MarkKind> _pending = <MarkKind>{};
  Set<MarkKind> _disabled = <MarkKind>{};
  bool _muted = false;

  /// 行首退格（内容未发生变化）→ 请求与上一块合并。
  VoidCallback? onMergeBackward;

  /// 纯文本或标记发生变化。
  void Function(String text, List<InlineMark> marks)? onDocChanged;

  InlinePalette palette = const InlinePalette(
    codeBackground: Color(0x14101828),
    codeForeground: Color(0xFFB42318),
  );

  RichTextController({
    String text = '',
    List<InlineMark> marks = const <InlineMark>[],
    this.useSentinel = true,
  })  : _marks = normalizeMarks(marks, text.length),
        super(text: useSentinel ? sentinel + text : text);

  /// 落盘用的纯文本（不含哨兵）。
  String get plainText {
    final raw = super.text;
    if (useSentinel && raw.startsWith(sentinel)) return raw.substring(1);
    return raw;
  }

  int get offsetBase => useSentinel ? 1 : 0;

  List<InlineMark> get marks => _marks;

  /// 相对纯文本的选区。
  TextSelection get plainSelection {
    final sel = selection;
    final len = plainText.length;
    if (sel.baseOffset < 0 || sel.extentOffset < 0) {
      return TextSelection.collapsed(offset: len);
    }
    final base = offsetBase;
    final start = (sel.start - base).clamp(0, len);
    final end = (sel.end - base).clamp(0, len);
    return TextSelection(baseOffset: start, extentOffset: end);
  }

  /// 当前生效的标记（选区全覆盖 / 光标处），已叠加待生效与已关闭的开关。
  Set<MarkKind> get activeMarks {
    final sel = plainSelection;
    final base = sel.isCollapsed
        ? marksAt(_marks, sel.start)
        : marksCovering(_marks, sel.start, sel.end);
    return {...base, ..._pending}..removeAll(_disabled);
  }

  /// 整块替换内容（外部驱动，例如块拆分/合并后重置）。
  void setDoc(String text, List<InlineMark> marks, {int? caret}) {
    _marks = normalizeMarks(marks, text.length);
    _pending = <MarkKind>{};
    _disabled = <MarkKind>{};
    final full = useSentinel ? sentinel + text : text;
    final offset = ((caret ?? text.length).clamp(0, text.length)) + offsetBase;
    _muted = true;
    value = TextEditingValue(
      text: full,
      selection: TextSelection.collapsed(offset: offset),
    );
    _muted = false;
  }

  /// 把光标移到纯文本的指定位置。
  void setPlainCaret(int offset) {
    final target = (offset.clamp(0, plainText.length)) + offsetBase;
    selection = TextSelection.collapsed(offset: target);
  }

  /// 切换行内标记：有选区则作用于选区，否则只影响「接下来输入的文本」。
  void toggleMark(MarkKind kind) {
    final sel = plainSelection;
    if (sel.isCollapsed) {
      if (activeMarks.contains(kind)) {
        _disabled.add(kind);
        _pending.remove(kind);
      } else {
        _pending.add(kind);
        _disabled.remove(kind);
      }
      notifyListeners();
      return;
    }
    final len = plainText.length;
    final covered = marksCover(_marks, kind, sel.start, sel.end);
    _marks = covered
        ? removeMark(_marks, kind, sel.start, sel.end, textLength: len)
        : applyMark(_marks, kind, sel.start, sel.end, textLength: len);
    onDocChanged?.call(plainText, _marks);
    notifyListeners();
  }

  /// 清空当前块的全部行内样式。
  void clearMarks() {
    if (_marks.isEmpty && _pending.isEmpty) return;
    _marks = const <InlineMark>[];
    _pending = <MarkKind>{};
    _disabled = <MarkKind>{};
    onDocChanged?.call(plainText, _marks);
    notifyListeners();
  }

  @override
  set value(TextEditingValue newValue) {
    if (_muted) {
      super.value = newValue;
      return;
    }

    final oldPlain = plainText;
    var next = newValue;

    // 哨兵被删除 —— 判断是「行首退格」还是把哨兵连同内容一起删了
    if (useSentinel && !next.text.startsWith(sentinel)) {
      final onlySentinelRemoved = next.text == oldPlain;
      final restored = sentinel + next.text;
      next = TextEditingValue(
        text: restored,
        selection: TextSelection(
          baseOffset: next.selection.baseOffset < 0
              ? -1
              : (next.selection.baseOffset + 1).clamp(1, restored.length),
          extentOffset: next.selection.extentOffset < 0
              ? -1
              : (next.selection.extentOffset + 1).clamp(1, restored.length),
        ),
      );
      if (onlySentinelRemoved) {
        super.value = next;
        onMergeBackward?.call();
        return;
      }
    }

    final newPlain = useSentinel && next.text.startsWith(sentinel)
        ? next.text.substring(1)
        : next.text;

    if (newPlain != oldPlain) {
      final diff = computeTextDiff(oldPlain, newPlain);
      // 紧贴样式右端继续输入时延续样式（除非用户刚显式关掉）
      final extend = <MarkKind>{};
      for (final m in _marks) {
        if (m.end == diff.at && !_disabled.contains(m.kind)) extend.add(m.kind);
      }
      var updated = shiftMarks(
        _marks,
        at: diff.at,
        removed: diff.removed,
        inserted: diff.inserted,
        textLength: newPlain.length,
        extend: extend,
      );
      if (diff.inserted > 0 && _pending.isNotEmpty) {
        for (final kind in _pending) {
          updated = applyMark(
            updated,
            kind,
            diff.at,
            diff.at + diff.inserted,
            textLength: newPlain.length,
          );
        }
      }
      if (diff.inserted > 0 && _disabled.isNotEmpty) {
        for (final kind in _disabled) {
          updated = removeMark(
            updated,
            kind,
            diff.at,
            diff.at + diff.inserted,
            textLength: newPlain.length,
          );
        }
      }
      _marks = updated;
      _pending = <MarkKind>{};
      _disabled = <MarkKind>{};
      super.value = _clamp(next);
      onDocChanged?.call(newPlain, _marks);
      return;
    }

    super.value = _clamp(next);
  }

  TextEditingValue _clamp(TextEditingValue v) {
    if (!useSentinel) return v;
    final sel = v.selection;
    if (sel.baseOffset < 0 || sel.extentOffset < 0) return v;
    if (sel.baseOffset >= 1 && sel.extentOffset >= 1) return v;
    return v.copyWith(
      selection: TextSelection(
        baseOffset: sel.baseOffset < 1 ? 1 : sel.baseOffset,
        extentOffset: sel.extentOffset < 1 ? 1 : sel.extentOffset,
      ),
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final children = <InlineSpan>[];
    if (useSentinel && super.text.startsWith(sentinel)) {
      children.add(TextSpan(text: sentinel, style: base));
    }
    children.addAll(buildInlineSpans(
      text: plainText,
      marks: _marks,
      base: base,
      palette: palette,
    ));
    return TextSpan(style: base, children: children);
  }
}
