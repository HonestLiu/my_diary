import 'package:flutter/material.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:provider/provider.dart';
import 'package:my_diary_mobile/editor/doc_view.dart';
import 'package:my_diary_mobile/editor/markdown_doc.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:my_diary_mobile/ui/detail_screen.dart';

/// 首页 / 日历共用的日记卡片：精致卡片风 —— 柔和投影无边框圆角卡。
/// 标题 + 两行渲染预览 + 单行 meta，仅当有条目有图片封面时在右侧显示小缩略图。
class EntryCard extends StatelessWidget {
  final JournalEntry entry;
  const EntryCard({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final imgs = entry.assets.where((a) => a.kind == AssetKind.image);
    final cover = imgs.isEmpty ? null : imgs.first;
    // 渲染后的预览：解码正文为文档块，再压平成带行内样式的 span（保留加粗/斜体等）。
    final previewSpans = docBlocksToPreviewSpans(
      context,
      decodeEntryBody(entry.body, entry.assets),
      baseStyle: context.caption.copyWith(fontSize: 13),
    );
    final hasPreview =
        TextSpan(children: previewSpans).toPlainText().trim().isNotEmpty;

    return Card(
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.circular(context.tokens.radiusCard)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DetailScreen(entry: entry)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.displayTitle,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasPreview) ...[
                      const SizedBox(height: 5),
                      Text.rich(
                        TextSpan(children: previewSpans),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 9),
                    _MetaLine(entry: entry),
                  ],
                ),
              ),
              if (cover != null) ...[
                const SizedBox(width: 14),
                _Thumb(asset: cover),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 单行 meta：`😄 开心 · ☀️ 晴 · 上海 · #日记`，超长省略。
class _MetaLine extends StatelessWidget {
  final JournalEntry entry;
  const _MetaLine({required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final loc = entry.location?.trim() ?? '';
    final parts = <String>[
      '${entry.mood.emoji} ${entry.mood.label}',
      '${entry.weather.emoji} ${entry.weather.label}',
      if (loc.isNotEmpty) loc,
      ...entry.tags.map((tag) => '#$tag'),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12, color: t.textTertiary),
    );
  }
}

class _Thumb extends StatelessWidget {
  final AssetRef asset;
  const _Thumb({required this.asset});

  @override
  Widget build(BuildContext context) {
    final file = context.read<AppStore>().resolveAsset(asset.path);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.file(file, width: 48, height: 48, fit: BoxFit.cover),
    );
  }
}
