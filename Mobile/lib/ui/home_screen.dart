import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/editor_screen.dart';
import 'package:my_diary_mobile/ui/detail_screen.dart';
import 'package:my_diary_mobile/ui/search_screen.dart';
import 'package:my_diary_mobile/ui/settings_screen.dart';
import 'package:my_diary_mobile/ui/sync_screen.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final entries = store.entries;

    // 按日期分组（最新在前）。
    final groups = <String, List<JournalEntry>>{};
    for (final e in entries) {
      groups.putIfAbsent(e.date, () => []).add(e);
    }
    final dates = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(
        title: const Text('MyDiary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          IconButton(
            icon: store.busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            tooltip: '同步',
            onPressed: store.busy
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SyncScreen()),
                    ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: entries.isEmpty
          ? _EmptyState(onCreate: () => _create(context))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                if (store.lastSync?.conflicts.isNotEmpty == true)
                  _ConflictBanner(onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SyncScreen()),
                      )),
                if (store.syncError != null)
                  _ErrorBanner(message: store.syncError!),
                for (final d in dates) ...[
                  _DateHeader(dateKey: d, count: groups[d]!.length),
                  for (final e in groups[d]!) _EntryCard(entry: e),
                  const SizedBox(height: 8),
                ],
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('写日记'),
      ),
    );
  }

  void _create(BuildContext context) {
    final store = context.read<AppStore>();
    final entry = store.repo.newEntry();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditorScreen(entry: entry)),
    );
  }
}

class _DateHeader extends StatelessWidget {
  final String dateKey;
  final int count;
  const _DateHeader({required this.dateKey, required this.count});

  @override
  Widget build(BuildContext context) {
    final dt = DateFormat('yyyy-MM-dd').parse(dateKey);
    final weekday = DateFormat('EEEE', 'zh_CN').format(dt);
    final pretty = DateFormat('M 月 d 日', 'zh_CN').format(dt);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
      child: Row(
        children: [
          Text(pretty,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Text(weekday,
              style: TextStyle(
                  fontSize: 13, color: Theme.of(context).hintColor)),
          const Spacer(),
          Text('$count 篇',
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).hintColor)),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final JournalEntry entry;
  const _EntryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final preview = entry.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DetailScreen(entry: entry)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(entry.mood.emoji,
                      style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      entry.displayTitle,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (entry.assets.isNotEmpty)
                    const Icon(Icons.photo_library_outlined,
                        size: 16),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                preview.isEmpty ? '（暂无内容）' : preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).hintColor),
              ),
              if (entry.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: entry.tags
                      .map((t) => Chip(
                            label: Text('#$t'),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📖', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            const Text('还没有日记',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('写下第一篇，或先去设置里配置同步，',
                textAlign: TextAlign.center),
            const Text('把桌面端的日记拉到手机上。',
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('写第一篇日记'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConflictBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _ConflictBanner({required this.onTap});
  @override
  Widget build(BuildContext context) => Card(
        color: Colors.orange.shade50,
        child: ListTile(
          leading: const Icon(Icons.warning_amber_rounded,
              color: Colors.orange),
          title: const Text('存在同步冲突，待你处理'),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});
  @override
  Widget build(BuildContext context) => Card(
        color: Colors.red.shade50,
        child: ListTile(
          leading: const Icon(Icons.error_outline, color: Colors.red),
          title: Text('同步出错：$message',
              maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      );
}
