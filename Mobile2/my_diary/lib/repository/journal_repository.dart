import 'dart:convert';

import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/models/settings.dart';
import 'package:my_diary_mobile/repository/version.dart' as versions;
import 'package:my_diary_mobile/vault/local_vault.dart';
import 'package:my_diary_mobile/vault/markdown_codec.dart';
import 'package:my_diary_mobile/vault/vault_layout.dart';
import 'package:uuid/uuid.dart';

/// 搜索范围：内容（标题+正文）/ 标签 / 地点。
/// 用于搜索页的类别筛选器（FilterChip），同时驱动搜索逻辑。
enum SearchScope {
  title,
  body,
  tags,
  location;

  /// 中文标签（UI FilterChip 展示用）。
  String get label => switch (this) {
        SearchScope.title => '标题',
        SearchScope.body => '正文',
        SearchScope.tags => '标签',
        SearchScope.location => '地点',
      };
}

/// JournalRepository —— UI 调用的高层 API（镜像桌面端 `journal.ts`）。
///
/// 职责：
///   - 通过 LocalVault 读写 Markdown 文件
///   - 在内存中维护索引（元数据 + 搜索用），落盘即从磁盘重建
///   - 负责 vault 创建、设置、版本快照
///
/// 条目以 `id` 寻址，绝不以日期寻址：一天可含任意多条目，改日期即移动文件。
/// 磁盘上的 Markdown 文件始终是事实来源；索引是派生缓存，漂移时可 reindex()。
class JournalRepository {
  final LocalVault storage;

  /// entry id -> vault 相对文件路径（每次扫描后重建）。
  final Map<String, String> _pathById = {};

  /// 当 `_pathById` 已知镜像 vault 时为 true（保存/删除后保持更新）。
  bool _pathMapFresh = false;

  String vaultRoot = '';

  JournalRepository(this.storage);

  /// 暴露底层存储（供同步引擎使用）。
  LocalVault get storageAdapter => storage;

  Future<void> init(String vaultRoot) async {
    this.vaultRoot = vaultRoot;
    await storage.init();
    await reindex();
  }

  /// 从磁盘 Markdown 重建索引（及 id -> 路径映射）。
  Future<void> reindex() async {
    _pathById.clear();
    final files = await storage.list('entries/');
    for (final f in files) {
      if (!f.endsWith('.md')) continue;
      try {
        final raw = await storage.readText(f);
        final parsed = parseEntryFile(raw);
        _pathById[parsed.meta.id] = f;
      } catch (_) {
        // 跳过不可读 / 损坏的文件
      }
    }
    _pathMapFresh = true;
  }

  /// 读取全部条目，最新在前，并刷新 id -> 路径映射。
  Future<List<JournalEntry>> listEntries() async {
    final files = await storage.list('entries/');
    final entries = <JournalEntry>[];
    _pathById.clear();
    for (final f in files) {
      if (!f.endsWith('.md')) continue;
      try {
        final raw = await storage.readText(f);
        final parsed = parseEntryFile(raw);
        _pathById[parsed.meta.id] = f;
        entries.add(_toEntry(parsed.meta, parsed.body));
      } catch (_) {
        /* skip */
      }
    }
    _pathMapFresh = true;
    entries.sort(byRecency);
    return entries;
  }

  /// 定位条目文件，仅在必要时重新扫描 vault。
  Future<String?> resolvePath(String id) async {
    final known = _pathById[id];
    if (known != null) {
      if (await storage.exists(known)) return known;
      _pathById.remove(id);
      await listEntries();
      return _pathById[id];
    }
    if (_pathMapFresh) return null; // 全新条目：无文件可找
    await listEntries();
    return _pathById[id];
  }

  /// 按 id 加载单个条目。
  Future<JournalEntry?> getEntry(String id) async {
    final p = await resolvePath(id);
    if (p == null) return null;
    try {
      final raw = await storage.readText(p);
      final parsed = parseEntryFile(raw);
      return _toEntry(parsed.meta, parsed.body);
    } catch (_) {
      return null;
    }
  }

  /// 某天写下的全部条目，最新在前（一天可含多条）。
  Future<List<JournalEntry>> getEntriesByDate(String dateKey) async {
    final all = await listEntries();
    return all.where((e) => e.date == dateKey).toList();
  }

  /// 构建空白条目（不落盘；首次真实编辑时由编辑器持久化）。
  JournalEntry newEntry({String? dateKey, JournalEntry? defaults}) {
    final now = DateTime.now().toUtc().toIso8601String();
    return JournalEntry(
      id: const Uuid().v4(),
      date: dateKey ?? _formatDateKey(DateTime.now()),
      title: '',
      mood: Mood.neutral,
      weather: Weather.unknown,
      latitude: defaults?.latitude,
      longitude: defaults?.longitude,
      tags: const [],
      assets: const [],
      createdAt: now,
      updatedAt: now,
      body: '',
      content: defaults?.content,
    );
  }

  Future<void> saveEntry(JournalEntry entry) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final e = entry.copyWith(updatedAt: now);
    final nextPath = entryFilePath(
      EntryFileRef(id: e.id, date: e.date),
    );
    final prevPath = await resolvePath(e.id);
    final nextRaw = serializeEntryFile(e);

    // 仅当传入内容与之前不同时，才把「上一次」磁盘内容快照为版本（首次保存不快照）。
    if (prevPath != null) {
      try {
        final prevRaw = await storage.readText(prevPath);
        if (prevRaw.trim() != nextRaw.trim()) {
          await versions.archiveCurrent(storage, e.id, prevRaw);
        }
      } catch (_) {
        /* 旧文件不可读 —— 直接覆盖 */
      }
    }

    await storage.writeText(nextPath, nextRaw);

    // 日期是元数据：当其变化（或旧版「每天一个文件」首次保存）时，条目移动到规范位置。
    if (prevPath != null && prevPath != nextPath) {
      try {
        await storage.delete(prevPath);
      } catch (_) {
        /* 尽力而为 —— 留下旧副本也好过丢失新副本 */
      }
    }
    _pathById[e.id] = nextPath;
  }

  /// 列出某条目的历史版本（最新在前）。
  Future<List<int>> listVersions(JournalEntry entry) =>
      versions.listVersions(storage, [entry.id, entry.date]);

  /// 将某历史版本恢复为条目当前内容（保留身份；恢复前先归档）。
  Future<JournalEntry> restoreVersion(
    JournalEntry entry,
    int version, {
    String? versionKey,
  }) async {
    final key = versionKey ?? entry.id;
    final snapshot = await versions.readVersion(storage, key, version);
    if (snapshot == null) return entry;
    final restored = snapshot.copyWith(id: entry.id);
    await saveEntry(restored);
    return restored;
  }

  Future<void> deleteEntry(String id) async {
    final p = await resolvePath(id);
    if (p != null) {
      try {
        await storage.delete(p);
      } catch (_) {
        /* 已不存在 */
      }
      _pathById.remove(id);
    }
  }

  /// 搜索日记。[filters] 为空时搜全部字段（向后兼容）；指定后仅匹配对应类别。
  /// 可多选（取并集），如 {SearchScope.tags, SearchScope.location} 同时搜标签和地点。
  Future<List<JournalEntry>> search(
    String query, {
    Set<SearchScope> filters = const {},
  }) async {
    final all = await listEntries();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((e) {
      final matchTitle = e.title.toLowerCase().contains(q);
      final matchBody = e.body.toLowerCase().contains(q);
      final matchTags = e.tags.any((t) => t.toLowerCase().contains(q));
      final matchLocation =
          (e.location ?? '').toLowerCase().contains(q);

      if (filters.isEmpty) {
        return matchTitle || matchBody || matchTags || matchLocation;
      }
      return (filters.contains(SearchScope.title) && matchTitle) ||
          (filters.contains(SearchScope.body) && matchBody) ||
          (filters.contains(SearchScope.tags) && matchTags) ||
          (filters.contains(SearchScope.location) && matchLocation);
    }).toList();
  }

  /// 简单统计。
  Future<({int entries, int words, Map<Mood, int> moodCounts})> stats() async {
    final all = await listEntries();
    var words = 0;
    final moodCounts = <Mood, int>{};
    for (final e in all) {
      words += e.body.replaceAll(RegExp(r'\s+'), ' ').trim().split(' ').where((w) => w.isNotEmpty).length;
      moodCounts[e.mood] = (moodCounts[e.mood] ?? 0) + 1;
    }
    return (entries: all.length, words: words, moodCounts: moodCounts);
  }

  Future<AppSettings> loadSettings() async {
    const p = VaultLayout.settings;
    if (!(await storage.exists(p))) return defaultSettings;
    try {
      final raw = await storage.readText(p);
      final map = _deepJson(raw);
      return AppSettings.fromJson(map);
    } catch (_) {
      return defaultSettings;
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    await storage.writeText(VaultLayout.settings, _jsonEncode(settings.toJson()));
  }

  JournalEntry _toEntry(JournalMeta meta, String body) => JournalEntry(
        id: meta.id,
        date: meta.date,
        title: meta.title,
        mood: meta.mood,
        weather: meta.weather,
        location: meta.location,
        latitude: meta.latitude,
        longitude: meta.longitude,
        tags: meta.tags,
        assets: meta.assets,
        createdAt: meta.createdAt,
        updatedAt: meta.updatedAt,
        body: body,
      );
}

/// 最新在前：先比日期，同日再比创建时间。
int byRecency(JournalEntry a, JournalEntry b) {
  if (a.date != b.date) return a.date.compareTo(b.date) * -1;
  if (a.createdAt != b.createdAt) {
    return a.createdAt.compareTo(b.createdAt) * -1;
  }
  return 0;
}

String _formatDateKey(DateTime d) {
  final y = d.year;
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// 极简 JSON 解析封装（dart:convert）。
Map<String, dynamic> _deepJson(String raw) =>
    jsonDecode(raw) as Map<String, dynamic>;

String _jsonEncode(Map<String, dynamic> m) => jsonEncode(m);
