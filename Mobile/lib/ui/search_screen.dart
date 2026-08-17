import 'package:flutter/material.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
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
    final store = context.read<AppStore>();
    final res = await store.search(q);
    if (mounted) setState(() => _results = res);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜索标题、正文、标签、地点…',
            border: InputBorder.none,
          ),
        ),
      ),
      body: _results.isEmpty
          ? const Center(child: Text('没有匹配的日记'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _results.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final e = _results[i];
                final preview =
                    e.body.replaceAll(RegExp(r'\s+'), ' ').trim();
                return Card(
                  child: ListTile(
                    title: Text(e.displayTitle),
                    subtitle: Text(
                      preview.isEmpty ? e.date : '$preview',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(e.mood.emoji),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => DetailScreen(entry: e)),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
