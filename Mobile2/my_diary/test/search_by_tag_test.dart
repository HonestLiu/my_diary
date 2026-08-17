// Regression: search with SearchScope filters only matches the selected fields;
// tags-only must NOT pick up body/title matches, and location-only must NOT
// pick up body/tag matches.
// Pins the search-filter contract for the new FilterChip UI.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/repository/journal_repository.dart';
import 'package:my_diary_mobile/vault/local_vault.dart';

void main() {
  JournalEntry e(String id, String title, String body,
          {List<String> tags = const [], String? location}) =>
      JournalEntry(
        id: id,
        date: '2026-08-01',
        title: title,
        mood: Mood.happy,
        weather: Weather.sunny,
        tags: tags,
        location: location,
        assets: const [],
        createdAt: '2026-08-01T10:00:00.000Z',
        updatedAt: '2026-08-01T10:00:00.000Z',
        body: body,
      );

  late Directory dir;
  late JournalRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('search-filter');
    repo = JournalRepository(LocalVault(dir.path));
    await repo.init(dir.path);

    await repo.saveEntry(e('a', '日记A', '今天天气很好，日常的快乐',
        tags: ['生活', '日常'], location: '上海'));
    await repo.saveEntry(e('b', '日记B', '吃了个苹果'));
    // C 的正文含「日常」但没打标签，地点是北京。
    await repo.saveEntry(e('c', '日记C', '无事发生，平凡的日常', location: '北京'));
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('no filters: searches all fields (backward-compatible)', () async {
    final res = await repo.search('日常');
    expect(res.length, 2); // A + C (body matches)
  });

  test('tags-only: matches only tagged entries, not body', () async {
    final res = await repo.search('日常', filters: {SearchScope.tags});
    expect(res.length, 1);
    expect(res.first.id, 'a');
  });

  test('location-only: matches only locations', () async {
    final res = await repo.search('上海', filters: {SearchScope.location});
    expect(res.length, 1);
    expect(res.first.id, 'a');
  });

  test('content-only: matches title + body only, not tags/location', () async {
    // A's body contains 「日常」, title does not; but '苹果' is only in B's body.
    final res = await repo.search('苹果', filters: {SearchScope.content});
    expect(res.length, 1);
    expect(res.first.id, 'b');
  });

  test('multi-select: tags + location union', () async {
    // '日常' matches: A (tag) + C (body — excluded by filter). C has location 北京.
    // But '日常' is NOT a location. Only A's tag matches.
    final res = await repo.search('日常',
        filters: {SearchScope.tags, SearchScope.location});
    expect(res.length, 1); // only A (tag match)
  });

  test('case-insensitive', () async {
    final res = await repo.search('生活', filters: {SearchScope.tags});
    expect(res.length, 1);
    expect(res.first.id, 'a');
  });
}
