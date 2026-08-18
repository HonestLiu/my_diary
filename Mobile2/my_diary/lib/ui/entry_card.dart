import 'package:flutter/material.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:provider/provider.dart';
import 'package:my_diary_mobile/editor/doc_view.dart';
import 'package:my_diary_mobile/editor/markdown_doc.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:my_diary_mobile/ui/detail_screen.dart';

/// 首页 / 日历共用的日记卡片：柔和投影无边框圆角卡。
/// 布局：标题行（标题 + 心情/天气 emoji + 喜欢角标）→ 地点行 → 两行预览 →
/// 底部标签胶囊；右侧可选大封面图。信息分层分散，不挤在底部一行。
class EntryCard extends StatelessWidget {
  final JournalEntry entry;
  const EntryCard({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final imgs = entry.assets.where((a) => a.kind == AssetKind.image);
    final cover = imgs.isEmpty ? null : imgs.first;
    final loc = entry.location?.trim() ?? '';
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
          borderRadius: BorderRadius.circular(t.radiusCard)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DetailScreen(entry: entry)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题行：标题 + 心情/天气 emoji + 喜欢红心角标。
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.displayTitle,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(entry.mood.iconData,
                            size: 16, color: t.textSecondary),
                        if (entry.weather != Weather.unknown) ...[
                          const SizedBox(width: 3),
                          Icon(entry.weather.iconData,
                              size: 16,
                              color: t.textSecondary),
                        ],
                        if (entry.favorite) ...[
                          const SizedBox(width: 5),
                          const Icon(Icons.favorite,
                              size: 15, color: Colors.redAccent),
                        ],
                      ],
                    ),
                    // 正文预览两行。
                    if (hasPreview) ...[
                      const SizedBox(height: 7),
                      Text.rich(
                        TextSpan(children: previewSpans),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    // 底部胶囊行：地点 + 标签。
                    if (loc.isNotEmpty || entry.tags.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (loc.isNotEmpty)
                            _MetaChip(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.place_outlined,
                                      size: 12, color: t.textTertiary),
                                  const SizedBox(width: 3),
                                  Text(loc,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: t.textTertiary)),
                                ],
                              ),
                            ),
                          for (final tag in entry.tags.take(2))
                            _MetaChip(
                              child: Text('#$tag',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: t.textTertiary)),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (cover != null) ...[
                const SizedBox(width: 14),
                _Cover(asset: cover),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部 meta 胶囊：浅底小圆角，内容由调用方提供。
class _MetaChip extends StatelessWidget {
  final Widget child;
  const _MetaChip({required this.child});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: t.fill,
        borderRadius: BorderRadius.circular(t.radiusChip),
      ),
      child: child,
    );
  }
}

/// 右侧封面：84×84 圆角图（图片损坏时显示占位）。
class _Cover extends StatelessWidget {
  final AssetRef asset;
  const _Cover({required this.asset});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final file = context.read<AppStore>().resolveAsset(asset.path);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(
        file,
        width: 84,
        height: 84,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 84,
          height: 84,
          color: t.fill,
          alignment: Alignment.center,
          child: Icon(Icons.broken_image_outlined,
              size: 24, color: t.textTertiary),
        ),
      ),
    );
  }
}

/// 单行 meta：`😄 开心 · ☀️ 晴 · 上海 · #日记`，超长省略。
/// 供媒体预览条等场景复用（日记卡片内部已改用 _MetaChips 胶囊）。
/// 心情 / 天气用 iconfont 字形渲染（moodfont / iconfont family）。
class MetaLine extends StatelessWidget {
  final JournalEntry entry;
  const MetaLine({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final loc = entry.location?.trim() ?? '';
    final parts = <InlineSpan>[
      TextSpan(
        text: '${entry.mood.iconChar} ${entry.mood.label}',
        style: const TextStyle(fontFamily: 'moodfont'),
      ),
      TextSpan(
        text: '${entry.weather.iconChar} ${entry.weather.label}',
        style: const TextStyle(fontFamily: 'iconfont'),
      ),
      if (loc.isNotEmpty) TextSpan(text: loc),
      ...entry.tags.map((tag) => TextSpan(text: '#$tag')),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text.rich(
      TextSpan(children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) const TextSpan(text: ' · '),
          parts[i],
        ],
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12, color: t.textTertiary),
    );
  }
}
