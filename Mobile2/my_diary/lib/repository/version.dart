import 'dart:typed_data';

import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/vault/local_vault.dart';
import 'package:my_diary_mobile/vault/markdown_codec.dart';
import 'package:my_diary_mobile/vault/vault_layout.dart';

/// 版本历史（落盘于 versions/<entry-id>/vN.md）。与桌面端 `version.ts` 一致。
/// 本地文件是事实来源；版本仅是「改动前快照」，便于回滚。

/// 列出某条目已有的版本号（升序）。`keys` 含 entryId，以及旧版按日期键存的版本。
Future<List<int>> listVersions(LocalVault storage, List<String> keys) async {
  final versions = <int>{};
  for (final key in keys) {
    final dir = versionDir(key);
    if (!await storage.exists(dir)) continue;
    final files = await storage.list(dir);
    for (final f in files) {
      final m = RegExp(r'v(\d+)\.md$').firstMatch(f);
      if (m != null) versions.add(int.parse(m.group(1)!));
    }
  }
  return versions.toList()..sort();
}

/// 把「改动前」的原文快照为下一个版本。
Future<void> archiveCurrent(
  LocalVault storage,
  String entryId,
  String prevRawContent,
) async {
  final existing = await listVersions(storage, [entryId]);
  final next = (existing.isEmpty ? 0 : existing.last) + 1;
  await storage.writeText(versionFilePath(entryId, next), prevRawContent);
}

/// 读取某个历史版本为完整条目。
Future<JournalEntry?> readVersion(
  LocalVault storage,
  String key,
  int version,
) async {
  final path = versionFilePath(key, version);
  if (!await storage.exists(path)) return null;
  final raw = await storage.readText(path);
  final parsed = parseEntryFile(raw);
  return JournalEntry(
    id: parsed.meta.id,
    date: parsed.meta.date,
    title: parsed.meta.title,
    mood: parsed.meta.mood,
    weather: parsed.meta.weather,
    location: parsed.meta.location,
    tags: parsed.meta.tags,
    assets: parsed.meta.assets,
    createdAt: parsed.meta.createdAt,
    updatedAt: parsed.meta.updatedAt,
    body: parsed.body,
  );
}

/// 把历史版本内容写回磁盘（供 UI 预览）。
Future<Uint8List> readVersionBytes(
  LocalVault storage,
  String key,
  int version,
) async {
  final path = versionFilePath(key, version);
  return storage.readBytes(path);
}
