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
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final e = journeys[index];
          return ListTile(
            title: Text(e.displayTitle),
            subtitle: Text(
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
  String _formatSubtitle(JournalEntry e) {
    final parts = <String>[];
    if (e.location != null && e.location!.isNotEmpty) parts.add(e.location!);
    if (e.mood != Mood.neutral) parts.add('${e.mood.emoji} ${e.mood.label}');
    if (e.weather != Weather.unknown) {
      parts.add('${e.weather.emoji} ${e.weather.label}');
    }
    return parts.join(' · ');
  }
}
