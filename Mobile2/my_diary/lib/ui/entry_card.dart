import 'package:flutter/material.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:provider/provider.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:my_diary_mobile/ui/detail_screen.dart';

/// 首页 / 日历共用的日记卡片：标题 + 两行预览 + 右侧封面缩略 + 底部 meta。
class EntryCard extends StatelessWidget {
  final JournalEntry entry;
  const EntryCard({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final imgs = entry.assets.where((a) => a.kind == AssetKind.image);
    final cover = imgs.isEmpty ? null : imgs.first;
    final preview = entry.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    final loc = entry.location?.trim() ?? '';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DetailScreen(entry: entry)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.displayTitle,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          preview.isEmpty ? '（暂无内容）' : preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.caption,
                        ),
                      ],
                    ),
                  ),
                  if (cover != null) ...[
                    const SizedBox(width: 12),
                    _Thumb(asset: cover),
                  ],
                ],
              ),
              // 底部 meta：心情 / 天气 / 定位 / 标签
              _CardMeta(entry: entry, location: loc),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardMeta extends StatelessWidget {
  final JournalEntry entry;
  final String location;
  const _CardMeta({required this.entry, required this.location});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final chips = <Widget>[
      _metaItem(context, '${entry.mood.emoji} ${entry.mood.label}'),
      _metaItem(context, '${entry.weather.emoji} ${entry.weather.label}'),
      if (location.isNotEmpty)
        _metaItem(context, location, icon: Icons.place_outlined),
      ...entry.tags.map((tag) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: t.fill,
              borderRadius: BorderRadius.circular(t.radiusChip),
            ),
            child: Text('#$tag',
                style: TextStyle(fontSize: 12, color: t.textSecondary)),
          )),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: chips,
      ),
    );
  }

  Widget _metaItem(BuildContext context, String text, {IconData? icon}) {
    final tertiary = context.tokens.textTertiary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: tertiary),
          const SizedBox(width: 3),
        ],
        Text(text, style: TextStyle(fontSize: 12, color: tertiary)),
      ],
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
      child: Image.file(file, width: 56, height: 56, fit: BoxFit.cover),
    );
  }
}
