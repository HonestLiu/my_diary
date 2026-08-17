// Regression: search with SearchScope filters only matches the selected fields.
// Pins the 4-scope contract: title / body / tags / location — each separate.

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

    await repo.saveEntry(e('a', '关于日常的记录', '今天天气很好',
        tags: ['生活', '日常'], location: '上海'));
    await repo.saveEntry(e('b', '日记B', '吃了个苹果'));
    await repo.saveEntry(
        e('c', '日记C', '无事发生，平凡的日常', location: '北京'));
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('no filters: searches all fields (backward-compatible)', () async {
    final res = await repo.search('日常');
    expect(res.length, 2); // A (title) + C (body)
  });

  test('title-only: matches title only, not body', () async {
    // A's title contains「日常」, C's body contains「日常」but title does not.
    final res = await repo.search('日常', filters: {SearchScope.title});
    expect(res.length, 1);
    expect(res.first.id, 'a');
  });

  test('body-only: matches body only, not title', () async {
    final res = await repo.search('苹果', filters: {SearchScope.body});
    expect(res.length, 1);
    expect(res.first.id, 'b');
  });

  test('tags-only: matches only tagged entries', () async {
    final res = await repo.search('日常', filters: {SearchScope.tags});
    expect(res.length, 1);
    expect(res.first.id, 'a');
  });

  test('location-only: matches only locations', () async {
    final res = await repo.search('上海', filters: {SearchScope.location});
    expect(res.length, 1);
    expect(res.first.id, 'a');
  });

  test('multi-select: title + body union', () async {
    final res = await repo.search('日常',
        filters: {SearchScope.title, SearchScope.body});
    expect(res.length, 2); // A (title) + C (body)
  });

  test('case-insensitive', () async {
    final res = await repo.search('生活', filters: {SearchScope.tags});
    expect(res.length, 1);
    expect(res.first.id, 'a');
  });
}
