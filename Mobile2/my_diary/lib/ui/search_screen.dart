import 'package:flutter/material.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:my_diary_mobile/ui/entry_card.dart';
import 'package:provider/provider.dart';

class SearchScreen extends StatefulWidget {
  /// 进入时预填的搜索词（如「我的」页标签云点选某标签），空则不预填。
  final String initialQuery;

  /// 标签搜索模式：仅按标签匹配（不含标题 / 正文 / 地点）。
  /// 标签云点选默认开启，保证只返回真的打了该标签的日记。
  final bool tagOnly;
  const SearchScreen({
    super.key,
    this.initialQuery = '',
    this.tagOnly = false,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final TextEditingController _ctl;
  List<JournalEntry> _results = [];

  @override
  void initState() {
    super.initState();
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
    final res = widget.tagOnly ? await store.searchByTag(q) : await store.search(q);
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
            hintText: widget.tagOnly ? '搜索标签…' : '搜索标题、正文、标签、地点…',
            border: InputBorder.none,
            hintStyle: TextStyle(color: t.textTertiary),
            prefixIcon: widget.tagOnly
                ? Icon(Icons.sell_outlined,
                    size: 18, color: t.textTertiary)
                : null,
          ),
          style: TextStyle(color: t.textPrimary, fontSize: 16),
        ),
      ),
      body: _ctl.text.trim().isEmpty
          ? Center(
              child: Text('输入关键词开始搜索',
                  style: context.caption),
            )
          : _results.isEmpty
              ? Center(
                  child: Text('没有匹配的日记', style: context.caption),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => EntryCard(entry: _results[i]),
                ),
    );
  }
}
