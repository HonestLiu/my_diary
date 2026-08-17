import 'package:flutter/material.dart';
import 'package:my_diary_mobile/models/sync_types.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:provider/provider.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  Future<List<String>>? _conflictsFuture;

  @override
  void initState() {
    super.initState();
    _loadConflicts();
  }

  void _loadConflicts() {
    _conflictsFuture = context.read<AppStore>().pendingConflictPaths();
    setState(() {});
  }

  Future<void> _sync() async {
    final store = context.read<AppStore>();
    await store.syncNow();
    _loadConflicts();
  }

  Future<void> _resolve(String path, ConflictResolution r) async {
    final store = context.read<AppStore>();
    await store.resolveConflict(path, r);
    _loadConflicts();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(r == ConflictResolution.local
                ? '已保留本地版本'
                : '已采用远程版本')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final last = store.lastSync;
    final sync = store.settings.sync;

    return Scaffold(
      appBar: AppBar(title: const Text('同步')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(sync.enabled
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_off_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          sync.enabled
                              ? '同步已启用 · ${_providerLabel(sync.provider)}'
                              : '同步未启用',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: store.busy ? null : _sync,
                    icon: store.busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.sync),
                    label: Text(store.busy ? '同步中…' : '立即同步'),
                  ),
                  if (store.lastSyncAt != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      '上次同步：${store.lastSyncAt!.toLocal()}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (last != null) ...[
            _ResultTile(
              icon: Icons.upload_outlined,
              label: '已上传',
              count: last.uploaded.length,
            ),
            _ResultTile(
              icon: Icons.download_outlined,
              label: '已下载',
              count: last.downloaded.length,
            ),
            _ResultTile(
              icon: Icons.warning_amber_rounded,
              label: '冲突',
              count: last.conflicts.length,
              danger: last.conflicts.isNotEmpty,
            ),
            if (last.errors.isNotEmpty)
              _ResultTile(
                icon: Icons.error_outline,
                label: '错误',
                count: last.errors.length,
                danger: true,
              ),
          ],
          const SizedBox(height: 20),
          const Text('待解决冲突',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          FutureBuilder<List<String>>(
            future: _conflictsFuture,
            builder: (c, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final conflicts = snap.data!;
              if (conflicts.isEmpty) {
                return const Card(
                  child: ListTile(
                    leading: Icon(Icons.check_circle_outline,
                        color: Colors.green),
                    title: Text('没有冲突，一切同步正常'),
                  ),
                );
              }
              return Column(
                children: conflicts
                    .map((p) => Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
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
                        ))
                    .toList(),
              );
            },
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

class _ResultTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final bool danger;
  const _ResultTile({
    required this.icon,
    required this.label,
    required this.count,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: danger ? Colors.orange : null),
        title: Text(label),
        trailing: Chip(
          label: Text('$count'),
          backgroundColor: danger ? Colors.orange.shade100 : null,
        ),
      );
}
