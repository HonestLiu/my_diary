import 'package:my_diary_mobile/models/journal_entry.dart';

/// Vault 布局（规范、开放的磁盘结构），与桌面端 `Desktop/src/lib/vault.ts` 一致：
///
/// MyDiary/
/// ├── entries/YYYY/MM/YYYY-MM-DD-<shortid>.md
/// ├── assets/{images,audio,video,attachments}/
/// ├── metadata/{index.json,sync.json}
/// ├── versions/<entry-id>/vN.md
/// ├── conflicts/<entry-file-name>.{local,remote}.md
/// └── settings.json
///
/// 条目由 `id` 标识（而非日期）：任意多条目可共享同一天。日期只是普通元数据。
/// 所有函数返回相对于 vault 根的路径，因此同一套代码可作用于任何存储后端。
class VaultLayout {
  static const String settings = 'settings.json';
  static const String index = 'metadata/index.json';
  static const String sync = 'metadata/sync.json';
  static const String entries = 'entries';
  static const String assets = 'assets';
  static const String versions = 'versions';
  static const String conflicts = 'conflicts';

  static const List<String> requiredDirectories = [
    'entries',
    'assets/images',
    'assets/audio',
    'assets/video',
    'assets/attachments',
    'metadata',
    'versions',
    'conflicts',
  ];
}

/// 派生条目磁盘位置所需的最小信息。
class EntryFileRef {
  final String id;
  final String date;
  const EntryFileRef({required this.id, required this.date});
}

/// 条目 id 的短、文件名安全片段（可读且能区分同天多条目）。
String shortEntryId(String id) {
  final clean = id.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '').toLowerCase();
  return clean.length >= 8 ? clean.substring(0, 8) : (clean.isNotEmpty ? clean : 'entry');
}

String entryFileName(EntryFileRef entry) =>
    '${entry.date}-${shortEntryId(entry.id)}.md';

/// 条目规范路径：entries/YYYY/MM/YYYY-MM-DD-<shortid>.md
String entryFilePath(EntryFileRef entry) =>
    '${entryDir(entry.date)}/${entryFileName(entry)}';

String entryDir(String dateKey) {
  final parts = dateKey.split('-');
  final y = parts.isNotEmpty ? parts[0] : '0000';
  final m = parts.length > 1 ? parts[1] : '00';
  return 'entries/$y/$m';
}

String assetDir(AssetKind kind) {
  switch (kind) {
    case AssetKind.image:
      return 'assets/images';
    case AssetKind.audio:
      return 'assets/audio';
    case AssetKind.video:
      return 'assets/video';
    case AssetKind.attachment:
      return 'assets/attachments';
  }
}

String assetPath(AssetKind kind, String filename) => '${assetDir(kind)}/$filename';

String versionDir(String entryKey) => 'versions/${sanitizeKey(entryKey)}';

String versionFilePath(String entryKey, int version) =>
    '${versionDir(entryKey)}/v$version.md';

String conflictFilePath(String key, String side) =>
    'conflicts/${sanitizeKey(key)}.$side.md';

/// 剥离文件名中不安全的（或路径穿越的）字符。
String sanitizeKey(String key) {
  final cleaned = key.replaceAll(RegExp(r'[^0-9a-zA-Z._-]'), '_');
  return cleaned.isNotEmpty ? cleaned : 'entry';
}

/// 从条目文件路径提取日期键（YYYY-MM-DD）。同时兼容当前命名与旧版 `YYYY-MM-DD.md`。
String? dateKeyFromEntryPath(String path) {
  final m = RegExp(
          r'entries/\d{4}/\d{2}/(\d{4}-\d{2}-\d{2})(?:-[0-9a-zA-Z]+)?\.md$')
      .firstMatch(path);
  return m?.group(1);
}

/// 为同步冲突副本生成稳定、无碰撞的 key：优先用条目文件名，否则用扁平化路径。
String conflictKeyFromPath(String path) {
  final base = RegExp(r'([^/]+)\.md$').firstMatch(path)?.group(1);
  if (base != null && dateKeyFromEntryPath(path) != null) return base;
  return path.replaceAll('/', '_').replaceAll(RegExp(r'\.md$'), '');
}
