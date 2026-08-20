// Unit tests for the mobile diary's data-interchange contract.
//
// The whole point of the mobile app is to share diary data with the desktop
// (Tauri) app through an open format: Markdown body + YAML frontmatter on disk,
// plus SHA-256 file fingerprints for sync. These tests pin that contract so the
// two sides stay compatible.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/repository/journal_repository.dart';
import 'package:my_diary_mobile/services/widget_service.dart';
import 'package:my_diary_mobile/sync/crypto.dart';
import 'package:my_diary_mobile/vault/local_vault.dart';
import 'package:my_diary_mobile/vault/markdown_codec.dart';
import 'package:my_diary_mobile/vault/vault_layout.dart';
import 'package:my_diary_mobile/vault/yaml_frontmatter.dart';

void main() {
  group('Markdown codec round-trip', () {
    test('serializes and parses back every field', () {
      final entry = JournalEntry(
        id: 'abc123-def456',
        date: '2026-08-17',
        title: '我的第一条日记',
        mood: Mood.happy,
        weather: Weather.sunny,
        location: '上海',
        tags: const ['flutter', '日记'],
        assets: const [
          AssetRef(
            kind: AssetKind.image,
            path: 'assets/images/x.webp',
            name: 'x.webp',
            size: 123,
          ),
        ],
        createdAt: '2026-08-17T10:00:00.000Z',
        updatedAt: '2026-08-17T10:05:00.000Z',
        body: '今天开始写移动端日记。\n\n第二段落。',
      );

      final raw = serializeEntryFile(entry);
      expect(raw.startsWith('---\n'), isTrue);
      expect(raw, contains('\n---\n\n# 我的第一条日记\n'));

      final parsed = parseEntryFile(raw, fallbackId: 'fallback');
      expect(parsed.meta.id, 'abc123-def456');
      expect(parsed.meta.title, '我的第一条日记');
      expect(parsed.meta.mood, Mood.happy);
      expect(parsed.meta.weather, Weather.sunny);
      expect(parsed.meta.location, '上海');
      expect(parsed.meta.tags, const ['flutter', '日记']);
      expect(parsed.meta.assets, hasLength(1));
      expect(parsed.meta.assets.first.kind, AssetKind.image);
      expect(parsed.meta.assets.first.path, 'assets/images/x.webp');
      expect(parsed.meta.createdAt, '2026-08-17T10:00:00.000Z');
      expect(parsed.meta.updatedAt, '2026-08-17T10:05:00.000Z');
      // Leading H1 is stripped on read; body survives intact.
      expect(parsed.body, '今天开始写移动端日记。\n\n第二段落。');
    });

    test('falls back to generated id when frontmatter has none', () {
      const raw = '---\ndate: "2026-08-17"\ntitle: "无 id"\n---\n\n# 无 id\n\n正文\n';
      final parsed = parseEntryFile(raw, fallbackId: 'generated-id');
      expect(parsed.meta.id, 'generated-id');
    });
  });

  group('YAML compatibility with desktop (js-yaml)', () {
    test('parses flow-style tags and assets emitted by js-yaml', () {
      // This is roughly how the desktop `buildFrontmatter` may serialize.
      const text = '''
id: "entry-1"
date: "2026-08-17"
title: "Flow style"
mood: "calm"
weather: "rainy"
location: "Beijing"
tags: [alpha, beta, gamma]
assets: [{kind: image, path: "assets/images/a.webp"}]
created_at: "2026-08-17T00:00:00.000Z"
updated_at: "2026-08-17T00:00:00.000Z"
''';
      final m = parseFrontmatter(text);
      expect(m.id, 'entry-1');
      expect(m.tags, const ['alpha', 'beta', 'gamma']);
      expect(m.assets, hasLength(1));
      expect(m.assets.first.kind, AssetKind.image);
      expect(m.assets.first.path, 'assets/images/a.webp');
      expect(m.mood, Mood.calm);
      expect(m.weather, Weather.rainy);
    });

    test('tolerates missing optional fields', () {
      const text = 'id: "x"\ndate: "2026-08-17"\ntitle: "最少字段"\n';
      final m = parseFrontmatter(text);
      expect(m.id, 'x');
      expect(m.tags, isEmpty);
      expect(m.assets, isEmpty);
      expect(m.mood, Mood.neutral);
      expect(m.weather, Weather.unknown);
      expect(m.location, isNull);
    });
  });

  group('Fast frontmatter parser (self-generated block format)', () {
    test('parses scalars, escapes, numbers, block lists and asset maps', () {
      // 与 encodeFrontmatter 落盘形态一致（原始字符串：转义为字面反斜杠）。
      const text = r'''
id: "e-42"
date: "2026-08-17"
title: "标题 \"带引号\" 与\n换行"
mood: "excited"
weather: "sunny"
location: "上海"
latitude: 31.23
longitude: 121.47
favorite: true
tags:
  - "日常"
  - "工作"
assets:
  - kind: "image"
    path: "assets/images/a1.jpg"
    name: "a1.jpg"
    size: 12345
created_at: "2026-08-17T00:00:00.000Z"
updated_at: "2026-08-17T01:00:00.000Z"
''';
      final m = parseFrontmatter(text);
      expect(m.id, 'e-42');
      expect(m.title, '标题 "带引号" 与\n换行');
      expect(m.mood, Mood.excited);
      expect(m.latitude, 31.23);
      expect(m.favorite, isTrue);
      expect(m.tags, const ['日常', '工作']);
      expect(m.assets, hasLength(1));
      expect(m.assets.first.kind, AssetKind.image);
      expect(m.assets.first.path, 'assets/images/a1.jpg');
      expect(m.assets.first.name, 'a1.jpg');
      expect(m.assets.first.size, 12345);
    });

    test('round-trip via encodeFrontmatter survives the fast path', () {
      final entry = JournalEntry(
        id: 'roundtrip',
        date: '2026-08-17',
        title: '回环测试',
        mood: Mood.happy,
        weather: Weather.foggy,
        location: '杭州',
        tags: const ['a', 'b'],
        assets: const [
          AssetRef(
            kind: AssetKind.video,
            path: 'assets/videos/v1.mp4',
            name: 'v1.mp4',
            size: 99,
          ),
        ],
        createdAt: '2026-08-17T00:00:00.000Z',
        updatedAt: '2026-08-17T00:00:00.000Z',
        body: '正文',
      );
      final m = parseFrontmatter(encodeFrontmatter(entry));
      expect(m.id, entry.id);
      expect(m.title, entry.title);
      expect(m.mood, entry.mood);
      expect(m.weather, entry.weather);
      expect(m.location, entry.location);
      expect(m.tags, entry.tags);
      expect(m.assets, hasLength(1));
      expect(m.assets.first.path, 'assets/videos/v1.mp4');
      expect(m.assets.first.size, 99);
    });
  });

  group('Vault layout paths', () {
    test('entryFilePath follows entries/YYYY/MM convention', () {
      final p = entryFilePath(
        const EntryFileRef(id: 'abcDEF1234567890', date: '2026-08-17'),
      );
      expect(p, 'entries/2026/08/2026-08-17-abcdef12.md');
    });

    test('dateKeyFromEntryPath extracts the date', () {
      expect(
        dateKeyFromEntryPath('entries/2026/08/2026-08-17-abcdef12.md'),
        '2026-08-17',
      );
    });

    test('conflictKeyFromPath uses the file base name', () {
      expect(
        conflictKeyFromPath('entries/2026/08/2026-08-17-abcdef12.md'),
        '2026-08-17-abcdef12',
      );
    });

    test('shortEntryId truncates and lowercases', () {
      expect(shortEntryId('ABCDEF1234567890'), 'abcdef12');
      expect(shortEntryId('short'), 'short');
    });

    test('versionFilePath nests under versions/<key>', () {
      expect(versionFilePath('entry-1', 3), 'versions/entry-1/v3.md');
    });
  });

  group('Crypto fingerprint', () {
    test('SHA-256 of empty input matches the known digest', () {
      expect(sha256Hex(const []),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });

    test('HMAC-SHA256 hex 是 64 位小写十六进制（RFC 4231 测试向量 1）', () {
      // 曾因对 Uint8List 调 toString() 而输出 "[11, 11, ...]" 列表表示，
      // 生成非法 Signature 导致 S3/MinIO/OSS 全部 400/403。
      final key = Uint8List.fromList(List.filled(20, 0x0b));
      final hex = hmacSha256Hex(key, 'Hi There');
      expect(hex,
          'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7');
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hex), isTrue);
    });
  });

  group('Incremental list loading (listMetadata + fillBodies)', () {
    test('元数据列表不含正文，fillBodies 按页补齐', () async {
      final root = Directory.systemTemp.createTempSync('incr_').path;
      final vault = LocalVault(root);
      await vault.init();
      final repo = JournalRepository(vault);
      await repo.init(root);
      for (var i = 0; i < 5; i++) {
        final e = JournalEntry(
          id: 'e$i',
          date: '2026-08-1$i',
          title: 't$i',
          mood: Mood.calm,
          weather: Weather.sunny,
          tags: const [],
          assets: const [],
          createdAt: '2026-08-01T00:00:00.000Z',
          updatedAt: '2026-08-01T00:00:00.000Z',
          body: '正文内容 $i',
        );
        await vault.writeText(
          entryFilePath(EntryFileRef(id: e.id, date: e.date)),
          serializeEntryFile(e),
        );
      }

      final all = await repo.listMetadata();
      expect(all, hasLength(5));
      expect(all.every((e) => e.body.isEmpty), isTrue,
          reason: 'listMetadata 不携带正文');

      // 再补一页正文（前 3 条）。
      final page = await repo.fillBodies(all.take(3).toList());
      expect(page, hasLength(3));
      expect(page.every((e) => e.body.isNotEmpty), isTrue);
      expect(page.first.body, contains('正文内容'));

      await Directory(root).delete(recursive: true);
    });
  });

  group('WidgetService.compute（桌面小组件数据）', () {
    JournalEntry _e(String id, String date, String title, Mood mood,
            {String body = ''}) =>
        JournalEntry(
          id: id,
          date: date,
          title: title,
          mood: mood,
          weather: Weather.sunny,
          tags: const [],
          assets: const [],
          createdAt: '2026-08-19T00:00:00.000Z',
          updatedAt: '2026-08-19T00:00:00.000Z',
          body: body,
        );

    test('今日速览 + 最近一条（最新在前）', () {
      final now = DateTime(2026, 8, 19, 12);
      final entries = [
        _e('b', '2026-08-19', '今天的日记', Mood.happy,
            body: '**今天**去了公园，还买了牛奶。'),
        _e('a', '2026-08-19', '今天另一条', Mood.happy),
        _e('old', '2026-08-17', '旧日记', Mood.tired),
      ];
      final d = WidgetService.compute(now, entries);
      expect(d.todayCount, 2);
      expect(d.todayMood, '开心');
      expect(d.latestTitle, '今天的日记');
      expect(d.latestPreview, contains('今天去了公园'));
      expect(d.dateLabel, contains('8月19日'));
    });

    test('空库给出占位数据', () {
      final d = WidgetService.compute(DateTime(2026, 8, 19), const []);
      expect(d.todayCount, 0);
      expect(d.todayMood, '');
      expect(d.latestTitle, '');
      expect(d.latestPreview, '');
    });

    test('isQuickNew 识别写日记入口 URI', () {
      expect(WidgetService.isQuickNew(WidgetService.quickNewUri()), isTrue);
      expect(
          WidgetService.isQuickNew(Uri.parse('mydiary://other')), isFalse);
      expect(WidgetService.isQuickNew(null), isFalse);
    });
  });
}
