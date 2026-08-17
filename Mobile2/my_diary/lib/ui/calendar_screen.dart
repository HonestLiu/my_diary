import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:my_diary_mobile/ui/entry_card.dart';
import 'package:provider/provider.dart';

/// 日历视图：按月浏览，有日记的日期打点；选中某天后在日历下方
/// 直接以「首页同款卡片」列表展示当天日记（不再弹抽屉）。
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _focused;
  late DateTime _selected;
  int _dir = 1; // 切换方向：1=向后（下月），-1=向前（上月）

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focused = DateTime(now.year, now.month, 1);
    _selected = now;
  }

  Map<String, List<JournalEntry>> _groupByDate(List<JournalEntry> entries) {
    final map = <String, List<JournalEntry>>{};
    for (final e in entries) {
      map.putIfAbsent(e.date, () => []).add(e);
    }
    return map;
  }

  /// 选中日期的 yyyy-MM-dd 键，用于匹配日记分组。
  String get _selectedKey {
    final s = _selected;
    return '${s.year.toString().padLeft(4, '0')}-'
        '${s.month.toString().padLeft(2, '0')}-'
        '${s.day.toString().padLeft(2, '0')}';
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
      _selected = now;
    });
  }

  void _pickDay(int day) {
    setState(() {
      _selected = DateTime(_focused.year, _focused.month, day);
    });
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
    final selectedKey = _selectedKey;
    final items = groups[selectedKey] ?? [];

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
          // 日历网格：自然高度，下方列表占据剩余空间。
          AnimatedSwitcher(
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
              shrinkWrap: true,
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
                    isToday: isThisMonth && d == today.day,
                    isSelected: _selected.year == year &&
                        _selected.month == month &&
                        _selected.day == d,
                    onTap: () => _pickDay(d),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          // 选中日期的日记列表（与首页同款卡片）。
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Text(_dayLabel(selectedKey),
                          style: context.titleMedium),
                      const Spacer(),
                      Text('${items.length} 篇',
                          style: context.caption),
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
                                Text('这一天还没有日记',
                                    style: context.caption),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding:
                              const EdgeInsets.fromLTRB(16, 10, 16, 24),
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, i) =>
                              EntryCard(entry: items[i]),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _dayLabel(String dateKey) {
  final dt = DateFormat('yyyy-MM-dd').parse(dateKey);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(dt.year, dt.month, dt.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '昨天';
  if (diff == 2) return '前天';
  final wd = DateFormat('EEEE', 'zh_CN').format(dt);
  return '${DateFormat('M 月 d 日').format(dt)} · $wd';
}

class _DayCell extends StatelessWidget {
  final int day;
  final int count;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.count,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final cs = Theme.of(context).colorScheme;
    final hasEntries = count > 0;
    final selected = isSelected && !isToday;
    final prominent = hasEntries || isToday || selected;

    final child = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: isToday
              ? BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                )
              : selected
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.primary, width: 2),
                    )
                  : null,
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: 14,
              fontWeight: prominent ? FontWeight.w700 : FontWeight.w500,
              color: isToday
                  ? cs.onPrimary
                  : (selected ? cs.primary : t.textPrimary),
            ),
          ),
        ),
        const SizedBox(height: 3),
        if (hasEntries)
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: isToday ? cs.onPrimary : cs.primary,
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
      child: Opacity(opacity: prominent ? 1 : 0.45, child: child),
    );
  }
}
