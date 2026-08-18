import 'package:flutter/material.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:my_diary_mobile/ui/entry_card.dart';
import 'package:provider/provider.dart';

/// 喜欢的日记：展示全部带喜欢标记（favorite）的日记，按日期降序分组，
/// 复用首页的 EntryCard，点击进详情。
class FavoriteScreen extends StatelessWidget {
  const FavoriteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final t = context.tokens;
    final favorites = store.entries.where((e) => e.favorite).toList()
      ..sort((a, b) => byRecencySort(a, b));

    return Scaffold(
      appBar: AppBar(
        title: const Text('喜欢的日记'),
        actions: [
          if (favorites.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text('${favorites.length} 篇', style: context.caption),
              ),
            ),
        ],
      ),
      body: favorites.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite_border,
                        size: 44, color: t.textTertiary),
                    const SizedBox(height: 16),
                    Text('还没有喜欢的日记', style: context.titleMedium),
                    const SizedBox(height: 6),
                    Text('在日记详情页点右上角 ♡，就能在这里快速找到。',
                        style: context.caption, textAlign: TextAlign.center),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: favorites.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: EntryCard(entry: favorites[i]),
              ),
            ),
    );
  }
}

/// 排序：日期降序，同日按创建时间降序（最新在前）。
int byRecencySort(JournalEntry a, JournalEntry b) {
  if (a.date != b.date) return b.date.compareTo(a.date);
  return b.createdAt.compareTo(a.createdAt);
}
