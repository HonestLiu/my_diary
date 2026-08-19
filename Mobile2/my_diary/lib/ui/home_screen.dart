import 'dart:math' show Random;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_diary_mobile/editor/doc_view.dart';
import 'package:my_diary_mobile/editor/markdown_doc.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:my_diary_mobile/ui/detail_screen.dart';
import 'package:my_diary_mobile/ui/editor_screen.dart';
import 'package:my_diary_mobile/ui/entry_card.dart';
import 'package:my_diary_mobile/ui/profile_screen.dart';
import 'package:my_diary_mobile/ui/search_screen.dart';
import 'package:provider/provider.dart';

/// 首页日记列表的排序方式。
enum HomeSort {
  dateDesc('日期最新优先'),
  dateAsc('日期最旧优先'),
  updatedDesc('最近更新优先');

  final String label;
  const HomeSort(this.label);
}

class HomeScreen extends StatefulWidget {
  /// 主列表滚动控制器（由外壳注入，用于 FAB 感知滚动位置切换形态）。
  final ScrollController? controller;
  const HomeScreen({super.key, this.controller});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  HomeSort _sortBy = HomeSort.dateDesc; // 排序方式
  bool _onlyMedia = false; // 是否只看带媒体的日记

  /// 由外壳 FAB 在返回后调用，强制刷新时间轴。
  void refresh() => setState(() {});

  @override
  void initState() {
    super.initState();
    // 接近列表底部时触发正文分页加载（列表本身已是懒构建 + 卡片懒解码，
    // 这里把「读入正文」也变为按需）。
    widget.controller?.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final c = widget.controller;
    if (c == null || !c.hasClients || !mounted) return;
    if (c.position.extentAfter < 600) {
      context.read<AppStore>().loadMoreEntries();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final entries = store.entries;

    // 筛选 + 分组 + 排序。
    final visible = _onlyMedia
        ? entries.where((e) => e.assets.isNotEmpty).toList()
        : entries;
    final groups = <String, List<JournalEntry>>{};
    for (final e in visible) {
      groups.putIfAbsent(e.date, () => []).add(e);
    }
    final dates = groups.keys.toList();
    if (_sortBy == HomeSort.dateAsc) {
      dates.sort((a, b) => a.compareTo(b));
    } else {
      dates.sort((a, b) => b.compareTo(a));
    }
    // 「最近更新优先」：同一天内按更新时间倒序。
    if (_sortBy == HomeSort.updatedDesc) {
      for (final g in groups.values) {
        g.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      }
    }

    // 懒加载行列表：日记卡片不立即构建，滚动到可视区才由 ListView.builder
    // 调用构建器（长列表 + 整页重建时显著降低 build 开销）。
    final rows = <Widget Function()>[];
    final hasConflicts = store.lastSync?.conflicts.isNotEmpty == true;
    if (hasConflicts) {
      rows.add(() => _ConflictBanner(onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          )));
    }
    final syncError = store.syncError;
    if (syncError != null) {
      rows.add(() => _ErrorBanner(message: syncError));
    }
    for (final w in _memorySection(context, entries)) {
      rows.add(() => w);
    }
    rows.add(() => _buildToolbar(context, visible.length));
    if (visible.isEmpty) {
      rows.add(() => Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(child: Text('没有符合条件的日记', style: context.caption)),
          ));
    }
    for (final d in dates) {
      rows.add(() => _DayHeader(dateKey: d));
      final dayEntries = groups[d]!;
      for (var i = 0; i < dayEntries.length; i++) {
        if (i > 0) rows.add(() => const SizedBox(height: 12));
        final card = dayEntries[i]; // 每迭代独立绑定，闭包捕获安全
        rows.add(() => EntryCard(entry: card));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('日记'),
        actions: [
          if (store.syncEnabled)
            _SyncStatusIcon(
              syncing: store.busy,
              lastSyncAt: store.lastSyncAt,
              error: store.syncError,
              onTap: () => store.syncNow(),
            ),
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
          : ListView.builder(
              controller: widget.controller,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: rows.length,
              itemBuilder: (_, i) => rows[i](),
            ),
    );
  }

  /// 列表工具条：与日记卡片同款「柔和投影圆角卡」，内含计数 + 媒体筛选 + 排序。
  /// 位于回忆区块下方。两个按钮统一 32 高、卡片上下 padding 对称（6/6）。
  Widget _buildToolbar(BuildContext context, int count) {
    final t = context.tokens;
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      elevation: 2,
      margin: const EdgeInsets.fromLTRB(0, 12, 0, 2),
      shadowColor: Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radiusCard)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Row(
          children: [
            Text(
              '$count 篇日记',
              style: context.caption.copyWith(color: t.textSecondary),
            ),
            const Spacer(),
            // 媒体筛选 chip（统一高度，上下居中）。
            SizedBox(
              height: 32,
              child: FilterChip(
                label: Text('仅媒体',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          _onlyMedia ? FontWeight.w700 : FontWeight.w500,
                      color: _onlyMedia ? primary : t.textSecondary,
                    )),
                selected: _onlyMedia,
                onSelected: (v) => setState(() => _onlyMedia = v),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                selectedColor: primary.withValues(alpha: 0.12),
                checkmarkColor: primary,
                backgroundColor: context.cs.surface,
                side: BorderSide(
                  color: _onlyMedia
                      ? primary.withValues(alpha: 0.45)
                      : t.border,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 排序 chip：直接 onPressed 弹底部单选面板（不用 PopupMenuButton 包
            // chip，否则点击手势会被 chip 吃掉、弹不出来）。
            SizedBox(
              height: 32,
              child: ActionChip(
                avatar: Icon(Icons.sort, size: 15, color: primary),
                label: Text(_sortBy.label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: t.textSecondary)),
                onPressed: _showSortSheet,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: context.cs.surface,
                side: BorderSide(color: t.border),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 排序选择：底部单选面板（与 App 其他弹层风格一致）。
  Future<void> _showSortSheet() async {
    final t = context.tokens;
    final primary = Theme.of(context).colorScheme.primary;
    final v = await showModalBottomSheet<HomeSort>(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(t.radiusSheet)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('排序方式',
                    style: context.titleMedium),
              ),
            ),
            for (final s in HomeSort.values)
              ListTile(
                leading: Icon(
                  s == _sortBy ? Icons.check_circle : Icons.circle_outlined,
                  size: 22,
                  color: s == _sortBy ? primary : t.textTertiary,
                ),
                title: Text(s.label,
                    style: TextStyle(
                      fontWeight:
                          s == _sortBy ? FontWeight.w700 : FontWeight.w400,
                    )),
                onTap: () => Navigator.pop(context, s),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (v != null && mounted) setState(() => _sortBy = v);
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
        padding: const EdgeInsets.only(top: 24, bottom: 12),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(_dayLabel(dateKey, context), style: context.titleMedium),
          ],
        ),
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

/// AppBar 同步状态指示：同步中转圈、成功显示上次同步时间、失败显示错误，
/// 未开始显示等待。仅启用同步时显示；点击立即手动同步。
class _SyncStatusIcon extends StatelessWidget {
  final bool syncing;
  final DateTime? lastSyncAt;
  final String? error;
  final VoidCallback onTap;
  const _SyncStatusIcon({
    required this.syncing,
    required this.lastSyncAt,
    required this.error,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget icon;
    String tooltip;
    if (syncing) {
      icon = const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
      tooltip = '正在同步…';
    } else if (error != null) {
      icon = const Icon(Icons.cloud_off_outlined, color: Colors.redAccent);
      tooltip = '同步失败，点击重试';
    } else if (lastSyncAt != null) {
      icon = const Icon(Icons.cloud_done_outlined);
      tooltip = '已同步：${DateFormat('MM-dd HH:mm').format(lastSyncAt!.toLocal())}，点击手动同步';
    } else {
      icon = const Icon(Icons.cloud_sync_outlined);
      tooltip = '点击手动同步';
    }
    return Tooltip(
      message: tooltip,
      child: IconButton(icon: icon, onPressed: onTap),
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
    // 水平缩进由外层列表（padding 16）统一提供，这里只留纵向，与下方内容左对齐。
    padding: const EdgeInsets.fromLTRB(0, 18, 0, 0),
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
        height: 145,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          children: const [_MemoryEmptyCard()],
        ),
      ),
      const SizedBox(height: 6),
    ];
  }

  return [
    header,
    const SizedBox(height: 12),
    SizedBox(
      height: 145,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (c, i) => _MemoryCard(item: items[i]),
      ),
    ),
    const SizedBox(height: 6),
  ];
}

/// 回忆区空态卡：与文字回忆卡同风格（品牌色淡染渐变底），给一句简短提醒。尺寸偏小。
class _MemoryEmptyCard extends StatelessWidget {
  const _MemoryEmptyCard();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      width: 145,
      height: 145,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(accent.withValues(alpha: 0.22), t.surfaceVariant),
            t.surfaceVariant,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('✨', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 6),
          Text('还没有回忆',
              style: context.titleMedium
                  .copyWith(color: t.textPrimary, fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            '写下第一篇日记，未来的你会在这里遇见此刻。',
            style: context.caption.copyWith(color: t.textSecondary),
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
    final store = context.read<AppStore>();
    final cover = store.coverFor(e.assets);
    // 渲染后的预览：解码正文为文档块，压平成带行内样式的 span（保留加粗/斜体/代码等），
    // 而非 Markdown 源码；底色（图 / 文）决定预览基色。
    final previewBase = cover != null
        ? const TextStyle(color: Colors.white70, fontSize: 12)
        : TextStyle(color: t.textSecondary, fontSize: 12);
    final previewSpans = e.body.trim().isEmpty
        ? const <InlineSpan>[]
        : docBlocksToPreviewSpans(
            context,
            cachedDecodeEntryBody(e),
            baseStyle: previewBase,
          );
    final hasPreview =
        TextSpan(children: previewSpans).toPlainText().trim().isNotEmpty;
    final dateStr = _memoDate(e);

    final Widget inner;
    if (cover != null) {
      // 图片卡：图作底，底部暗渐变保证文字可读。
      final file = store.resolveThumb(cover);
      inner = Stack(
        fit: StackFit.expand,
        children: [
          Image.file(file,
              fit: BoxFit.cover,
              cacheWidth: 290,
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
          if (cover.kind == AssetKind.video)
            const Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: EdgeInsets.all(7),
                  child: Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 26),
                ),
              ),
            ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
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
                        fontSize: 14,
                        fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (hasPreview) ...[
                  const SizedBox(height: 3),
                  Text.rich(TextSpan(children: previewSpans),
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
              right: -6,
              top: -14,
              child: Text('忆',
                  style: TextStyle(
                      fontSize: 92,
                      fontWeight: FontWeight.w700,
                      color: accent.withValues(alpha: 0.16))),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
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
                          fontSize: 14,
                          fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  if (hasPreview) ...[
                    const SizedBox(height: 3),
                    Text.rich(TextSpan(children: previewSpans),
                        maxLines: 1,
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
      child: Container(
        width: 145,
        height: 145,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
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
