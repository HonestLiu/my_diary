import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:my_diary_mobile/ui/detail_screen.dart';
import 'package:my_diary_mobile/ui/editor_screen.dart';
import 'package:my_diary_mobile/ui/profile_screen.dart';
import 'package:my_diary_mobile/ui/search_screen.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  /// 由外壳 FAB 在返回后调用，强制刷新时间轴。
  void refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final entries = store.entries;

    final groups = <String, List<JournalEntry>>{};
    for (final e in entries) {
      groups.putIfAbsent(e.date, () => []).add(e);
    }
    final dates = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(
        title: const Text('日记'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_outlined),
            tooltip: '搜索',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
        ],
      ),
      body: entries.isEmpty
          ? _EmptyState(onCreate: () => _create(context))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (store.lastSync?.conflicts.isNotEmpty == true)
                  _ConflictBanner(onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ProfileScreen()),
                      )),
                if (store.syncError != null)
                  _ErrorBanner(message: store.syncError!),
                for (final d in dates) ...[
                  _DayHeader(dateKey: d),
                  const SizedBox(height: 8),
                  for (final e in groups[d]!) ...[
                    _EntryCard(entry: e),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
    );
  }

  void _create(BuildContext context) {
    final store = context.read<AppStore>();
    final entry = store.repo.newEntry();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditorScreen(entry: entry)),
    ).then((_) => refresh());
  }
}

String _dayLabel(String dateKey, BuildContext context) {
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

class _DayHeader extends StatelessWidget {
  final String dateKey;
  const _DayHeader({required this.dateKey});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
        child: Text(_dayLabel(dateKey, context),
            style: context.titleMedium),
      );
}

class _EntryCard extends StatelessWidget {
  final JournalEntry entry;
  const _EntryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final imgs = entry.assets.where((a) => a.kind == AssetKind.image);
    final cover = imgs.isEmpty ? null : imgs.first;
    final preview = entry.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    final loc = entry.location?.trim() ?? '';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.displayTitle,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          preview.isEmpty ? '（暂无内容）' : preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.caption,
                        ),
                      ],
                    ),
                  ),
                  if (cover != null) ...[
                    const SizedBox(width: 12),
                    _Thumb(asset: cover),
                  ],
                ],
              ),
              // 底部 meta：心情 / 天气 / 定位 / 标签
              _CardMeta(entry: entry, location: loc),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardMeta extends StatelessWidget {
  final JournalEntry entry;
  final String location;
  const _CardMeta({required this.entry, required this.location});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final chips = <Widget>[
      _metaItem(context, '${entry.mood.emoji} ${entry.mood.label}'),
      _metaItem(context, '${entry.weather.emoji} ${entry.weather.label}'),
      if (location.isNotEmpty)
        _metaItem(context, location, icon: Icons.place_outlined),
      ...entry.tags.map((tag) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: t.fill,
              borderRadius: BorderRadius.circular(t.radiusChip),
            ),
            child: Text('#$tag',
                style: TextStyle(fontSize: 12, color: t.textSecondary)),
          )),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: chips,
      ),
    );
  }

  Widget _metaItem(BuildContext context, String text, {IconData? icon}) {
    final tertiary = context.tokens.textTertiary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: tertiary),
          const SizedBox(width: 3),
        ],
        Text(text, style: TextStyle(fontSize: 12, color: tertiary)),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  final AssetRef asset;
  const _Thumb({required this.asset});

  @override
  Widget build(BuildContext context) {
    final file = context.read<AppStore>().resolveAsset(asset.path);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.file(file, width: 56, height: 56, fit: BoxFit.cover),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: t.surfaceVariant,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Text('📖', style: TextStyle(fontSize: 40)),
            ),
            const SizedBox(height: 20),
            Text('还没有日记',
                style: context.titleLarge),
            const SizedBox(height: 6),
            Text('写下第一篇，记录今天的故事。',
                style: context.caption),
            const SizedBox(height: 22),
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: const Color(0xFFFEF3F2),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFB42318)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('存在同步冲突，待你处理',
                        style: TextStyle(
                            color: Color(0xFFB42318),
                            fontWeight: FontWeight.w600)),
                  ),
                  const Icon(Icons.chevron_right,
                      color: Color(0xFFB42318)),
                ],
              ),
            ),
          ),
        ),
      );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: const Color(0xFFFEF3F2),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Color(0xFFB42318)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('同步出错：$message',
                      style: const TextStyle(color: Color(0xFFB42318)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      );
}
