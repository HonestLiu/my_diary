import 'package:flutter/material.dart';
import 'package:my_diary_mobile/editor/doc_model.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';

/// 行内标记 → TextStyle。编辑态与只读态共用同一套，保证「所见即所得」。
class InlinePalette {
  final Color codeBackground;
  final Color codeForeground;

  const InlinePalette({
    required this.codeBackground,
    required this.codeForeground,
  });

  static InlinePalette of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return InlinePalette(
      codeBackground: dark ? const Color(0x33FFFFFF) : const Color(0x14101828),
      codeForeground: dark ? const Color(0xFFFDA29B) : const Color(0xFFB42318),
    );
  }
}

TextStyle styleForMarks(
  Set<MarkKind> kinds,
  TextStyle base,
  InlinePalette palette,
) {
  var style = base;
  if (kinds.contains(MarkKind.bold)) {
    style = style.copyWith(fontWeight: FontWeight.w700);
  }
  if (kinds.contains(MarkKind.italic)) {
    style = style.copyWith(fontStyle: FontStyle.italic);
  }
  final decorations = <TextDecoration>[];
  if (kinds.contains(MarkKind.underline)) {
    decorations.add(TextDecoration.underline);
  }
  if (kinds.contains(MarkKind.strike)) {
    decorations.add(TextDecoration.lineThrough);
  }
  if (decorations.isNotEmpty) {
    style = style.copyWith(
      decoration: TextDecoration.combine(decorations),
      decorationColor: style.color,
      decorationThickness: 1.2,
    );
  }
  if (kinds.contains(MarkKind.code)) {
    style = style.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
      backgroundColor: palette.codeBackground,
      color: palette.codeForeground,
      letterSpacing: 0,
    );
  }
  return style;
}

/// 块级排版样式。编辑态（TextField）与只读态（Text.rich）必须共用，
/// 否则同一篇日记在两处的行高/字号会漂移。
TextStyle blockTextStyle(BuildContext context, BlockKind kind) {
  final t = context.tokens;
  switch (kind) {
    case BlockKind.heading1:
      return TextStyle(
          fontSize: 22,
          height: 1.35,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: t.textPrimary);
    case BlockKind.heading2:
      return TextStyle(
          fontSize: 19,
          height: 1.4,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: t.textPrimary);
    case BlockKind.heading3:
      return TextStyle(
          fontSize: 17,
          height: 1.45,
          fontWeight: FontWeight.w600,
          color: t.textPrimary);
    case BlockKind.quote:
      return TextStyle(
          fontSize: 15,
          height: 1.65,
          fontStyle: FontStyle.italic,
          color: t.textSecondary);
    case BlockKind.code:
      return TextStyle(
        fontSize: 13.5,
        height: 1.55,
        fontFamily: 'monospace',
        fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
        color: t.textPrimary,
      );
    default:
      return TextStyle(fontSize: 15.5, height: 1.7, color: t.textPrimary);
  }
}

/// 把「纯文本 + 标记区间」切成带样式的 TextSpan 列表。
///
/// 关键约束：所有 span 的文本拼接必须**逐字等于**入参 `text`，
/// 否则 TextField 的光标定位、选区与命中测试会全部错位。
List<InlineSpan> buildInlineSpans({
  required String text,
  required List<InlineMark> marks,
  required TextStyle base,
  required InlinePalette palette,
}) {
  if (text.isEmpty) return const <InlineSpan>[];
  final norm = normalizeMarks(marks, text.length);
  if (norm.isEmpty) {
    return <InlineSpan>[TextSpan(text: text, style: base)];
  }

  final cuts = <int>{0, text.length};
  for (final m in norm) {
    cuts.add(m.start);
    cuts.add(m.end);
  }
  final points = cuts.toList()..sort();

  final spans = <InlineSpan>[];
  for (var i = 0; i < points.length - 1; i++) {
    final s = points[i];
    final e = points[i + 1];
    if (e <= s) continue;
    final kinds = norm
        .where((m) => m.start <= s && m.end >= e)
        .map((m) => m.kind)
        .toSet();
    spans.add(TextSpan(
      text: text.substring(s, e),
      style: kinds.isEmpty ? base : styleForMarks(kinds, base, palette),
    ));
  }
  return spans;
}
