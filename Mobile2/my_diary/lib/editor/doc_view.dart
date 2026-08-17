import 'package:flutter/material.dart';
import 'package:my_diary_mobile/editor/doc_model.dart';
import 'package:my_diary_mobile/editor/inline_style.dart';
import 'package:my_diary_mobile/editor/media_card.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';

/// 只读富文本渲染器 —— 与编辑器共用同一份文档模型与排版样式，
/// 所以「编辑时看到的」和「详情页看到的」逐像素一致。
class DocView extends StatelessWidget {
  final List<DocBlock> blocks;
  final String emptyHint;

  const DocView({
    super.key,
    required this.blocks,
    this.emptyHint = '这一天还没有内容',
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (blocks.isEmpty) {
      return Text(emptyHint,
          style: TextStyle(fontSize: 15, color: t.textTertiary));
    }
    final palette = InlinePalette.of(context);
    final children = <Widget>[];
    var ordinal = 0;

    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final prev = i > 0 ? blocks[i - 1] : null;
      if (b.kind == BlockKind.numbered) {
        ordinal = (prev != null && prev.kind == BlockKind.numbered) ? ordinal + 1 : 1;
      }
      children.add(Padding(
        padding: _spacing(b, prev),
        child: _block(context, b, palette, ordinal),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  EdgeInsets _spacing(DocBlock b, DocBlock? prev) {
    if (prev == null) return EdgeInsets.zero;
    final tight = prev.kind.isList && b.kind == prev.kind;
    if (tight) return const EdgeInsets.only(top: 4);
    if (b.kind.isHeading) return const EdgeInsets.only(top: 18);
    if (b.kind == BlockKind.divider) return const EdgeInsets.only(top: 14);
    if (b.kind == BlockKind.media) return const EdgeInsets.only(top: 12);
    return const EdgeInsets.only(top: 10);
  }

  Widget _block(
    BuildContext context,
    DocBlock b,
    InlinePalette palette,
    int ordinal,
  ) {
    final t = context.tokens;

    switch (b.kind) {
      case BlockKind.divider:
        return Divider(color: t.border, height: 1);

      case BlockKind.media:
        final media = b.media;
        if (media == null) return const SizedBox.shrink();
        return MediaBlockCard(media: media);

      case BlockKind.code:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.fill,
            borderRadius: BorderRadius.circular(t.radiusInput),
            border: Border.all(color: t.border),
          ),
          child: Text(b.text, style: blockTextStyle(context, BlockKind.code)),
        );

      case BlockKind.quote:
        return Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                  width: 3),
            ),
          ),
          child: _rich(context, b, palette),
        );

      case BlockKind.bullet:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 7, right: 8, left: 2),
              child: Container(
                width: 5,
                height: 5,
                decoration:
                    BoxDecoration(color: t.textSecondary, shape: BoxShape.circle),
              ),
            ),
            Expanded(child: _rich(context, b, palette)),
          ],
        );

      case BlockKind.numbered:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              child: Text('$ordinal.',
                  style: blockTextStyle(context, BlockKind.paragraph)
                      .copyWith(color: t.textSecondary)),
            ),
            Expanded(child: _rich(context, b, palette)),
          ],
        );

      case BlockKind.todo:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 3, right: 8),
              child: Icon(
                b.checked ? Icons.check_box : Icons.check_box_outline_blank,
                size: 19,
                color: b.checked
                    ? Theme.of(context).colorScheme.primary
                    : t.textTertiary,
              ),
            ),
            Expanded(
              child: _rich(
                context,
                b,
                palette,
                override: b.checked
                    ? TextStyle(
                        color: t.textTertiary,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: t.textTertiary,
                      )
                    : null,
              ),
            ),
          ],
        );

      default:
        return _rich(context, b, palette);
    }
  }

  Widget _rich(
    BuildContext context,
    DocBlock b,
    InlinePalette palette, {
    TextStyle? override,
  }) {
    var base = blockTextStyle(context, b.kind);
    if (override != null) base = base.merge(override);
    return Text.rich(TextSpan(
      style: base,
      children: buildInlineSpans(
        text: b.text,
        marks: b.marks,
        base: base,
        palette: palette,
      ),
    ));
  }
}
