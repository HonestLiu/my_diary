import 'dart:math' show Random;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:my_diary_mobile/ui/detail_screen.dart';
import 'package:my_diary_mobile/ui/editor_screen.dart';
import 'package:my_diary_mobile/ui/entry_card.dart';
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
                ..._memorySection(context, entries),
                for (final d in dates) ...[
                  _DayHeader(dateKey: d),
                  const SizedBox(height: 8),
                  for (final e in groups[d]!) ...[
                    EntryCard(entry: e),
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

/// 回忆区块：首页顶部横向可拖动的「回忆」卡片。
/// 数据来源两类：① 往年的今天（月日与今天相同、年份更早的日记）；
/// ② 日期早于「now-2个月」的全部日记（随机抽补）。两者合并，最多加载 10 张。
/// 即使两类都为空，区块本身也会保留，只放一张简短的提醒卡（鼓励继续记录）。
List<Widget> _memorySection(BuildContext context, List<JournalEntry> entries) {
  final items = _buildMemories(entries);
  final t = context.tokens;
  final header = Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
    child: Row(
      children: [
        Icon(Icons.auto_awesome_outlined, size: 18, color: t.textSecondary),
        const SizedBox(width: 8),
        Text('回忆', style: context.titleMedium),
        const Spacer(),
        Text('左右滑动 →', style: context.caption),
      ],
    ),
  );

  // 没有回忆时，仍保留区块，放一张简短提示卡，鼓励继续记录。
  if (items.isEmpty) {
    return [
      header,
      const SizedBox(height: 12),
      SizedBox(
        height: 200,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: const [_MemoryEmptyCard()],
        ),
      ),
      const SizedBox(height: 22),
    ];
  }

  return [
    header,
    const SizedBox(height: 12),
    SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (c, i) => _MemoryCard(item: items[i]),
      ),
    ),
    const SizedBox(height: 22),
  ];
}

/// 回忆区空态卡：与文字回忆卡同风格（品牌色淡染渐变底），给一句简短提醒。
class _MemoryEmptyCard extends StatelessWidget {
  const _MemoryEmptyCard();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      width: 196,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(accent.withValues(alpha: 0.22), t.surfaceVariant),
            t.surfaceVariant,
          ],
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('✨', style: TextStyle(fontSize: 22)),
          const SizedBox(height: 12),
          Text('还没有回忆',
              style: context.titleMedium.copyWith(color: t.textPrimary)),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              '写下更多日记吧，将来的你会在「回忆」里遇见此刻的自己。',
              style: context.caption.copyWith(color: t.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// 计算回忆卡片数据：往年的今天优先，再用「2 个月之前（含更早）」的随机补足，合计 ≤ 10。
List<_MemoryItem> _buildMemories(List<JournalEntry> entries) {
  final now = DateTime.now();
  final todayMd = _md(now);

  // ① 往年的今天：月日相同、且年份早于今年。
  final onThisDay = <_MemoryItem>[];
  final onThisDayIds = <String>{};
  for (final e in entries) {
    final d = DateTime.tryParse(e.date);
    if (d == null || d.year >= now.year) continue;
    if (_md(d) != todayMd) continue;
    onThisDay.add(_MemoryItem(e, '往年的今天 · ${d.year}', 'onThisDay'));
    onThisDayIds.add(e.id);
  }

  // ② 2 个月之前：日期早于 (now - 2 个月) 的全部日记，随机抽补。
  //    注意是「之前的全部」，不只 2 个月那一月——更早（如 5 月及以前）都纳入。
  final cutoff = DateTime(now.year, now.month - 2, now.day);
  final recent = entries.where((e) {
    if (onThisDayIds.contains(e.id)) return false; // 不重复计入
    final d = DateTime.tryParse(e.date);
    if (d == null) return false;
    return d.isBefore(cutoff);
  }).toList();
  // 以「当天」为种子随机打乱：同一天内稳定（不会每次 rebuild 抖动），跨天自然变化。
  final rng = Random(now.year * 372 + now.month * 31 + now.day);
  recent.shuffle(rng);

  // 合并：往年的今天在前（更值得回味的「锚点」），2 个月之前的随机补后，封顶 10。
  final items = <_MemoryItem>[...onThisDay];
  for (final e in recent) {
    if (items.length >= 10) break;
    final d = DateTime.tryParse(e.date);
    final label = d == null
        ? '回忆'
        : (d.year == now.year
            ? '${d.month}月'
            : '${d.year}年${d.month}月');
    items.add(_MemoryItem(e, label, 'recent'));
  }
  return items.take(10).toList();
}

/// 单张回忆卡片的数据载体。
class _MemoryItem {
  final JournalEntry entry;
  final String badge; // 角标文案，如「往年的今天 · 2023」「2 个月前」
  final String kind; // 'onThisDay' | 'recent'
  const _MemoryItem(this.entry, this.badge, this.kind);
}

/// 回忆卡片：有图片则以图为底（暗色遮罩 + 白字），无图则为带品牌色淡染的纯文字卡（背景水印「忆」），风格统一、略带艺术感。
class _MemoryCard extends StatelessWidget {
  final _MemoryItem item;
  const _MemoryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final e = item.entry;
    final t = context.tokens;
    final accent = Theme.of(context).colorScheme.primary;
    final imgs = e.assets.where((a) => a.kind == AssetKind.image);
    final cover = imgs.isEmpty ? null : imgs.first;
    final preview = e.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    final dateStr = _memoDate(e);

    final Widget inner;
    if (cover != null) {
      // 图片卡：图作底，底部暗渐变保证文字可读。
      final file = context.read<AppStore>().resolveAsset(cover.path);
      inner = Stack(
        fit: StackFit.expand,
        children: [
          Image.file(file,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: t.fill)),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.72),
                ],
              ),
            ),
          ),
          Positioned(
            top: 10,
            left: 10,
            child: _memoBadge(context, item.badge, dark: true),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(dateStr,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(e.displayTitle,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(preview,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        ],
      );
    } else {
      // 文字卡：品牌色淡染底 + 大号水印「忆」，营造回忆氛围。
      inner = Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              t.surfaceVariant,
              Color.alphaBlend(
                  accent.withValues(alpha: 0.22), t.surfaceVariant),
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -8,
              top: -18,
              child: Text('忆',
                  style: TextStyle(
                      fontSize: 130,
                      fontWeight: FontWeight.w700,
                      color: accent.withValues(alpha: 0.16))),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _memoBadge(context, item.badge, dark: false),
                  const Spacer(),
                  Text(dateStr,
                      style: TextStyle(
                          color: t.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(e.displayTitle,
                      style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(preview,
                        style: TextStyle(
                            color: t.textSecondary, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DetailScreen(entry: e)),
      ),
      child: SizedBox(
        width: 196,
        height: 200,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: inner,
        ),
      ),
    );
  }
}

/// 回忆角标：sparkle 图标 + 文案；深色图卡用半透明黑底白字，浅色文字卡用 fill 底 + 品牌色字。
Widget _memoBadge(BuildContext context, String text, {required bool dark}) {
  final accent = Theme.of(context).colorScheme.primary;
  final t = context.tokens;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: dark ? Colors.black.withValues(alpha: 0.32) : t.fill,
      borderRadius: BorderRadius.circular(t.radiusChip),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.auto_awesome_outlined,
            size: 12, color: dark ? Colors.white70 : accent),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: dark ? Colors.white : accent)),
      ],
    ),
  );
}

String _memoDate(JournalEntry e) {
  final d = DateTime.tryParse(e.date);
  if (d == null) return '';
  return '${DateFormat('M月d日').format(d)} · ${DateFormat('EEEE', 'zh_CN').format(d)}';
}

String _md(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
