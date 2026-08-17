import 'package:flutter/material.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:my_diary_mobile/ui/detail_screen.dart';
import 'package:provider/provider.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctl = TextEditingController();
  List<JournalEntry> _results = [];

  @override
  void initState() {
    super.initState();
    _ctl.addListener(_onChanged);
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
    final res = await store.search(q);
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
            hintText: '搜索标题、正文、标签、地点…',
            border: InputBorder.none,
            hintStyle: TextStyle(color: t.textTertiary),
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
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final e = _results[i];
                    final preview =
                        e.body.replaceAll(RegExp(r'\s+'), ' ').trim();
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => DetailScreen(entry: e)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: t.fill,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.center,
                                child: Text(e.mood.emoji,
                                    style: const TextStyle(fontSize: 20)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(e.displayTitle,
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 5),
                                    Text(
                                      preview.isEmpty
                                          ? e.date
                                          : preview,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.caption,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
