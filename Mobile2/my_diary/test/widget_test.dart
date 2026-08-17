// Unit tests for the mobile diary's data-interchange contract.
//
// The whole point of the mobile app is to share diary data with the desktop
// (Tauri) app through an open format: Markdown body + YAML frontmatter on disk,
// plus SHA-256 file fingerprints for sync. These tests pin that contract so the
// two sides stay compatible.

import 'package:flutter_test/flutter_test.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/sync/crypto.dart';
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
  });
}
