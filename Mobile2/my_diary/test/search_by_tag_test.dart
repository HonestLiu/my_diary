// Regression: searchByTag matches only entries whose tags contain the query;
// entries whose body/title happen to contain the same word are excluded.
// This is the precision guarantee for the tag-cloud → search interaction.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/repository/journal_repository.dart';
import 'package:my_diary_mobile/vault/local_vault.dart';

void main() {
  test('searchByTag matches only tagged entries, not body content', () async {
    final dir = await Directory.systemTemp.createTemp('search-tag');
    final repo = JournalRepository(LocalVault(dir.path));
    await repo.init(dir.path);

    JournalEntry e(String id, String title, String body,
            [List<String> tags = const []]) =>
        JournalEntry(
          id: id,
          date: '2026-08-01',
          title: title,
          mood: Mood.happy,
          weather: Weather.sunny,
          tags: tags,
          assets: const [],
          createdAt: '2026-08-01T10:00:00.000Z',
          updatedAt: '2026-08-01T10:00:00.000Z',
          body: body,
        );

    await repo.saveEntry(
        e('a', '日记A', '今天天气很好，日常的快乐', ['生活', '日常']));
    await repo.saveEntry(e('b', '日记B', '吃了个苹果'));
    // C 的正文含有「日常」但没打该标签。
    await repo.saveEntry(e('c', '日记C', '无事发生，平凡的日常'));

    // 通用搜索会把正文含「日常」的也捞出来。
    final general = await repo.search('日常');
    expect(general.length, 2);

    // 标签专用搜索只返回真的打了「日常」标签的日记。
    final byTag = await repo.searchByTag('日常');
    expect(byTag.length, 1);
    expect(byTag.first.id, 'a');

    // 大小写不敏感。
    final byTagUpper = await repo.searchByTag('生活');
    expect(byTagUpper.length, 1);
    expect(byTagUpper.first.id, 'a');

    await dir.delete(recursive: true);
  });
}
