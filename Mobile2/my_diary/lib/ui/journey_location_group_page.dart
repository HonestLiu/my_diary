import 'package:flutter/material.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/ui/detail_screen.dart';

/// 地点分组页：聚簇点内的全部日记列表，点击进入详情。
/// 移植自原 MyDiary 的 `lib/pages/map/journey_location_group_page.dart`。
class JourneyLocationGroupPage extends StatefulWidget {
  final List<JournalEntry> journeys;
  const JourneyLocationGroupPage({super.key, required this.journeys});

  @override
  State<JourneyLocationGroupPage> createState() =>
      _JourneyLocationGroupPageState();
}

class _JourneyLocationGroupPageState extends State<JourneyLocationGroupPage> {
  @override
  Widget build(BuildContext context) {
    final journeys = widget.journeys;
    return Scaffold(
      appBar: AppBar(title: Text('此位置日记 (${journeys.length})')),
      body: ListView.separated(
        itemCount: journeys.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final e = journeys[index];
          return ListTile(
            title: Text(e.displayTitle),
            subtitle: Text.rich(
              _formatSubtitle(e),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DetailScreen(entry: e)),
            ),
          );
        },
      ),
    );
  }

  /// 副标题：地点 · 心情 · 天气（空项跳过）。
  /// 心情 / 天气用 iconfont 字形渲染（moodfont / iconfont family）。
  InlineSpan _formatSubtitle(JournalEntry e) {
    final parts = <InlineSpan>[];
    if (e.location != null && e.location!.isNotEmpty) {
      parts.add(TextSpan(text: e.location));
    }
    if (e.mood != Mood.neutral) {
      parts.add(TextSpan(
        text: '${e.mood.iconChar} ${e.mood.label}',
        style: const TextStyle(fontFamily: 'moodfont'),
      ));
    }
    if (e.weather != Weather.unknown) {
      parts.add(TextSpan(
        text: '${e.weather.iconChar} ${e.weather.label}',
        style: const TextStyle(fontFamily: 'iconfont'),
      ));
    }
    if (parts.isEmpty) return const TextSpan(text: '');
    return TextSpan(children: [
      for (var i = 0; i < parts.length; i++) ...[
        if (i > 0) const TextSpan(text: ' · '),
        parts[i],
      ],
    ]);
  }
}
