import 'package:flutter/material.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/repository/journal_repository.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:my_diary_mobile/ui/entry_card.dart';
import 'package:provider/provider.dart';

class SearchScreen extends StatefulWidget {
  /// 进入时预填的搜索词，空则不预填。
  final String initialQuery;

  /// 进入时预选的搜索范围（如标签云传入 {SearchScope.tags}），
  /// 空集合 = 搜全部字段（首页正常搜索入口）。
  final Set<SearchScope> initialFilters;

  /// 进入时预选的心情筛选（如「我的」页点击心情柱状图柱子传入），
  /// 非空时即使没有关键词也会展示该心情的全部日记。
  final Mood? initialMood;
  const SearchScreen({
    super.key,
    this.initialQuery = '',
    this.initialFilters = const {},
    this.initialMood,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final TextEditingController _ctl;
  List<JournalEntry> _results = [];
  late final Set<SearchScope> _filters;
  Mood? _mood;
  bool _moodExpanded = false; // 「心情」胶囊是否展开

  // 每个范围对应的图标，供 FilterChip 展示。
  static const Map<SearchScope, IconData> _icons = {
    SearchScope.title: Icons.title,
    SearchScope.body: Icons.article_outlined,
    SearchScope.tags: Icons.sell_outlined,
    SearchScope.location: Icons.place_outlined,
  };

  @override
  void initState() {
    super.initState();
    _filters = Set<SearchScope>.from(widget.initialFilters);
    _mood = widget.initialMood;
    _ctl = TextEditingController(text: widget.initialQuery);
    _ctl.addListener(_onChanged);
    if (widget.initialQuery.trim().isNotEmpty || widget.initialMood != null) {
      _onChanged();
    }
  }

  @override
  void dispose() {
    _ctl.removeListener(_onChanged);
    _ctl.dispose();
    super.dispose();
  }

  void _onChanged() async {
    final q = _ctl.text;
    if (q.trim().isEmpty && _mood == null) {
      if (mounted) setState(() => _results = []);
      return;
    }
    final store = context.read<AppStore>();
    final res = await store.search(q, filters: _filters, mood: _mood);
    if (mounted) setState(() => _results = res);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctl,
          // 从「我的」心情柱进来时不弹键盘，直接展示该心情的日记。
          autofocus: widget.initialQuery.trim().isNotEmpty ||
              widget.initialMood == null,
          decoration: InputDecoration(
            // 心情前缀用 moodfont 字形渲染，与主搜索提示混排。
            // 注意：hint 传 Widget 时 InputDecorator 不会套用 hintStyle
            //（仅对 hintText 生效），需在 Text.rich 上显式指定与输入框
            // 一致的 16px 与三级文字色，否则会继承 AppBar 的大号标题字号。
            hint: Text.rich(
              TextSpan(children: [
                if (_mood != null) ...[
                  TextSpan(
                    text: '${_mood!.iconChar} ',
                    style: const TextStyle(fontFamily: 'moodfont'),
                  ),
                  TextSpan(text: '${_mood!.label} · '),
                ],
                TextSpan(
                  text: _filters.isEmpty
                      ? '搜索标题、正文、标签、地点…'
                      : '搜索${_filters.map((f) => f.label).join('、')}…',
                ),
              ]),
              style: TextStyle(fontSize: 16, color: t.textTertiary),
            ),
            border: InputBorder.none,
          ),
          style: TextStyle(color: t.textPrimary, fontSize: 16),
        ),
      ),
      body: Column(
        children: [
          // 搜索范围筛选器：点击切换搜索哪些字段。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: SearchScope.values.map((s) {
                final selected = _filters.contains(s);
                return FilterChip(
                  label: Text(s.label),
                  avatar: Icon(_icons[s], size: 15),
                  selected: selected,
                  onSelected: (sel) {
                    setState(() {
                      if (sel) {
                        _filters.add(s);
                      } else {
                        _filters.remove(s);
                      }
                    });
                    _onChanged();
                  },
                );
              }).toList(),
            ),
          ),
          // 心情筛选：收进「心情」胶囊，点击展开选择；与字段范围正交。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MoodFilterPill(
                  mood: _mood,
                  expanded: _moodExpanded,
                  onTap: () =>
                      setState(() => _moodExpanded = !_moodExpanded),
                ),
                if (_moodExpanded) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      FilterChip(
                        label: const Text('全部'),
                        selected: _mood == null,
                        onSelected: (_) {
                          setState(() {
                            _mood = null;
                            _moodExpanded = false;
                          });
                          _onChanged();
                        },
                      ),
                      for (final m in Mood.ordered)
                        FilterChip(
                          label: Text('${m.iconChar} ${m.label}',
                              style: const TextStyle(
                                  fontFamily: 'moodfont')),
                          selected: _mood == m,
                          onSelected: (sel) {
                            setState(() {
                              _mood = sel ? m : null;
                              _moodExpanded = false;
                            });
                            _onChanged();
                          },
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _ctl.text.trim().isEmpty && _mood == null
                ? Center(
                    child: Text('输入关键词开始搜索',
                        style: context.caption),
                  )
                : _results.isEmpty
                    ? Center(
                        child: Text('没有匹配的日记',
                            style: context.caption),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _results.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 12),
                        itemBuilder: (_, i) =>
                            EntryCard(entry: _results[i]),
                      ),
          ),
        ],
      ),
    );
  }
}

/// 「心情」筛选胶囊：未选时显示「心情」，已选时显示当前心情（如「😊 开心」），
/// 点击展开/收起下方的心情选项；展开中高亮显示。
class _MoodFilterPill extends StatelessWidget {
  final Mood? mood;
  final bool expanded;
  final VoidCallback onTap;
  const _MoodFilterPill({
    required this.mood,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final active = mood != null || expanded;
    final fg = active ? scheme.onSecondaryContainer : t.textPrimary;
    return Material(
      color: active ? scheme.secondaryContainer : t.fill,
      shape: StadiumBorder(side: BorderSide(color: t.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mood_outlined,
                  size: 16,
                  color: mood != null ? scheme.primary : t.textSecondary),
              const SizedBox(width: 6),
              Text(
                mood == null ? '心情' : '${mood!.iconChar} ${mood!.label}',
                style: TextStyle(
                    fontSize: 13,
                    color: fg,
                    fontWeight: mood != null ? FontWeight.w600 : null,
                    fontFamily: mood != null ? 'moodfont' : null),
              ),
              const SizedBox(width: 4),
              Icon(expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: t.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
