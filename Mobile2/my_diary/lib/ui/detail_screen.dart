import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_diary_mobile/editor/doc_view.dart';
import 'package:my_diary_mobile/editor/markdown_doc.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(context.tokens.radiusSheet)),
      ),
      builder: (c) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('版本历史', style: context.titleMedium),
            const SizedBox(height: 8),
            if (versions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('暂无历史版本'),
              ),
            for (final item in versions)
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(DateFormat('yyyy-MM-dd HH:mm')
                    .format(DateTime.parse(item.entry.updatedAt).toLocal())),
                subtitle: Text(
                    '${item.entry.title} · ${item.entry.body.length} 字'),
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
                  final restored =
                      await store.repo.restoreVersion(_entry, item.version);
                  if (!mounted) return;
                  setState(() => _entry = restored);
                  if (c.mounted) Navigator.pop(c);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final e = _entry;
    // 正文按块渲染：图片 / 音视频 / 附件都在写作时所处的位置就地呈现，
    // 因此不再单独堆一层封面图和缩略图条（否则同一张图会出现两次）。
    final blocks = decodeEntryBody(e.body, e.assets);

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
        padding: const EdgeInsets.only(top: 8),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metaChip('${e.mood.emoji} ${e.mood.label}'),
                _metaChip('${e.weather.emoji} ${e.weather.label}'),
                if (e.location != null && e.location!.isNotEmpty)
                  _metaChip('📍 ${e.location}'),
              ],
            ),
          ),
          if (e.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: e.tags
                    .map((tag) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: t.fill,
                            borderRadius:
                                BorderRadius.circular(t.radiusChip),
                          ),
                          child: Text('#$tag',
                              style: TextStyle(
                                  fontSize: 12, color: t.textSecondary)),
                        ))
                    .toList(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: DocView(blocks: blocks, emptyHint: '这一天还没有内容'),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: context.tokens.fill,
          borderRadius:
              BorderRadius.circular(context.tokens.radiusChip),
        ),
        child: Text(text,
            style:
                TextStyle(fontSize: 13, color: context.tokens.textSecondary)),
      );
}
