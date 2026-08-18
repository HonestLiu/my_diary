import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/models/sync_types.dart';
import 'package:my_diary_mobile/sync/auth_service.dart';
import 'package:my_diary_mobile/repository/journal_repository.dart';
import 'package:my_diary_mobile/services/export_service.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:my_diary_mobile/ui/favorite_screen.dart';
import 'package:my_diary_mobile/ui/search_screen.dart';
import 'package:my_diary_mobile/ui/settings_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

/// 我的：个人中心 + 统计 + 账户与同步 + 外观快捷 + 设置入口。
/// 精致卡片风：柔和投影无边框卡，散落小组件合并成更少的卡。
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<List<String>>? _conflicts;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _conflicts = context.read<AppStore>().pendingConflictPaths();
  }

  int get _streak {
    final dates = context
        .read<AppStore>()
        .entries
        .map((e) => e.date)
        .toSet();
    if (dates.isEmpty) return 0;
    var cursor = DateTime.now();
    var streak = 0;
    // 若今天没写，允许从昨天起算连续。
    if (!dates.contains(_key(cursor))) cursor = cursor.subtract(const Duration(days: 1));
    while (dates.contains(_key(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _sync() async {
    final store = context.read<AppStore>();
    await store.syncNow();
    if (mounted) setState(() => _conflicts = store.pendingConflictPaths());
  }

  /// 导出完整备份：流式生成 zip 到临时目录后走系统分享面板
  /// （移动端 saveFile 强制要求 bytes，整包进内存违背流式初衷，故用分享）。
  Future<void> _exportFullBackup() async {
    final store = context.read<AppStore>();
    setState(() => _exporting = true);
    try {
      final tmp = await getTemporaryDirectory();
      final stamp = DateFormat('yyyyMMdd-HHmm').format(DateTime.now());
      final zipPath = '${tmp.path}/my-diary-full-$stamp.zip';
      final count =
          await ExportService.buildFullZip(store.repo.storage.root, zipPath);
      if (!mounted) return;
      if (count == 0) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('还没有可导出的数据')));
        return;
      }
      await Share.shareXFiles(
        [XFile(zipPath, mimeType: 'application/zip')],
        text: 'MyDiary 完整备份（$count 个文件）',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('备份已生成（$count 个文件）：$zipPath'),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _resolve(String path, ConflictResolution r) async {
    final store = context.read<AppStore>();
    await store.resolveConflict(path, r);
    if (mounted) {
      setState(() => _conflicts = store.pendingConflictPaths());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r == ConflictResolution.local
              ? '已保留本地版本'
              : '已采用远程版本')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final auth = context.watch<AuthService>();
    final t = context.tokens;
    final s = store.settings;
    final sync = s.sync;
    final total = store.entries.length;
    final favCount = store.entries.where((e) => e.favorite).length;
    final ym = DateFormat('yyyy-MM').format(DateTime.now());
    final monthCount =
        store.entries.where((e) => e.date.startsWith(ym)).length;
    // 标签云：聚合全部标签的出现次数，降序排列。
    final tagCounts = <String, int>{};
    for (final e in store.entries) {
      for (final tag in e.tags) {
        tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
      }
    }
    final tagCloud = tagCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          // 卡 1：个人头部 + 三格统计
          _Card(children: [
            Row(
              children: [
                _Avatar(name: s.displayName, size: 64),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.displayName.isEmpty ? '我' : s.displayName,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('$total 篇日记 · 连续 $_streak 天',
                          style: context.caption),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                _StatTile(
                    icon: Icons.calendar_today_outlined,
                    value: '$monthCount',
                    label: '本月'),
                _vDivider(t),
                _StatTile(
                    icon: Icons.local_fire_department_outlined,
                    value: '$_streak',
                    label: '连续'),
                _vDivider(t),
                _StatTile(
                  icon: Icons.favorite,
                  value: '$favCount',
                  label: '喜欢',
                  iconColor: Colors.redAccent,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FavoriteScreen()),
                  ),
                ),
                _vDivider(t),
                _StatTile(
                    icon: Icons.article_outlined,
                    value: '$total',
                    label: '总计'),
              ],
            ),
          ]),
          const SizedBox(height: 16),

          // 卡 2：心情 / 天气分布（Tab 切换，统计全部日记）
          _StatsChartCard(
            moodData: _distribution(
              store.entries,
              (e) => e.mood,
              Mood.ordered,
              (m) => Text(m.emoji,
                  style: const TextStyle(fontSize: 17)),
              (m) => m.label,
            ),
            weatherData: _distribution(
              store.entries,
              (e) => e.weather,
              Weather.ordered.where((w) => w != Weather.unknown),
              (w) => Icon(w.iconData,
                  size: 17, color: t.textSecondary),
              (w) => w.label,
            ),
          ),
          const SizedBox(height: 16),

          // 卡 4：标签云
          _TagCloudCard(tags: tagCloud),
          const SizedBox(height: 16),

          // 卡 5：账户与同步
          _Card(children: [
            if (auth.isCloudAuthenticated)
              Row(
                children: [
                  const Icon(Icons.verified_user_outlined, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(auth.email ?? '已登录',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text('云服务已连接', style: context.caption),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await auth.logout();
                      if (mounted) setState(() {});
                    },
                    child: const Text('注销'),
                  ),
                ],
              )
            else
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SettingsScreen()),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_outlined, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('云服务账户',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('登录后多端同步日记', style: context.caption),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: t.textTertiary),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(sync.enabled
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    sync.enabled
                        ? '同步已启用 · ${_providerLabel(sync.provider)}'
                        : '同步未启用',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: store.busy ? null : _sync,
                icon: store.busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.sync),
                label: Text(store.busy ? '同步中…' : '立即同步'),
              ),
            ),
            if (store.lastSyncAt != null) ...[
              const SizedBox(height: 8),
              Text('上次同步：${DateFormat('MM-dd HH:mm').format(store.lastSyncAt!.toLocal())}',
                  style: context.caption),
            ],
            if (store.lastSync != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  _Stat(label: '上传', value: store.lastSync!.uploaded.length),
                  _Stat(label: '下载', value: store.lastSync!.downloaded.length),
                  _Stat(
                      label: '冲突',
                      value: store.lastSync!.conflicts.length,
                      danger: store.lastSync!.conflicts.isNotEmpty),
                ],
              ),
            ],
            FutureBuilder<List<String>>(
              future: _conflicts,
              builder: (c, snap) {
                final conflicts = snap.data;
                if (conflicts == null || conflicts.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                    Text('待解决冲突',
                        style: context.titleMedium),
                    const SizedBox(height: 8),
                    for (final p in conflicts)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: t.fill,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.split('/').last,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () =>
                                        _resolve(p, ConflictResolution.local),
                                    child: const Text('保留本地'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: () => _resolve(
                                        p, ConflictResolution.remote),
                                    child: const Text('采用远程'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ]),
          const SizedBox(height: 16),

          // 卡 6：外观
          _Card(children: [
            const Text('主题',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            SegmentedButton<ThemePreference>(
              segments: const [
                ButtonSegment(
                    value: ThemePreference.light, label: Text('亮')),
                ButtonSegment(
                    value: ThemePreference.dark, label: Text('暗')),
                ButtonSegment(
                    value: ThemePreference.system, label: Text('跟随系统')),
              ],
              selected: {s.theme},
              onSelectionChanged: (sel) => store
                  .saveSettings(s.copyWith(theme: sel.first)),
            ),
            const SizedBox(height: 18),
            const Text('品牌色',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              children: AccentKey.values
                  .map((a) => InkWell(
                        onTap: () =>
                            store.saveSettings(s.copyWith(accent: a)),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: accentSeeds[a],
                            shape: BoxShape.circle,
                            border: s.accent == a
                                ? Border.all(
                                    color: t.textPrimary, width: 2.5)
                                : null,
                          ),
                          child: s.accent == a
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 18)
                              : null,
                        ),
                      ))
                  .toList(),
            ),
          ]),
          const SizedBox(height: 16),

          // 卡 7：导出与设置入口
          _Card(children: [
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('导出完整备份'),
              subtitle: const Text('含图片/音视频等全部数据（流式压缩）'),
              trailing: _exporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.chevron_right),
              contentPadding: EdgeInsets.zero,
              onTap: _exporting ? null : _exportFullBackup,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('全部设置'),
              subtitle: const Text('同步方式 · 默认心情 · 昵称'),
              trailing: const Icon(Icons.chevron_right),
              contentPadding: EdgeInsets.zero,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SettingsScreen()),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Center(
            child: Text('MyDiary · 本地优先的日记',
                style: TextStyle(fontSize: 12, color: t.textTertiary)),
          ),
        ],
      ),
    );
  }

  String _providerLabel(SyncProvider p) {
    switch (p) {
      case SyncProvider.none:
        return '未启用';
      case SyncProvider.cloud:
        return '云服务';
      case SyncProvider.s3:
        return 'S3';
      case SyncProvider.r2:
        return 'Cloudflare R2';
      case SyncProvider.minio:
        return 'MinIO';
      case SyncProvider.oss:
        return '阿里云 OSS';
    }
  }

  /// 统计某维度（心情 / 天气）在全部日记中的分布，返回降序排列、含全部类别（含 0 值）。
  List<_BarDatum> _distribution<T>(
    List<JournalEntry> entries,
    T Function(JournalEntry) pick,
    Iterable<T> ordered,
    Widget Function(T) iconBuilder,
    String Function(T) label,
  ) {
    final counts = <T, int>{};
    for (final e in entries) {
      final k = pick(e);
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final list = ordered
        .map((k) => _BarDatum(iconBuilder(k), label(k), counts[k] ?? 0))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return list;
  }
}

/// 精致卡片：柔和投影、无边框、统一圆角与内距。
class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) => Card(
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(context.tokens.radiusCard)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      );
}

/// 标签云卡片：按使用频次缩放字号与色彩浓度（高频更大更深），
/// 最多展示前 15 个；点击某标签跳转搜索该标签。
class _TagCloudCard extends StatelessWidget {
  final List<MapEntry<String, int>> tags; // 已按 count 降序
  const _TagCloudCard({required this.tags});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final primary = Theme.of(context).colorScheme.primary;
    final maxCount = tags.isEmpty ? 1 : tags.first.value;
    final shown = tags.take(15).toList();

    return _Card(
      children: [
        Row(
          children: [
            Icon(Icons.sell_outlined, size: 18, color: t.textSecondary),
            const SizedBox(width: 8),
            Text('标签云', style: context.titleMedium),
            const Spacer(),
            Text('共 ${tags.length} 个', style: context.caption),
          ],
        ),
        const SizedBox(height: 16),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              '还没有标签，写日记时给条目加标签后，会在这里按使用频次汇总成云。',
              style: context.caption,
            ),
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: shown.map((e) {
              final ratio = e.value / maxCount; // 0..1
              return InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SearchScreen(
                      initialQuery: e.key,
                      initialFilters: {SearchScope.tags},
                    ),
                  ),
                ),
                borderRadius: BorderRadius.circular(t.radiusChip),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.08 + ratio * 0.12),
                    borderRadius: BorderRadius.circular(t.radiusChip),
                  ),
                  child: Text('#${e.key}',
                      style: TextStyle(
                        fontSize: 11 + ratio * 4,
                        fontWeight: FontWeight.w600,
                        color: primary.withValues(alpha: 0.55 + ratio * 0.45),
                      )),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

/// 统计格：图标 + 大数字 + 小标签（纵排，靠竖线分隔）。
/// 可选 [onTap] 变为可点击（如「喜欢」进列表页）。
class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color? iconColor; // 缺省用次级文字色
  final VoidCallback? onTap;
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final content = Column(
      children: [
        Icon(icon, size: 19, color: iconColor ?? t.textSecondary),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                height: 1.1)),
        const SizedBox(height: 3),
        Text(label, style: context.caption),
      ],
    );
    // Expanded 必须是 Row 的直接子级才能均分宽度，
    // 因此 InkWell 包在内容上、Expanded 留在最外层。
    final inner = onTap == null
        ? content
        : InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: content,
          );
    return Expanded(child: inner);
  }
}

/// 统计格之间的细分隔竖线。
Widget _vDivider(AppTokens t) => Container(
      width: 1,
      height: 46,
      color: t.border,
    );

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final bool danger;
  const _Stat(
      {required this.label, required this.value, this.danger = false});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: context.tokens.fill,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text('$value',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: danger
                          ? const Color(0xFFB42318)
                          : context.tokens.textPrimary)),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: 12, color: context.tokens.textSecondary)),
            ],
          ),
        ),
      );
}

/// 柱状图单条数据：图标 widget（emoji 文本 / iconfont 图标）+ 中文标签 + 计数。
class _BarDatum {
  final Widget icon;
  final String label;
  final int count;
  const _BarDatum(this.icon, this.label, this.count);
}

/// 心情 / 天气分布统计卡：顶部 Tab 切换（心情 | 天气），
/// 柱状图统计全部日记的分布，跟随当前品牌强调色。
class _StatsChartCard extends StatefulWidget {
  final List<_BarDatum> moodData;
  final List<_BarDatum> weatherData;
  const _StatsChartCard({
    required this.moodData,
    required this.weatherData,
  });

  @override
  State<_StatsChartCard> createState() => _StatsChartCardState();
}

class _StatsChartCardState extends State<_StatsChartCard> {
  bool _showMood = true; // true=心情，false=天气

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final primary = Theme.of(context).colorScheme.primary;
    final data = _showMood ? widget.moodData : widget.weatherData;
    final total = data.fold<int>(0, (s, d) => s + d.count);
    final maxCount = data.isEmpty
        ? 1
        : data.map((d) => d.count).reduce((a, b) => a > b ? a : b);

    return _Card(
      children: [
        Row(
          children: [
            Icon(
                _showMood ? Icons.mood_outlined : Icons.wb_sunny_outlined,
                size: 18,
                color: t.textSecondary),
            const SizedBox(width: 8),
            Text(_showMood ? '心情统计' : '天气统计', style: context.titleMedium),
            const Spacer(),
            Text(total == 0 ? '暂无记录' : '共 $total 次',
                style: context.caption),
          ],
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: true,
              label: Text('心情'),
              icon: Icon(Icons.mood_outlined, size: 16),
            ),
            ButtonSegment(
              value: false,
              label: Text('天气'),
              icon: Icon(Icons.wb_sunny_outlined, size: 16),
            ),
          ],
          selected: {_showMood},
          onSelectionChanged: (s) => setState(() => _showMood = s.first),
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll(
                Theme.of(context).textTheme.labelLarge),
          ),
        ),
        const SizedBox(height: 16),
        if (total == 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Center(
              child: Text('还没有记录', style: context.caption),
            ),
          )
        else ...[
          SizedBox(
            height: 132,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: data.map((d) {
                final ratio = maxCount == 0 ? 0.0 : d.count / maxCount;
                final barH = 10.0 + ratio * 100.0; // 最小 10，最大 110
                final isZero = d.count == 0;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('${d.count}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isZero
                                  ? t.textTertiary
                                  : t.textPrimary)),
                      const SizedBox(height: 5),
                      Container(
                        width: double.infinity,
                        height: barH,
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          // 0 值用中性空槽（浅底 + 描边），避免强调色顶满再配空槽的突兀感。
                          color: isZero ? t.fill : null,
                          gradient: isZero
                              ? null
                              : LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    primary,
                                    primary.withValues(alpha: 0.5),
                                  ],
                                ),
                          border: isZero
                              ? Border.all(color: t.border, width: 1)
                              : null,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6)),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: data
                .map((d) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Column(
                          children: [
                            SizedBox(
                              width: 17,
                              height: 17,
                              child: Center(child: d.icon),
                            ),
                            const SizedBox(height: 3),
                            Text(d.label,
                                style: TextStyle(
                                    fontSize: 11, color: t.textTertiary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final double size;
  const _Avatar({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    final src = name.isEmpty ? '我' : name;
    final letter = String.fromCharCode(src.runes.first);
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(letter,
          style: TextStyle(
              fontSize: size * 0.4,
              fontWeight: FontWeight.w700,
              color: color)),
    );
  }
}
