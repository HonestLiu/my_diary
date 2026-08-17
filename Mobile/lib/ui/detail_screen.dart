import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/editor_screen.dart';
import 'package:provider/provider.dart';

class DetailScreen extends StatefulWidget {
  final JournalEntry entry;
  const DetailScreen({super.key, required this.entry});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late JournalEntry _entry;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
  }

  void _edit() async {
    final updated = await Navigator.push<JournalEntry?>(
      context,
      MaterialPageRoute(builder: (_) => EditorScreen(entry: _entry)),
    );
    if (updated != null) setState(() => _entry = updated);
  }

  void _showVersions() async {
    final store = context.read<AppStore>();
    final versions = await store.entryVersions(_entry);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (c) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const ListTile(title: Text('版本历史', style: TextStyle(fontWeight: FontWeight.w700))),
          if (versions.isEmpty)
            const ListTile(title: Text('暂无历史版本')),
          for (final item in versions)
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(DateFormat('yyyy-MM-dd HH:mm')
                  .format(DateTime.parse(item.entry.updatedAt).toLocal())),
              subtitle: Text('${item.entry.title} · ${item.entry.body.length} 字'),
              trailing: const Icon(Icons.restore),
              onTap: () async {
                final ok = await showDialog<bool>(
                      context: c,
                      builder: (d) => AlertDialog(
                        title: const Text('恢复到此版本？'),
                        content: const Text('当前内容会先被存档，可再次恢复。'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(d, false),
                              child: const Text('取消')),
                          FilledButton(
                              onPressed: () => Navigator.pop(d, true),
                              child: const Text('恢复')),
                        ],
                      ),
                    ) ??
                    false;
                if (!ok) return;
                final restored = await store.repo.restoreVersion(_entry, item.version);
                if (mounted) {
                  setState(() => _entry = restored);
                  Navigator.pop(c);
                }
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = _entry;
    final images =
        e.assets.where((a) => a.kind == AssetKind.image).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(e.displayTitle, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
              icon: const Icon(Icons.history),
              tooltip: '版本历史',
              onPressed: _showVersions),
          IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑',
              onPressed: _edit),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('${e.mood.emoji} ${e.mood.label}')),
              Chip(label: Text('${e.weather.emoji} ${e.weather.label}')),
              if (e.location != null && e.location!.isNotEmpty)
                Chip(label: Text('📍 ${e.location}')),
            ],
          ),
          if (e.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                children: e.tags
                    .map((t) => Chip(label: Text('#$t')))
                    .toList(),
              ),
            ),
          if (images.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                height: 160,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: images.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final file =
                        context.read<AppStore>().resolveAsset(images[i].path);
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(file, fit: BoxFit.cover),
                    );
                  },
                ),
              ),
            ),
          const Divider(),
          MarkdownBody(
            data: e.body.isEmpty ? '_（暂无内容）_' : e.body,
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                .copyWith(
              p: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
