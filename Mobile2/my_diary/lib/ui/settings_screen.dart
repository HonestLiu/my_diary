import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/models/sync_types.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:my_diary_mobile/sync/auth_service.dart';
import 'package:my_diary_mobile/services/export_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

/// 直接对象存储（S3 / R2 / MinIO / OSS）：需要 SigV4 凭据，本地配置。
bool _isDirect(SyncProvider p) =>
    p == SyncProvider.s3 ||
    p == SyncProvider.r2 ||
    p == SyncProvider.minio ||
    p == SyncProvider.oss;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late ThemePreference _theme;
  late AccentKey _accent;
  late FontKey _font;
  late Mood _defaultMood;
  late String _displayName;
  late int _weekStartsOn;

  late SyncProvider _provider;
  late bool _pathStyle;
  late int _autoSyncMinutes; // 定期自动同步间隔（分钟）；0 = 关闭
  late bool _autoLocateNew;
  late bool _showDetailMap;
  late int _imageQuality; // 图片上传压缩质量（1–100）
  late int _videoQuality; // 视频上传压缩质量（1–100）

  late TextEditingController _displayNameCtl;
  late TextEditingController _endpointCtl;
  late TextEditingController _bucketCtl;
  late TextEditingController _regionCtl;
  late TextEditingController _accessKeyCtl;
  late TextEditingController _secretKeyCtl;

  bool _exporting = false;
  late Future<List<String>> _conflicts;

  /// 已导出的本地备份 zip（临时目录下 `my-diary-full-*.zip`），新→旧。
  List<({String path, String name, int size, DateTime modified})> _backups = [];

  @override
  void initState() {
    super.initState();
    // 首帧后加载历史备份列表（避免在 initState 里 setState）。
    Future.microtask(_loadBackups);
    final s = context.read<AppStore>().settings;
    // 云账号已移除：历史 cloud 配置降级为「不使用同步」，避免下拉项缺失报错。
    _provider = s.sync.provider == SyncProvider.cloud
        ? SyncProvider.none
        : s.sync.provider;
    _theme = s.theme;
    _accent = s.accent;
    _font = s.font;
    _defaultMood = s.defaultMood;
    _displayName = s.displayName;
    _weekStartsOn = s.weekStartsOn;
    _pathStyle = s.sync.effectivePathStyle();
    _autoSyncMinutes = s.sync.autoSyncIntervalMinutes;
    _autoLocateNew = s.autoLocateNew;
    _showDetailMap = s.showDetailMap;
    _imageQuality = s.imageCompressQuality;
    _videoQuality = s.videoCompressQuality;

    _displayNameCtl = TextEditingController(text: _displayName);
    _endpointCtl = TextEditingController(text: s.sync.endpoint ?? '');
    _bucketCtl = TextEditingController(text: s.sync.bucket ?? '');
    _regionCtl = TextEditingController(text: s.sync.region ?? '');
    _accessKeyCtl = TextEditingController();
    _secretKeyCtl = TextEditingController();
    _conflicts = context.read<AppStore>().pendingConflictPaths();
  }

  @override
  void dispose() {
    _displayNameCtl.dispose();
    _endpointCtl.dispose();
    _bucketCtl.dispose();
    _regionCtl.dispose();
    _accessKeyCtl.dispose();
    _secretKeyCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = context.read<AppStore>();
    final auth = context.read<AuthService>();

    final sync = SyncConfig(
      enabled: _provider != SyncProvider.none,
      provider: _provider,
      endpoint: _isDirect(_provider) ? _endpointCtl.text.trim() : null,
      bucket: _isDirect(_provider) ? _bucketCtl.text.trim() : null,
      region: _isDirect(_provider) ? _regionCtl.text.trim() : null,
      pathStyle: _isDirect(_provider) ? _pathStyle : null,
      autoSyncIntervalMinutes: _isDirect(_provider) ? _autoSyncMinutes : 0,
    );

    // 直接对象存储秘钥存本地保险箱（不经过 settings.json，避免明文落盘）。
    final ak = _accessKeyCtl.text.trim();
    final sk = _secretKeyCtl.text.trim();
    if (ak.isNotEmpty && sk.isNotEmpty) {
      await auth.saveS3Secrets(ak, sk);
    }

    final newSettings = store.settings.copyWith(
      theme: _theme,
      accent: _accent,
      font: _font,
      displayName: _displayNameCtl.text.trim(),
      weekStartsOn: _weekStartsOn,
      defaultMood: _defaultMood,
      sync: sync,
      autoLocateNew: _autoLocateNew,
      showDetailMap: _showDetailMap,
      imageCompressQuality: _imageQuality,
      videoCompressQuality: _videoQuality,
    );
    await store.saveSettings(newSettings);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('设置已保存')));
      Navigator.pop(context);
    }
  }

  Future<void> _sync() async {
    final store = context.read<AppStore>();
    await store.syncNow();
    if (!mounted) return;
    setState(() {
      // 同步回调须为同步函数，不能返回 Future（否则触发
      // "setState() callback argument returned a Future" 断言）。
      _conflicts = store.pendingConflictPaths();
    });
  }

  Future<void> _resolve(String path, ConflictResolution r) async {
    final store = context.read<AppStore>();
    await store.resolveConflict(path, r);
    if (!mounted) return;
    setState(() {
      _conflicts = store.pendingConflictPaths();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r == ConflictResolution.local
            ? '已保留本地版本'
            : '已采用远程版本')));
  }

  /// 导出完整备份：流式生成 zip 到临时目录后走系统分享面板。
  /// 分享后不自动删除（Android 分享面板关闭前接收方可能仍在读流），
  /// 而是刷新下方「历史备份」列表，由用户按需删除 / 一键清空。
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
      await _loadBackups(); // 新备份出现在下方列表，便于管理
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// 扫描临时目录下的历史备份 zip（my-diary-full-*.zip），新→旧。
  Future<void> _loadBackups() async {
    try {
      final tmp = await getTemporaryDirectory();
      final files = <({String path, String name, int size, DateTime modified})>[];
      await for (final e in tmp.list(followLinks: false)) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        if (!name.startsWith('my-diary-full-') || !name.endsWith('.zip')) continue;
        try {
          final st = await e.stat();
          files.add((
            path: e.path,
            name: name,
            size: st.size,
            modified: st.modified,
          ));
        } catch (_) {/* 忽略无法读取的文件 */}
      }
      files.sort((a, b) => b.modified.compareTo(a.modified));
      if (!mounted) return;
      setState(() => _backups = files);
    } catch (_) {
      if (mounted) setState(() => _backups = []);
    }
  }

  /// 删除单份备份（带确认）。
  Future<void> _deleteBackup(String path) async {
    final ok = await _confirm(
      title: '删除备份',
      message: '确定删除这份备份文件吗？',
      confirmLabel: '删除',
    );
    if (ok != true || !mounted) return;
    try {
      await File(path).delete();
    } catch (_) {/* 已不存在等 */}
    await _loadBackups();
  }

  /// 清空全部历史备份（带确认）。
  Future<void> _clearAllBackups() async {
    final ok = await _confirm(
      title: '清空全部历史备份',
      message: '将删除全部 ${_backups.length} 份本地备份文件，确定吗？',
      confirmLabel: '清空',
    );
    if (ok != true || !mounted) return;
    for (final b in _backups) {
      try {
        await File(b.path).delete();
      } catch (_) {}
    }
    await _loadBackups();
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      );

  String _sizeText(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final t = context.tokens;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle('外观'),
          _Card(
            children: [
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
                selected: {_theme},
                onSelectionChanged: (s) =>
                    setState(() => _theme = s.first),
              ),
              const SizedBox(height: 18),
              const Text('品牌色',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                children: AccentKey.values
                    .map((a) => ChoiceChip(
                          label: Text(accentLabels[a]!),
                          selected: _accent == a,
                          avatar: CircleAvatar(
                            backgroundColor: accentSeeds[a],
                            radius: 8,
                          ),
                          onSelected: (_) => setState(() => _accent = a),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 18),
              const Text('字体',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              SegmentedButton<FontKey>(
                segments: const [
                  ButtonSegment(
                      value: FontKey.sans, label: Text('无衬线')),
                  ButtonSegment(
                      value: FontKey.serif, label: Text('衬线')),
                ],
                selected: {_font},
                onSelectionChanged: (s) => setState(() => _font = s.first),
              ),
              const SizedBox(height: 18),
              const Text('默认心情',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text('新建日记时自动采用',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                children: Mood.ordered
                    .map((m) => ChoiceChip(
                          label: Text('${m.iconChar} ${m.label}',
                              style: const TextStyle(
                                  fontFamily: 'moodfont')),
                          selected: _defaultMood == m,
                          onSelected: (_) =>
                              setState(() => _defaultMood = m),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _displayNameCtl,
                decoration: const InputDecoration(labelText: '昵称'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: _weekStartsOn,
                decoration:
                    const InputDecoration(labelText: '每周起始日'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('周日')),
                  DropdownMenuItem(value: 1, child: Text('周一')),
                ],
                onChanged: (v) => setState(() => _weekStartsOn = v!),
              ),
            ],
          ),
          _SectionTitle('日记'),
          _Card(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('新建日记自动定位'),
                subtitle: const Text('创建新日记时自动获取位置与天气并填充（需已配置地图与天气 Key）'),
                value: _autoLocateNew,
                onChanged: (v) => setState(() => _autoLocateNew = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('预览页显示地图'),
                subtitle: const Text('日记预览页（详情）底部展示位置地图块'),
                value: _showDetailMap,
                onChanged: (v) => setState(() => _showDetailMap = v),
              ),
            ],
          ),
          _SectionTitle('媒体'),
          _Card(
            children: [
              const Text('图片上传压缩',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('导入图片时按此质量重压缩（上限 2000px 长边）并生成列表缩略图。',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _imageQuality.toDouble(),
                      min: 1,
                      max: 100,
                      divisions: 99,
                      label: '$_imageQuality',
                      onChanged: (v) =>
                          setState(() => _imageQuality = v.round()),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text('$_imageQuality',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('视频上传压缩',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('导入视频时按此质量压缩（100 为不压缩）并抽取封面帧。',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _videoQuality.toDouble(),
                      min: 1,
                      max: 100,
                      divisions: 99,
                      label: '$_videoQuality',
                      onChanged: (v) =>
                          setState(() => _videoQuality = v.round()),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text('$_videoQuality',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text('两项均只影响之后导入的素材，已存在的图片/视频不会被重新处理。',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          _SectionTitle('同步'),
          _Card(
            children: [
              DropdownButtonFormField<SyncProvider>(
                value: _provider,
                decoration:
                    const InputDecoration(labelText: '同步方式'),
                items: const [
                  DropdownMenuItem(
                      value: SyncProvider.none, child: Text('不使用同步')),
                  DropdownMenuItem(
                      value: SyncProvider.s3, child: Text('AWS S3')),
                  DropdownMenuItem(
                      value: SyncProvider.r2, child: Text('Cloudflare R2')),
                  DropdownMenuItem(
                      value: SyncProvider.minio, child: Text('MinIO')),
                  DropdownMenuItem(
                      value: SyncProvider.oss, child: Text('阿里云 OSS')),
                ],
                onChanged: (v) => setState(() => _provider = v!),
              ),
              if (_isDirect(_provider)) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _endpointCtl,
                  decoration: const InputDecoration(
                    hintText: 'https://s3.us-east-1.amazonaws.com',
                    labelText: 'Endpoint',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _bucketCtl,
                  decoration:
                      const InputDecoration(labelText: 'Bucket'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _regionCtl,
                  decoration: const InputDecoration(
                    labelText: 'Region',
                    hintText: 'MinIO 留空即可；OSS 留空则按 Endpoint 自动推导',
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Path-style 寻址'),
                  subtitle: const Text('MinIO / R2 / OSS 开启；AWS S3 关闭'),
                  value: _pathStyle,
                  onChanged: (v) => setState(() => _pathStyle = v),
                ),
                TextField(
                  controller: _accessKeyCtl,
                  decoration: const InputDecoration(
                    labelText: 'Access Key（留空则不修改）',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _secretKeyCtl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Secret Key（留空则不修改）',
                  ),
                ),
                const SizedBox(height: 14),
                const Text('自动同步',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const Text('开启后按所选间隔后台定期同步（编辑日记后会立即触发一次）',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  value: _autoSyncMinutes,
                  decoration:
                      const InputDecoration(labelText: '同步间隔'),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('关闭（仅手动同步）')),
                    DropdownMenuItem(value: 5, child: Text('每 5 分钟')),
                    DropdownMenuItem(value: 15, child: Text('每 15 分钟')),
                    DropdownMenuItem(value: 30, child: Text('每 30 分钟')),
                    DropdownMenuItem(value: 60, child: Text('每 60 分钟')),
                  ],
                  onChanged: (v) => setState(() => _autoSyncMinutes = v!),
                ),
              ],
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 14),
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
                Text(
                    '上次同步：${DateFormat('MM-dd HH:mm').format(store.lastSyncAt!.toLocal())}',
                    style: context.caption),
              ],
              if (store.syncEnabled &&
                  store.settings.sync.autoSyncIntervalMinutes > 0) ...[
                const SizedBox(height: 4),
                Text(
                    '自动同步：每 ${store.settings.sync.autoSyncIntervalMinutes} 分钟',
                    style: context.caption.copyWith(
                        color: Theme.of(context).colorScheme.primary)),
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
                      Text('待解决冲突', style: context.titleMedium),
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
                                      onPressed: () => _resolve(
                                          p, ConflictResolution.local),
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
            ],
          ),
          _SectionTitle('数据与备份'),
          _Card(
            children: [
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
              // 历史备份列表：导出后留在临时目录的 zip 在此列出，可单独删除或一键清空。
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _backups.isEmpty
                            ? '历史备份'
                            : '历史备份（${_backups.length}，共 ${_sizeText(_backups.fold<int>(0, (s, b) => s + b.size))}）',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (_backups.isNotEmpty)
                      TextButton(
                        onPressed: _clearAllBackups,
                        child: const Text('清空全部'),
                      ),
                  ],
                ),
              ),
              if (_backups.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    '暂无本地备份文件',
                    style: TextStyle(fontSize: 12, color: t.textTertiary),
                  ),
                )
              else
                for (final b in _backups)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.archive_outlined, size: 20),
                    title: Text(b.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                      '${_sizeText(b.size)} · '
                      '${DateFormat('yyyy-MM-dd HH:mm').format(b.modified.toLocal())}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      tooltip: '删除此备份',
                      onPressed: () => _deleteBackup(b.path),
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// 分区标题：小号加粗 caption，作为卡片之间的分组标记。
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Text(text,
            style: context.caption.copyWith(
                fontSize: 13, fontWeight: FontWeight.w700)),
      );
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
