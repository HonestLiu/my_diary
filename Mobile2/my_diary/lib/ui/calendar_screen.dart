import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:my_diary_mobile/ui/detail_screen.dart';
import 'package:provider/provider.dart';

/// 日历视图：按月浏览，有日记的日期打点；点击某天以列表展示当天日记。
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _focused;
  int _dir = 1; // 切换方向：1=向后（下月），-1=向前（上月）

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focused = DateTime(now.year, now.month, 1);
  }

  Map<String, List<JournalEntry>> _groupByDate(
      List<JournalEntry> entries) {
    final map = <String, List<JournalEntry>>{};
    for (final e in entries) {
      map.putIfAbsent(e.date, () => []).add(e);
    }
    return map;
  }

  void _shift(int months) {
    setState(() {
      _dir = months > 0 ? 1 : -1;
      _focused = DateTime(_focused.year, _focused.month + months, 1);
    });
  }

  void _jumpToToday() {
    final now = DateTime.now();
    final cur = now.year * 12 + now.month;
    final foc = _focused.year * 12 + _focused.month;
    setState(() {
      _dir = cur >= foc ? 1 : -1;
      _focused = DateTime(now.year, now.month, 1);
    });
  }

  void _showDay(BuildContext context, String dateKey,
      List<JournalEntry> items) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(context.tokens.radiusSheet)),
      ),
      builder: (c) => DraggableScrollableSheet(
        initialChildSize: items.length > 4 ? 0.7 : 0.5,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, controller) => SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.tokens.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(dateKey, style: context.titleMedium),
                    const Spacer(),
                    Text('${items.length} 篇', style: context.caption),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('🌱',
                                  style: const TextStyle(fontSize: 36)),
                              const SizedBox(height: 12),
                              Text('这一天还没有日记', style: context.caption),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: controller,
                        padding: const EdgeInsets.all(8),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final e = items[i];
                          return ListTile(
                            leading: Text(e.mood.emoji,
                                style: const TextStyle(fontSize: 20)),
                            title: Text(e.displayTitle),
                            subtitle: Text(
                              e.body.replaceAll(RegExp(r'\s+'), ' ').trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.caption,
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.pop(c);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => DetailScreen(entry: e)),
                              );
                            },
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final store = context.watch<AppStore>();
    final groups = _groupByDate(store.entries);

    final year = _focused.year;
    final month = _focused.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday; // 1=Mon..7=Sun
    final mondayStart = store.settings.weekStartsOn == 1;
    final startOffset = mondayStart ? firstWeekday - 1 : firstWeekday % 7;

    final weekLabels = mondayStart
        ? const ['一', '二', '三', '四', '五', '六', '日']
        : const ['日', '一', '二', '三', '四', '五', '六'];

    final today = DateTime.now();
    final isThisMonth = today.year == year && today.month == month;

    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat('yyyy 年 M 月', 'zh_CN').format(_focused)),
        actions: [
          TextButton(
            onPressed: _jumpToToday,
            child: const Text('今天'),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _shift(-1),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _shift(1),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: weekLabels
                  .map((w) => Expanded(
                        child: Center(
                          child: Text(w,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: t.textTertiary,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: Offset(_dir > 0 ? 0.06 : -0.06, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                    parent: animation, curve: Curves.easeOutCubic));
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: GridView.count(
                key: ValueKey('$year-$month'),
                crossAxisCount: 7,
                padding: const EdgeInsets.all(10),
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1,
                children: [
                  for (var i = 0; i < startOffset; i++)
                    const SizedBox.shrink(),
                  for (var d = 1; d <= daysInMonth; d++) ...[
                    _DayCell(
                      day: d,
                      count: groups[
                              '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}']
                          ?.length ??
                          0,
                      isToday:
                          isThisMonth && d == today.day,
                      onTap: () => _showDay(
                        context,
                        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}',
                        groups[
                                '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}'] ??
                            [],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final int count;
  final bool isToday;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.count,
    required this.isToday,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hasEntries = count > 0;
    final child = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: isToday
              ? BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                )
              : null,
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: 14,
              fontWeight: hasEntries || isToday
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: isToday
                  ? Theme.of(context).colorScheme.onPrimary
                  : t.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 3),
        if (hasEntries)
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: isToday
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
          )
        else
          const SizedBox(height: 5),
      ],
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Opacity(opacity: hasEntries || isToday ? 1 : 0.45, child: child),
    );
  }
}
