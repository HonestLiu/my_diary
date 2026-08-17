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
  const SearchScreen({
    super.key,
    this.initialQuery = '',
    this.initialFilters = const {},
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final TextEditingController _ctl;
  List<JournalEntry> _results = [];
  late final Set<SearchScope> _filters;

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
    _ctl = TextEditingController(text: widget.initialQuery);
    _ctl.addListener(_onChanged);
    if (widget.initialQuery.trim().isNotEmpty) {
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
    if (q.trim().isEmpty) {
      if (mounted) setState(() => _results = []);
      return;
    }
    final store = context.read<AppStore>();
    final res = await store.search(q, filters: _filters);
    if (mounted) setState(() => _results = res);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: _filters.isEmpty
                ? '搜索标题、正文、标签、地点…'
                : '搜索${_filters.map((f) => f.label).join('、')}…',
            border: InputBorder.none,
            hintStyle: TextStyle(color: t.textTertiary),
          ),
          style: TextStyle(color: t.textPrimary, fontSize: 16),
        ),
      ),
      body: Column(
        children: [
          // 搜索范围筛选器：点击切换搜索哪些字段。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Wrap(
              spacing: 8,
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
          const Divider(height: 1),
          Expanded(
            child: _ctl.text.trim().isEmpty
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
                        separatorBuilder: (_, __) =>
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
