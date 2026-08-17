// Integration test for the local-first sync engine.
//
// Uses an in-memory fake RemoteStorage plus a real on-disk LocalVault in a temp
// dir, so we exercise the actual SyncEngine.sync() algorithm — upload, download,
// idempotent re-sync, and conflict detection — without a live S3/cloud backend.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/models/sync_types.dart';
import 'package:my_diary_mobile/repository/journal_repository.dart';
import 'package:my_diary_mobile/sync/remote_storage.dart';
import 'package:my_diary_mobile/sync/sync_engine.dart';
import 'package:my_diary_mobile/vault/local_vault.dart';
import 'package:my_diary_mobile/vault/markdown_codec.dart';

/// In-memory RemoteStorage for driving SyncEngine without a real backend.
class FakeRemoteStorage implements RemoteStorage {
  final Map<String, Uint8List> objects = {};
  SyncManifest? manifest;

  @override
  String get name => 'fake';

  @override
  Future<void> upload(String remotePath, Uint8List data) async {
    objects[remotePath] = Uint8List.fromList(data);
  }

  @override
  Future<Uint8List> download(String remotePath) async {
    final d = objects[remotePath];
    if (d == null) throw StateError('not found: $remotePath');
    return Uint8List.fromList(d);
  }

  @override
  Future<void> delete(String remotePath) async {
    objects.remove(remotePath);
  }

  @override
  Future<List<String>> list([String prefix = '']) async {
    return objects.keys
        .where((k) => prefix.isEmpty || k.startsWith(prefix))
        .toList()
      ..sort();
  }

  @override
  Future<SyncManifest?> fetchManifest() async => manifest;

  @override
  Future<void> pushManifest(SyncManifest m) async {
    manifest = m;
  }
}

JournalEntry _sample(String id, String body) => JournalEntry(
      id: id,
      date: '2026-08-17',
      title: '同步测试 $id',
      mood: Mood.calm,
      weather: Weather.sunny,
      tags: const [],
      assets: const [],
      createdAt: '2026-08-17T10:00:00.000Z',
      updatedAt: '2026-08-17T10:00:00.000Z',
      body: body,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalVault vault;
  late FakeRemoteStorage remote;
  late String vaultRoot;

  setUp(() async {
    // dart:io temp dir works on the host runner (path_provider needs a device).
    vaultRoot = Directory.systemTemp.createTempSync('sync_test_').path;
    vault = LocalVault(vaultRoot);
    await vault.init();
    remote = FakeRemoteStorage();
  });

  tearDown(() async {
    final d = Directory(vaultRoot);
    if (await d.exists()) await d.delete(recursive: true);
  });

  Future<JournalRepository> _repo() async {
    final repo = JournalRepository(vault);
    await repo.init(vault.root);
    return repo;
  }

  test('first sync uploads local entries to remote', () async {
    final repo = await _repo();
    await repo.saveEntry(_sample('e1', '本地内容'));

    final engine = SyncEngine(vault, remote, 'mobile');
    final res = await engine.sync();

    expect(res.uploaded,
        contains('entries/2026/08/2026-08-17-e1.md'));
    expect(remote.objects,
        contains('entries/2026/08/2026-08-17-e1.md'));
    expect(remote.manifest, isNotNull);
  });

  test('re-sync with no local changes is a no-op', () async {
    final repo = await _repo();
    await repo.saveEntry(_sample('e1', '本地内容'));
    final engine = SyncEngine(vault, remote, 'mobile');
    await engine.sync();

    final res2 = await engine.sync();
    expect(res2.uploaded, isEmpty);
    expect(res2.downloaded, isEmpty);
    expect(res2.conflicts, isEmpty);
  });

  test('remote-only entry is downloaded locally', () async {
    // Seed remote with an entry this device has never seen.
    final raw = serializeEntryFile(_sample('remote1', '来自桌面端'));
    remote.objects['entries/2026/08/2026-08-17-remote1.md'] =
        Uint8List.fromList(raw.codeUnits);
    remote.manifest = SyncManifest(
      deviceId: 'desktop',
      files: [
        SyncFile(
          path: 'entries/2026/08/2026-08-17-remote1.md',
          hash: 'ignored',
          size: raw.length,
          updated: 1,
        ),
      ],
      generatedAt: 1,
    );

    final engine = SyncEngine(vault, remote, 'mobile');
    final res = await engine.sync();

    expect(res.downloaded,
        contains('entries/2026/08/2026-08-17-remote1.md'));
    expect(
        await vault.exists('entries/2026/08/2026-08-17-remote1.md'), isTrue);
  });

  test('concurrent edits on both sides produce a conflict, never a silent overwrite',
      () async {
    final repo = await _repo();
    await repo.saveEntry(_sample('e1', '原始内容'));
    final engine = SyncEngine(vault, remote, 'mobile');
    await engine.sync(); // establishes baseline on both sides

    // Local edits the entry.
    await repo.saveEntry(_sample('e1', '本地修改'));

    // Remote independently edits the same file (simulating the desktop).
    final rawRemote = serializeEntryFile(_sample('e1', '远程修改'));
    remote.objects['entries/2026/08/2026-08-17-e1.md'] =
        Uint8List.fromList(rawRemote.codeUnits);
    remote.manifest = SyncManifest(
      deviceId: 'desktop',
      files: [
        SyncFile(
          path: 'entries/2026/08/2026-08-17-e1.md',
          hash: 'remotehash',
          size: rawRemote.length,
          updated: 2,
        ),
      ],
      generatedAt: 2,
    );

    final res = await engine.sync();
    expect(res.conflicts, hasLength(1));
    expect(await vault.exists('conflicts/2026-08-17-e1.local.md'), isTrue);
    expect(await vault.exists('conflicts/2026-08-17-e1.remote.md'), isTrue);
  });
}
