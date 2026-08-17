import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:provider/provider.dart';

class EditorScreen extends StatefulWidget {
  final JournalEntry entry;
  const EditorScreen({super.key, required this.entry});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late TextEditingController _titleCtl;
  late TextEditingController _bodyCtl;
  late TextEditingController _locationCtl;
  late TextEditingController _tagInputCtl;

  late Mood _mood;
  late Weather _weather;
  late String _date;
  late List<String> _tags;
  late List<AssetRef> _assets;

  final _picker = ImagePicker();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _titleCtl = TextEditingController(text: e.title);
    _bodyCtl = TextEditingController(text: e.body);
    _locationCtl = TextEditingController(text: e.location ?? '');
    _tagInputCtl = TextEditingController();
    _mood = e.mood;
    _weather = e.weather;
    _date = e.date;
    _tags = List.from(e.tags);
    _assets = List.from(e.assets);
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _bodyCtl.dispose();
    _locationCtl.dispose();
    _tagInputCtl.dispose();
    super.dispose();
  }

  JournalEntry _buildDraft() => widget.entry.copyWith(
        title: _titleCtl.text,
        body: _bodyCtl.text,
        location: _locationCtl.text.trim(),
        clearLocation: _locationCtl.text.trim().isEmpty,
        mood: _mood,
        weather: _weather,
        date: _date,
        tags: _tags,
        assets: _assets,
      );

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final store = context.read<AppStore>();
    await store.saveEntry(_buildDraft());
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final store = context.read<AppStore>();
    final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('删除这篇日记？'),
            content: const Text('此操作不可撤销。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('删除')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await store.deleteEntry(widget.entry.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickImage() async {
    final x = await _picker.pickImage(source: ImageSource.gallery);
    if (x == null) return;
    final store = context.read<AppStore>();
    final ref = await store.importImage(File(x.path), name: x.name);
    setState(() => _assets.add(ref));
  }

  Future<void> _pickDate() async {
    final initial = DateFormat('yyyy-MM-dd').parse(_date);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _date = DateFormat('yyyy-MM-dd').format(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.entry.title.isEmpty &&
        widget.entry.body.isEmpty &&
        widget.entry.createdAt == widget.entry.updatedAt;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? '新日记' : '编辑'),
        actions: [
          if (!isNew)
            IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '删除',
                onPressed: _delete),
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 日期 + 地点
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(_date),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _locationCtl,
                  decoration:
                      const InputDecoration(hintText: '地点（可选）'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleCtl,
            decoration: const InputDecoration(
              hintText: '标题',
              border: InputBorder.none,
            ),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const Divider(),
          const SizedBox(height: 8),
          // 心情
          _SelectorLabel('心情'),
          _ChipRow<Mood>(
            values: Mood.ordered,
            selected: _mood,
            labelOf: (m) => '${m.emoji} ${m.label}',
            onSelect: (m) => setState(() => _mood = m),
          ),
          const SizedBox(height: 10),
          // 天气
          _SelectorLabel('天气'),
          _ChipRow<Weather>(
            values: Weather.ordered,
            selected: _weather,
            labelOf: (w) => '${w.emoji} ${w.label}',
            onSelect: (w) => setState(() => _weather = w),
          ),
          const SizedBox(height: 14),
          // 标签
          _SelectorLabel('标签'),
          Wrap(
            spacing: 6,
            children: [
              ..._tags.map((t) => Chip(
                    label: Text('#$t'),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => setState(() => _tags.remove(t)),
                  )),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _tagInputCtl,
                  decoration: const InputDecoration(
                    hintText: '添加',
                    isDense: true,
                    border: InputBorder.none,
                  ),
                  onSubmitted: (v) {
                    final t = v.trim();
                    if (t.isNotEmpty && !_tags.contains(t)) {
                      setState(() => _tags.add(t));
                    }
                    _tagInputCtl.clear();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 附件
          _SelectorLabel('图片'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._assets.where((a) => a.kind == AssetKind.image).map((a) {
                final file = context.read<AppStore>().resolveAsset(a.path);
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(file,
                          width: 84, height: 84, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: IconButton(
                        icon: const Icon(Icons.remove_circle, size: 18),
                        color: Colors.red,
                        onPressed: () =>
                            setState(() => _assets.remove(a)),
                      ),
                    ),
                  ],
                );
              }),
              InkWell(
                onTap: _pickImage,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: Theme.of(context).hintColor.withOpacity(0.4)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.add_a_photo_outlined),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 正文
          _SelectorLabel('正文（Markdown）'),
          TextField(
            controller: _bodyCtl,
            maxLines: null,
            minLines: 10,
            decoration: const InputDecoration(
              hintText: '今天发生了什么？',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SelectorLabel extends StatelessWidget {
  final String text;
  const _SelectorLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).hintColor)),
      );
}

class _ChipRow<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final void Function(T) onSelect;
  const _ChipRow({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: values
              .map((v) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(labelOf(v)),
                      selected: v == selected,
                      onSelected: (_) => onSelect(v),
                    ),
                  ))
              .toList(),
        ),
      );
}
