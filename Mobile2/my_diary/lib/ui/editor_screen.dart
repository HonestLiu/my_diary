import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:my_diary_mobile/config/map_config.dart';
import 'package:my_diary_mobile/config/weather_config.dart';
import 'package:my_diary_mobile/editor/doc_model.dart';
import 'package:my_diary_mobile/editor/inline_style.dart';
import 'package:my_diary_mobile/editor/markdown_doc.dart';
import 'package:my_diary_mobile/editor/media_card.dart';
import 'package:my_diary_mobile/editor/rich_text_controller.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/services/locator_data.dart';
import 'package:my_diary_mobile/services/locator_service.dart';
import 'package:my_diary_mobile/services/weather_service.dart';
import 'package:my_diary_mobile/ui/app_store.dart';
import 'package:my_diary_mobile/ui/map_picker_page.dart';
import 'package:my_diary_mobile/ui/app_theme.dart';
import 'package:provider/provider.dart';

/// 所见即所得编辑器。
///
/// 设计约束（用户明确要求）：
/// 1. 编辑区**不出现任何 Markdown 源码** —— 富文本以样式呈现，符号只存在于落盘文件里；
/// 2. 一切操作集中在**底部工具栏**：段落样式、行内格式、插入图片/音频/视频/文件、
///    以及心情 / 天气 / 日期 / 地点 / 标签等属性；
/// 3. 底层文件仍是标准 Markdown（见 `editor/markdown_doc.dart`），与桌面端互通。
class EditorScreen extends StatefulWidget {
  final JournalEntry entry;
  const EditorScreen({super.key, required this.entry});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

enum _Panel { none, style, insert, props }

class _EditorScreenState extends State<EditorScreen> {
  late final TextEditingController _titleCtl;
  late final TextEditingController _locationCtl;
  final TextEditingController _tagCtl = TextEditingController();

  late Mood _mood;
  late Weather _weather;
  late String _date;
  late List<String> _tags;
  double? _latitude;
  double? _longitude;
  bool _locatingLocation = false; // 一键定位进行中

  final List<DocBlock> _blocks = <DocBlock>[];
  final Map<String, RichTextController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};
  final List<RichTextController> _retiredControllers = [];
  final List<FocusNode> _retiredNodes = [];

  String? _focusedId;
  _Panel _panel = _Panel.none;
  bool _saving = false;
  bool _dirty = false;

  final ImagePicker _picker = ImagePicker();
  final ScrollController _scrollCtl = ScrollController();

  bool get _isNew =>
      widget.entry.title.isEmpty &&
      widget.entry.body.isEmpty &&
      widget.entry.createdAt == widget.entry.updatedAt;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _titleCtl = TextEditingController(text: e.title);
    _locationCtl = TextEditingController(text: e.location ?? '');
    _mood = e.mood;
    _weather = e.weather;
    _date = e.date;
    _tags = List.of(e.tags);
    _latitude = e.latitude;
    _longitude = e.longitude;
    _blocks.addAll(decodeEntryBody(e.body, e.assets));
    _ensureTrailingText();
    _titleCtl.addListener(_markDirty);
    _locationCtl.addListener(_markDirty);
    // 设置项：新建日记自动定位填充位置与天气（静默，不打扰）。
    if (_isNew && context.read<AppStore>().settings.autoLocateNew) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _autoLocateCurrentLocation();
      });
    }
  }

  /// 静默版一键定位：自动填充位置与天气，不弹 SnackBar（用于新建日记自动定位）。
  Future<void> _autoLocateCurrentLocation() async {
    if (!MapConfig.isConfigured) return;
    final locatorData = context.read<LocatorData>();
    final locator = context.read<LocatorService>();
    await locator.getUserAddress();
    if (!mounted) return;
    setState(() {
      final p = locatorData.currentPosition;
      if (p != null) {
        _latitude = p.latitude;
        _longitude = p.longitude;
      }
      final addr = locatorData.userAddress;
      if (addr != null && addr.isNotEmpty) {
        _locationCtl.text = addr;
      }
    });
    final p = locatorData.currentPosition;
    if (p != null && _weather == Weather.unknown) {
      await _fetchWeatherForPosition();
    }
    _markDirty();
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _locationCtl.dispose();
    _tagCtl.dispose();
    _scrollCtl.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final c in _retiredControllers) {
      c.dispose();
    }
    for (final n in _focusNodes.values) {
      n.dispose();
    }
    for (final n in _retiredNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) _dirty = true;
  }

  // -------------------------------------------------------------------------
  // 块 / 控制器 生命周期
  // -------------------------------------------------------------------------

  void _ensureTrailingText() {
    if (_blocks.isEmpty || !_blocks.last.kind.isText) {
      _blocks.add(DocBlock.paragraph());
    }
  }

  RichTextController _controllerFor(DocBlock b) {
    final existing = _controllers[b.id];
    if (existing != null) return existing;
    final ctl = RichTextController(text: b.text, marks: b.marks);
    ctl.onDocChanged = (text, marks) {
      _onBlockChanged(b, text, marks);
    };
    ctl.onMergeBackward = () {
      // 合并要改动 _blocks / 控制器集合，不能在 value setter 里同步执行。
      scheduleMicrotask(() => _mergeBackward(b));
    };
    ctl.addListener(_onCaretTick);
    _controllers[b.id] = ctl;
    return ctl;
  }

  FocusNode _focusNodeFor(DocBlock b) {
    final existing = _focusNodes[b.id];
    if (existing != null) return existing;
    final node = FocusNode();
    node.addListener(() {
      if (!mounted) return;
      if (node.hasFocus) setState(() => _focusedId = b.id);
    });
    _focusNodes[b.id] = node;
    return node;
  }

  void _retire(DocBlock b) {
    final ctl = _controllers.remove(b.id);
    if (ctl != null) {
      ctl
        ..onDocChanged = null
        ..onMergeBackward = null
        ..removeListener(_onCaretTick);
      _retiredControllers.add(ctl);
    }
    final node = _focusNodes.remove(b.id);
    if (node != null) _retiredNodes.add(node);
  }

  void _onCaretTick() {
    if (mounted) setState(() {});
  }

  void _onBlockChanged(DocBlock b, String text, List<InlineMark> marks) {
    b.text = text;
    b.marks = marks;
    _dirty = true;
    if (mounted) setState(() {});
  }

  DocBlock? get _focusedBlock {
    final id = _focusedId;
    if (id != null) {
      for (final b in _blocks) {
        if (b.id == id && b.kind.isText) return b;
      }
    }
    for (final b in _blocks.reversed) {
      if (b.kind.isText) return b;
    }
    return null;
  }

  Set<MarkKind> get _activeMarks {
    final b = _focusedBlock;
    if (b == null) return const <MarkKind>{};
    final ctl = _controllers[b.id];
    return ctl?.activeMarks ?? const <MarkKind>{};
  }

  // -------------------------------------------------------------------------
  // 回车 / 退格：块的拆分与合并
  // -------------------------------------------------------------------------

  /// 拦截换行：编辑区不允许出现裸 `\n`（代码块除外），一律转成「拆分成新块」。
  TextInputFormatter _lineBreakFormatter(DocBlock b) =>
      TextInputFormatter.withFunction((oldValue, newValue) {
        if (!newValue.text.contains('\n')) return newValue;
        String plain(String s) => s.startsWith(RichTextController.sentinel)
            ? s.substring(1)
            : s;
        final oldPlain = plain(oldValue.text);
        final newPlain = plain(newValue.text);
        final diff = computeTextDiff(oldPlain, newPlain);
        final inserted =
            newPlain.substring(diff.at, diff.at + diff.inserted);
        scheduleMicrotask(
            () => _applyLineBreak(b, diff.at, diff.removed, inserted));
        return oldValue;
      });

  BlockKind _continuationKind(BlockKind kind) {
    if (kind.isList) return kind;
    if (kind == BlockKind.quote) return BlockKind.quote;
    return BlockKind.paragraph;
  }

  void _applyLineBreak(DocBlock b, int at, int removed, String inserted) {
    final index = _blocks.indexOf(b);
    if (index < 0) return;
    final ctl = _controllerFor(b);
    final text = ctl.plainText;
    final start = at.clamp(0, text.length);
    final end = (at + removed).clamp(start, text.length);
    final head = text.substring(0, start);
    final tail = text.substring(end);
    final parts = inserted.split('\n');

    // 在空的列表项 / 引用 / 标题上回车 —— 退出该样式，而不是再造一个空块
    final plainEnter = parts.length == 2 && inserted == '\n';
    if (plainEnter &&
        head.isEmpty &&
        tail.isEmpty &&
        b.kind != BlockKind.paragraph) {
      setState(() {
        b.kind = BlockKind.paragraph;
        b.checked = false;
        b.language = null;
        _dirty = true;
      });
      return;
    }

    final split = splitMarks(ctl.marks, start, dropLength: end - start);
    final firstText = head + parts.first;
    final lastText = parts.last + tail;
    final middle =
        parts.length > 2 ? parts.sublist(1, parts.length - 1) : const <String>[];
    final continuation = _continuationKind(b.kind);

    final created = <DocBlock>[
      for (final line in middle) DocBlock(kind: continuation, text: line),
      DocBlock(
        kind: continuation,
        text: lastText,
        marks: normalizeMarks(
            shiftMarksBy(split.tail, parts.last.length), lastText.length),
      ),
    ];

    setState(() {
      b.text = firstText;
      b.marks = normalizeMarks(split.head, firstText.length);
      _blocks.insertAll(index + 1, created);
      _dirty = true;
    });
    ctl.setDoc(b.text, b.marks, caret: firstText.length);

    final target = created.last;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controllerFor(target).setPlainCaret(0);
      _focusNodeFor(target).requestFocus();
    });
  }

  void _mergeBackward(DocBlock b) {
    if (!mounted) return;
    final index = _blocks.indexOf(b);
    if (index < 0) return;

    // 首次退格先退化样式（列表 → 正文），符合主流编辑器直觉
    if (b.kind != BlockKind.paragraph) {
      setState(() {
        b.kind = BlockKind.paragraph;
        b.checked = false;
        b.language = null;
        _dirty = true;
      });
      return;
    }
    if (index == 0) return;

    final prev = _blocks[index - 1];
    if (!prev.kind.isText) {
      setState(() {
        _blocks.removeAt(index - 1);
        _retire(prev);
        _dirty = true;
      });
      return;
    }

    final prevCtl = _controllerFor(prev);
    final prevText = prevCtl.plainText;
    final merged = prevText + b.text;
    final mergedMarks = normalizeMarks(
      [...prevCtl.marks, ...shiftMarksBy(b.marks, prevText.length)],
      merged.length,
    );
    setState(() {
      prev.text = merged;
      prev.marks = mergedMarks;
      _blocks.removeAt(index);
      _retire(b);
      _ensureTrailingText();
      _dirty = true;
    });
    prevCtl.setDoc(merged, mergedMarks, caret: prevText.length);
    _focusNodeFor(prev).requestFocus();
  }

  // -------------------------------------------------------------------------
  // 工具栏动作
  // -------------------------------------------------------------------------

  void _togglePanel(_Panel panel) {
    setState(() => _panel = _panel == panel ? _Panel.none : panel);
  }

  /// 折叠当前底部面板（点击编辑区时自动调用，覆盖属性 / 段落样式 / 插入）。
  void _collapsePanel() {
    if (_panel != _Panel.none) setState(() => _panel = _Panel.none);
  }

  void _toggleMark(MarkKind kind) {
    final b = _focusedBlock;
    if (b == null) return;
    _controllerFor(b).toggleMark(kind);
  }

  void _setBlockKind(BlockKind kind) {
    final b = _focusedBlock;
    if (b == null) return;
    setState(() {
      b.kind = kind;
      if (kind != BlockKind.todo) b.checked = false;
      if (kind != BlockKind.code) b.language = null;
      _dirty = true;
    });
    _focusNodeFor(b).requestFocus();
  }

  void _toggleTodo(DocBlock b) {
    setState(() {
      b.checked = !b.checked;
      _dirty = true;
    });
  }

  void _removeBlock(DocBlock b) {
    setState(() {
      _blocks.remove(b);
      _retire(b);
      _ensureTrailingText();
      _dirty = true;
    });
  }

  /// 在光标所在块之后插入一个非文本块（媒体 / 分割线），并保证其后有可继续输入的段落。
  void _insertBlockAfterCursor(DocBlock block) {
    final anchor = _focusedBlock;
    DocBlock? follow;
    setState(() {
      if (anchor != null &&
          anchor.kind == BlockKind.paragraph &&
          anchor.text.isEmpty) {
        final i = _blocks.indexOf(anchor);
        _blocks[i] = block;
        _retire(anchor);
      } else {
        final i = anchor == null ? _blocks.length - 1 : _blocks.indexOf(anchor);
        _blocks.insert(i + 1, block);
      }
      final idx = _blocks.indexOf(block);
      if (idx == _blocks.length - 1 || !_blocks[idx + 1].kind.isText) {
        follow = DocBlock.paragraph();
        _blocks.insert(idx + 1, follow!);
      } else {
        follow = _blocks[idx + 1];
      }
      _dirty = true;
      _panel = _Panel.none;
    });
    final target = follow;
    if (target == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controllerFor(target).setPlainCaret(0);
      _focusNodeFor(target).requestFocus();
    });
  }

  Future<void> _importAndInsert(
    Future<File?> Function() pick,
    AssetKind kind, {
    String? Function()? nameOf,
  }) async {
    final store = context.read<AppStore>();
    try {
      final file = await pick();
      if (file == null) return;
      final ref = await store.importAsset(file, kind, name: nameOf?.call());
      _insertBlockAfterCursor(DocBlock.media(MediaPayload.fromAssetRef(ref)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    String? name;
    await _importAndInsert(
      () async {
        final x = await _picker.pickImage(source: source, imageQuality: 92);
        if (x == null) return null;
        name = x.name;
        return File(x.path);
      },
      AssetKind.image,
      nameOf: () => name,
    );
  }

  Future<void> _pickVideo() async {
    String? name;
    await _importAndInsert(
      () async {
        final x = await _picker.pickVideo(source: ImageSource.gallery);
        if (x == null) return null;
        name = x.name;
        return File(x.path);
      },
      AssetKind.video,
      nameOf: () => name,
    );
  }

  Future<void> _pickFile(AssetKind kind) async {
    String? name;
    await _importAndInsert(
      () async {
        final res = await FilePicker.platform.pickFiles(
          type: switch (kind) {
            AssetKind.audio => FileType.audio,
            AssetKind.video => FileType.video,
            _ => FileType.any,
          },
        );
        final picked = res?.files.singleOrNull;
        final path = picked?.path;
        if (path == null) return null;
        name = picked?.name;
        return File(path);
      },
      kind,
      nameOf: () => name,
    );
  }

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(_date) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _date = DateFormat('yyyy-MM-dd').format(picked);
        _dirty = true;
      });
    }
  }

  void _addTag(String raw) {
    final tag = raw.trim().replaceAll(RegExp(r'^#+'), '').trim();
    if (tag.isEmpty || _tags.contains(tag)) {
      _tagCtl.clear();
      return;
    }
    setState(() {
      _tags.add(tag);
      _dirty = true;
    });
    _tagCtl.clear();
  }

  // -------------------------------------------------------------------------
  // 保存 / 删除 / 返回
  // -------------------------------------------------------------------------

  JournalEntry _buildDraft() {
    final loc = _locationCtl.text.trim();
    return widget.entry.copyWith(
      title: _titleCtl.text.trim(),
      body: encodeMarkdown(_blocks),
      assets: collectAssets(_blocks),
      location: loc,
      clearLocation: loc.isEmpty,
      mood: _mood,
      weather: _weather,
      date: _date,
      tags: _tags,
      latitude: _latitude,
      longitude: _longitude,
    );
  }

  /// 打开地图选点页，回写经纬度与地点名称。
  Future<void> _pickLocation() async {
    final result = await Navigator.push<Map<String, dynamic>?>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerPage(
          initialLat: _latitude,
          initialLon: _longitude,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      _latitude = result['lat'] as double?;
      _longitude = result['lon'] as double?;
      final name = (result['name'] as String? ?? '').trim();
      if (name.isNotEmpty) _locationCtl.text = name;
      _markDirty();
    });
  }

  /// 一键定位：GPS 获取当前位置 + 天地图逆地理编码回填地点名称，
  /// 同时记录经纬度（保存后即出现在「足迹」地图上）并联动查询天气填充天气栏。
  Future<void> _locateCurrentLocation() async {
    if (!MapConfig.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('未配置天地图 Key，无法解析地址\n请在 lib/config/map_config.dart 中填写')),
      );
      return;
    }
    final locatorData = context.read<LocatorData>();
    final locator = context.read<LocatorService>();
    setState(() => _locatingLocation = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在获取当前位置…')),
    );
    await locator.getUserAddress();
    if (!mounted) return;
    setState(() {
      _locatingLocation = false;
      final p = locatorData.currentPosition;
      if (p != null) {
        _latitude = p.latitude;
        _longitude = p.longitude;
      }
      final addr = locatorData.userAddress;
      if (addr != null && addr.isNotEmpty) {
        _locationCtl.text = addr;
      }
    });
    final p = locatorData.currentPosition;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        p != null
            ? '已获取位置：${locatorData.userAddress ?? '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}'}'
            : (locatorData.status ?? '定位失败'),
      ),
    ));
    // 定位同时查天气：仅当天气尚未设置（如新建日记）时自动填充。
    if (p != null && _weather == Weather.unknown) {
      await _fetchWeatherForPosition();
    }
    _markDirty();
  }

  /// 用当前位置拉取心知天气，并把结果填充到天气栏（仅在未设置天气时调用）。
  Future<void> _fetchWeatherForPosition() async {
    if (!WeatherConfig.isConfigured) return;
    final p = context.read<LocatorData>().currentPosition;
    if (p == null) return;
    final loc =
        '${p.latitude.toStringAsFixed(2)}:${p.longitude.toStringAsFixed(2)}';
    final svc = WeatherService(location: loc);
    try {
      final now = await svc.fetchNow();
      if (!mounted) return;
      final w = weatherFromSeniverseCode(now.code);
      if (w != Weather.unknown) setState(() => _weather = w);
    } catch (_) {
      // 天气获取失败不打扰用户，保持原天气。
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final store = context.read<AppStore>();
    final draft = _buildDraft();
    try {
      await store.saveEntry(draft);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$e')));
      return;
    }
    if (!mounted) return;
    _dirty = false;
    final saved = store.entries.where((x) => x.id == draft.id);
    Navigator.pop(context, saved.isEmpty ? draft : saved.first);
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

  Future<void> _confirmLeave() async {
    final action = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('放弃未保存的修改？'),
        content: const Text('返回后本次编辑将丢失。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, 'cancel'),
              child: const Text('继续编辑')),
          TextButton(
              onPressed: () => Navigator.pop(c, 'discard'),
              child: const Text('放弃')),
          FilledButton(
              onPressed: () => Navigator.pop(c, 'save'),
              child: const Text('保存')),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'save') {
      await _save();
    } else if (action == 'discard') {
      _dirty = false;
      if (mounted) Navigator.pop(context);
    }
  }

  // -------------------------------------------------------------------------
  // 构建
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? '新日记' : '编辑'),
          actions: [
            if (!_isNew)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '删除',
                onPressed: _delete,
              ),
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('保存'),
            ),
            const SizedBox(width: 4),
          ],
        ),
        // 工具栏放在 body 内的 Column 末尾（而非 bottomNavigationBar）。
        // bottomNavigationBar 在 adjustResize 模式下不一定随键盘抬升，会导致
        // 工具栏被键盘遮挡；放到 body 内则一定随键盘收缩区上移。
        resizeToAvoidBottomInset: true,
        body: Column(
          children: [
            Expanded(
              // 点击编辑区任意处自动折叠底部面板（属性 / 段落样式 / 插入）。
              // 用 Listener 而非 GestureDetector：原始事件不经手势竞技场，
              // 点进文本框放光标、点空白处、滚动都会触发折叠，不干扰输入。
              child: Listener(
                onPointerDown: (_) => _collapsePanel(),
                child: ListView(
                  controller: _scrollCtl,
                  // 底部留出工具栏（actionRow 48 + 系统安全区），避免最底块被遮挡
                  padding: EdgeInsets.fromLTRB(
                      16, 8, 16, 48 + MediaQuery.of(context).padding.bottom),
                  children: [
                    _metaStrip(),
                    const SizedBox(height: 10),
                    _titleField(),
                    const SizedBox(height: 6),
                    ..._blockList(),
                    _tailSpacer(),
                  ],
                ),
              ),
            ),
            _toolbar(),
          ],
        ),
      ),
    );
  }

  Widget _metaStrip() {
    final t = context.tokens;
    final loc = _locationCtl.text.trim();
    final chips = <Widget>[
      _metaChip(icon: Icons.calendar_today_outlined, label: _date),
      _metaChip(label: '${_mood.emoji} ${_mood.label}'),
      _metaChip(icon: _weather.iconData, label: _weather.label),
      if (loc.isNotEmpty) _metaChip(icon: Icons.place_outlined, label: loc),
      for (final tag in _tags) _metaChip(label: '#$tag'),
    ];
    return GestureDetector(
      onTap: () => setState(() => _panel = _Panel.props),
      child: Container(
        color: Colors.transparent,
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          ...chips,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.radiusChip),
              border: Border.all(color: t.border),
            ),
            child: Icon(Icons.tune, size: 14, color: t.textSecondary),
          ),
        ]),
      ),
    );
  }

  Widget _metaChip({IconData? icon, required String label}) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: t.fill,
        borderRadius: BorderRadius.circular(t.radiusChip),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: t.textSecondary),
          const SizedBox(width: 4),
        ],
        Text(label, style: TextStyle(fontSize: 12.5, color: t.textSecondary)),
      ]),
    );
  }

  Widget _titleField() => TextField(
        controller: _titleCtl,
        textCapitalization: TextCapitalization.sentences,
        style: TextStyle(
          fontSize: 24,
          height: 1.3,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: context.tokens.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: '标题',
          hintStyle: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: context.tokens.textTertiary,
          ),
          filled: false,
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
      );

  List<Widget> _blockList() {
    final out = <Widget>[];
    var ordinal = 0;
    for (var i = 0; i < _blocks.length; i++) {
      final b = _blocks[i];
      final prev = i > 0 ? _blocks[i - 1] : null;
      if (b.kind == BlockKind.numbered) {
        ordinal =
            (prev != null && prev.kind == BlockKind.numbered) ? ordinal + 1 : 1;
      }
      out.add(Padding(
        padding: _blockSpacing(b, prev),
        child: _blockWidget(b, ordinal),
      ));
    }
    return out;
  }

  EdgeInsets _blockSpacing(DocBlock b, DocBlock? prev) {
    if (prev == null) return EdgeInsets.zero;
    if (prev.kind.isList && b.kind == prev.kind) {
      return const EdgeInsets.only(top: 2);
    }
    if (b.kind.isHeading) return const EdgeInsets.only(top: 12);
    if (!b.kind.isText) return const EdgeInsets.only(top: 8);
    return const EdgeInsets.only(top: 4);
  }

  Widget _blockWidget(DocBlock b, int ordinal) {
    final t = context.tokens;
    switch (b.kind) {
      case BlockKind.divider:
        return Row(children: [
          Expanded(child: Divider(color: t.border, height: 1)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _removeBlock(b),
            child: Icon(Icons.close, size: 15, color: t.textTertiary),
          ),
        ]);

      case BlockKind.media:
        final media = b.media;
        if (media == null) return const SizedBox.shrink();
        return MediaBlockCard(media: media, onRemove: () => _removeBlock(b));

      default:
        return _textBlock(b, ordinal);
    }
  }

  String _hintFor(DocBlock b) {
    if (b.kind.isHeading) return '标题';
    switch (b.kind) {
      case BlockKind.quote:
        return '引用内容';
      case BlockKind.code:
        return '代码';
      case BlockKind.todo:
        return '待办事项';
      case BlockKind.bullet:
      case BlockKind.numbered:
        return '列表项';
      default:
        return _blocks.length == 1 ? '今天发生了什么？' : '继续写…';
    }
  }

  Widget _textBlock(DocBlock b, int ordinal) {
    final t = context.tokens;
    final ctl = _controllerFor(b)..palette = InlinePalette.of(context);
    final node = _focusNodeFor(b);
    final style = blockTextStyle(context, b.kind);

    final field = Stack(
      children: [
        if (b.text.isEmpty && (node.hasFocus || _blocks.length == 1))
          Positioned.fill(
            child: IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  _hintFor(b),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style.copyWith(color: t.textTertiary),
                ),
              ),
            ),
          ),
        TextField(
          controller: ctl,
          focusNode: node,
          maxLines: null,
          minLines: 1,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          textCapitalization: TextCapitalization.sentences,
          style: style,
          cursorColor: Theme.of(context).colorScheme.primary,
          inputFormatters:
              b.kind == BlockKind.code ? null : [_lineBreakFormatter(b)],
          decoration: const InputDecoration(
            filled: false,
            isDense: true,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 4),
          ),
        ),
      ],
    );

    switch (b.kind) {
      case BlockKind.quote:
        return Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.5),
                width: 3,
              ),
            ),
          ),
          child: field,
        );

      case BlockKind.code:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: t.fill,
            borderRadius: BorderRadius.circular(t.radiusInput),
            border: Border.all(color: t.border),
          ),
          child: field,
        );

      case BlockKind.bullet:
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 11, right: 8, left: 2),
            child: Container(
              width: 5,
              height: 5,
              decoration:
                  BoxDecoration(color: t.textSecondary, shape: BoxShape.circle),
            ),
          ),
          Expanded(child: field),
        ]);

      case BlockKind.numbered:
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SizedBox(
              width: 22,
              child: Text('$ordinal.',
                  style: style.copyWith(color: t.textSecondary)),
            ),
          ),
          Expanded(child: field),
        ]);

      case BlockKind.todo:
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: () => _toggleTodo(b),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(top: 5, right: 6),
              child: Icon(
                b.checked ? Icons.check_box : Icons.check_box_outline_blank,
                size: 20,
                color: b.checked
                    ? Theme.of(context).colorScheme.primary
                    : t.textTertiary,
              ),
            ),
          ),
          Expanded(child: field),
        ]);

      default:
        return field;
    }
  }

  /// 底部大片留白：点一下就把光标放到最后（或补一个新段落），像纸一样好写。
  Widget _tailSpacer() => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final last = _blocks.isEmpty ? null : _blocks.last;
          if (last == null || !last.kind.isText) {
            final b = DocBlock.paragraph();
            setState(() => _blocks.add(b));
            WidgetsBinding.instance.addPostFrameCallback(
                (_) => _focusNodeFor(b).requestFocus());
            return;
          }
          final ctl = _controllerFor(last);
          _focusNodeFor(last).requestFocus();
          ctl.setPlainCaret(ctl.plainText.length);
        },
        child: const SizedBox(height: 160),
      );

  // -------------------------------------------------------------------------
  // 底部工具栏
  // -------------------------------------------------------------------------

  Widget _toolbar() {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: _panelBody(),
            ),
            _actionRow(),
          ],
        ),
      ),
    );
  }

  Widget _actionRow() {
    final active = _activeMarks;
    final focused = _focusedBlock;
    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(children: [
          _ToolButton(
            icon: Icons.text_fields,
            tooltip: '段落样式',
            active: _panel == _Panel.style,
            onTap: () => _togglePanel(_Panel.style),
          ),
          _toolDivider(),
          _ToolButton(
            icon: Icons.format_bold,
            tooltip: '加粗',
            active: active.contains(MarkKind.bold),
            onTap: () => _toggleMark(MarkKind.bold),
          ),
          _ToolButton(
            icon: Icons.format_italic,
            tooltip: '斜体',
            active: active.contains(MarkKind.italic),
            onTap: () => _toggleMark(MarkKind.italic),
          ),
          _ToolButton(
            icon: Icons.format_underlined,
            tooltip: '下划线',
            active: active.contains(MarkKind.underline),
            onTap: () => _toggleMark(MarkKind.underline),
          ),
          _ToolButton(
            icon: Icons.format_strikethrough,
            tooltip: '删除线',
            active: active.contains(MarkKind.strike),
            onTap: () => _toggleMark(MarkKind.strike),
          ),
          _ToolButton(
            icon: Icons.code,
            tooltip: '行内代码',
            active: active.contains(MarkKind.code),
            onTap: () => _toggleMark(MarkKind.code),
          ),
          _ToolButton(
            icon: Icons.format_clear,
            tooltip: '清除格式',
            onTap: () {
              final b = focused;
              if (b != null) _controllerFor(b).clearMarks();
            },
          ),
          _toolDivider(),
          _ToolButton(
            icon: Icons.add_circle_outline,
            tooltip: '插入',
            active: _panel == _Panel.insert,
            onTap: () => _togglePanel(_Panel.insert),
          ),
          _ToolButton(
            icon: Icons.tune,
            tooltip: '心情 / 天气 / 标签',
            active: _panel == _Panel.props,
            onTap: () => _togglePanel(_Panel.props),
          ),
          _toolDivider(),
          _ToolButton(
            icon: Icons.keyboard_hide_outlined,
            tooltip: '收起键盘',
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          ),
        ]),
      ),
    );
  }

  Widget _toolDivider() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Container(width: 1, height: 20, color: context.tokens.border),
      );

  Widget _panelBody() {
    switch (_panel) {
      case _Panel.none:
        return const SizedBox(width: double.infinity);
      case _Panel.style:
        return _stylePanel();
      case _Panel.insert:
        return _insertPanel();
      case _Panel.props:
        return _propsPanel();
    }
  }

  Widget _panelShell({required String title, required Widget child}) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(title,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: t.textSecondary)),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => _panel = _Panel.none),
              child: Icon(Icons.expand_more, size: 18, color: t.textTertiary),
            ),
          ]),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _stylePanel() {
    final current = _focusedBlock?.kind ?? BlockKind.paragraph;
    const kinds = [
      BlockKind.paragraph,
      BlockKind.heading1,
      BlockKind.heading2,
      BlockKind.heading3,
      BlockKind.quote,
      BlockKind.bullet,
      BlockKind.numbered,
      BlockKind.todo,
      BlockKind.code,
    ];
    return _panelShell(
      title: '段落样式',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: kinds
            .map((k) => _PillButton(
                  label: k.label,
                  active: k == current,
                  onTap: () => _setBlockKind(k),
                ))
            .toList(),
      ),
    );
  }

  Widget _insertPanel() => _panelShell(
        title: '插入',
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _InsertTile(
              icon: Icons.photo_library_outlined,
              label: '图片',
              onTap: () => _pickImage(ImageSource.gallery),
            ),
            _InsertTile(
              icon: Icons.photo_camera_outlined,
              label: '拍照',
              onTap: () => _pickImage(ImageSource.camera),
            ),
            _InsertTile(
              icon: Icons.videocam_outlined,
              label: '视频',
              onTap: _pickVideo,
            ),
            _InsertTile(
              icon: Icons.audiotrack_outlined,
              label: '音频',
              onTap: () => _pickFile(AssetKind.audio),
            ),
            _InsertTile(
              icon: Icons.attach_file,
              label: '文件',
              onTap: () => _pickFile(AssetKind.attachment),
            ),
            _InsertTile(
              icon: Icons.horizontal_rule,
              label: '分割线',
              onTap: () => _insertBlockAfterCursor(DocBlock.divider()),
            ),
          ],
        ),
      );

  Widget _propsPanel() {
    final t = context.tokens;
    return _panelShell(
      title: '日记属性',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 16),
                    label: Text(_date),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: t.border),
                      foregroundColor: t.textPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _locationCtl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: '地点',
                      isDense: true,
                      prefixIcon: const Icon(Icons.place_outlined, size: 18),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 34, minHeight: 34),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: _locatingLocation
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.my_location, size: 18),
                            tooltip: '定位当前位置',
                            onPressed:
                                _locatingLocation ? null : _locateCurrentLocation,
                          ),
                          IconButton(
                            icon: const Icon(Icons.map_outlined, size: 18),
                            tooltip: '地图选点',
                            onPressed: _pickLocation,
                          ),
                        ],
                      ),
                      suffixIconConstraints:
                          const BoxConstraints(minWidth: 68, minHeight: 34),
                    ),
                  ),
                ),
              ]),
              if (_latitude != null && _longitude != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Icon(Icons.location_pin,
                          size: 14, color: Colors.redAccent),
                      Text(
                        '已选坐标 ${_latitude!.toStringAsFixed(5)}, '
                        '${_longitude!.toStringAsFixed(5)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      GestureDetector(
                        onTap: () => setState(() {
                          _latitude = null;
                          _longitude = null;
                        }),
                        child: const Text('清除',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.redAccent,
                                decoration: TextDecoration.underline)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              _panelLabel('心情'),
              _chipRow<Mood>(
                values: Mood.ordered,
                selected: _mood,
                labelOf: (m) => '${m.emoji} ${m.label}',
                onSelect: (m) => setState(() {
                  _mood = m;
                  _dirty = true;
                }),
              ),
              const SizedBox(height: 12),
              _panelLabel('天气'),
              _chipRow<Weather>(
                values: Weather.ordered,
                selected: _weather,
                labelOf: (w) => '${w.emoji} ${w.label}',
                onSelect: (w) => setState(() {
                  _weather = w;
                  _dirty = true;
                }),
              ),
              const SizedBox(height: 12),
              _panelLabel('标签'),
              Wrap(spacing: 6, runSpacing: 6, children: [
                ..._tags.map((tag) => InputChip(
                      label: Text('#$tag'),
                      onDeleted: () => setState(() {
                        _tags.remove(tag);
                        _dirty = true;
                      }),
                      deleteIcon: const Icon(Icons.close, size: 15),
                    )),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _tagCtl,
                    decoration: const InputDecoration(
                      hintText: '添加标签',
                      isDense: true,
                    ),
                    onSubmitted: _addTag,
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panelLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.tokens.textSecondary)),
      );

  Widget _chipRow<T>({
    required List<T> values,
    required T selected,
    required String Function(T) labelOf,
    required void Function(T) onSelect,
  }) =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: values
              .map((v) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _PillButton(
                      label: labelOf(v),
                      active: v == selected,
                      onTap: () => onSelect(v),
                    ),
                  ))
              .toList(),
        ),
      );
}

// ---------------------------------------------------------------------------
// 工具栏零件（全部用 GestureDetector，避免抢走输入框焦点导致键盘收起）
// ---------------------------------------------------------------------------

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final primary = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 42,
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          alignment: Alignment.center,
          decoration: active
              ? BoxDecoration(
                  color: primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                )
              : null,
          child: Icon(icon,
              size: 20, color: active ? primary : t.textSecondary),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _PillButton({
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? primary.withValues(alpha: 0.12) : t.fill,
          borderRadius: BorderRadius.circular(t.radiusChip),
          border: Border.all(color: active ? primary : t.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? primary : t.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _InsertTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _InsertTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 78,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: t.fill,
          borderRadius: BorderRadius.circular(t.radiusInput),
          border: Border.all(color: t.border),
        ),
        child: Column(children: [
          Icon(icon, size: 20, color: t.textPrimary),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(fontSize: 12, color: t.textSecondary)),
        ]),
      ),
    );
  }
}
