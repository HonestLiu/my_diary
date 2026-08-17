import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/models/sync_types.dart';
import 'package:my_diary_mobile/sync/auth_service.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:my_diary_mobile/ui/settings_screen.dart';
import 'package:provider/provider.dart';

/// 我的：个人中心 + 账户 + 同步 + 外观快捷 + 设置入口。
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<List<String>>? _conflicts;

  @override
  void initState() {
    super.initState();
    _conflicts = context.read<AppStore>().pendingConflictPaths();
  }

  int get _entryCount =>
      context.read<AppStore>().entries.length;

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

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          // 个人头部
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
                            fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('$_entryCount 篇日记 · 连续 $_streak 天',
                        style: context.caption),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 本月统计：条数 + 心情分布
          _StatsCard(entries: store.entries),
          const SizedBox(height: 14),

          // 账户
          _Card(children: [
            if (auth.isCloudAuthenticated) ...[
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: Text(auth.email ?? '已登录'),
                subtitle: const Text('云服务已连接'),
                trailing: TextButton(
                  onPressed: () async {
                    await auth.logout();
                    if (mounted) setState(() {});
                  },
                  child: const Text('注销'),
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ] else
              ListTile(
                leading: const Icon(Icons.cloud_outlined),
                title: const Text('云服务账户'),
                subtitle: const Text('登录后多端同步日记'),
                trailing: const Icon(Icons.chevron_right),
                contentPadding: EdgeInsets.zero,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SettingsScreen()),
                ),
              ),
          ]),
          const SizedBox(height: 14),

          // 同步
          _Card(children: [
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
              const SizedBox(height: 10),
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
          const SizedBox(height: 14),

          // 外观
          _Card(children: [
            const Text('主题',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
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
            const SizedBox(height: 12),
            const Text('品牌色',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
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
          const SizedBox(height: 14),

          // 设置入口
          _Card(children: [
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
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      );
}

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

class _StatsCard extends StatelessWidget {
  final List<JournalEntry> entries;
  const _StatsCard({required this.entries});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ym = DateFormat('yyyy-MM').format(DateTime.now());
    var count = 0;
    final moodCounts = <Mood, int>{};
    for (final e in entries) {
      if (e.date.startsWith(ym)) {
        count++;
        moodCounts[e.mood] = (moodCounts[e.mood] ?? 0) + 1;
      }
    }
    final ranked = moodCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = ranked.take(5).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('本月', style: context.caption),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('$count',
                        style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1)),
                    const SizedBox(width: 5),
                    Text('篇', style: context.caption),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 16),
            Container(width: 1, height: 44, color: t.border),
            const SizedBox(width: 16),
            Expanded(
              child: top.isEmpty
                  ? Text('本月还没有心情记录', style: context.caption)
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: top
                          .map((e) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: t.fill,
                                  borderRadius:
                                      BorderRadius.circular(t.radiusChip),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(e.key.emoji,
                                        style: const TextStyle(fontSize: 15)),
                                    const SizedBox(width: 5),
                                    Text('${e.value}',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: t.textSecondary,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
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
