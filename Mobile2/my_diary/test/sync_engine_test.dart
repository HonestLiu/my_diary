// Integration test for the local-first sync engine.
//
// Uses an in-memory fake RemoteStorage plus a real on-disk LocalVault in a temp
// dir, so we exercise the actual SyncEngine.sync() algorithm — upload, download,
// idempotent re-sync, and conflict detection — without a live S3/cloud backend.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/models/sync_types.dart';
import 'package:my_diary_mobile/repository/journal_repository.dart';
import 'package:my_diary_mobile/sync/remote_storage.dart';
import 'package:my_diary_mobile/sync/crypto.dart';
import 'package:my_diary_mobile/sync/sync_engine.dart';
import 'package:my_diary_mobile/vault/local_vault.dart';
import 'package:my_diary_mobile/vault/markdown_codec.dart';
import 'package:my_diary_mobile/vault/vault_layout.dart';

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

  test('large vault (isolate hash path) uploads all entries', () async {
    final repo = await _repo();
    for (var i = 0; i < 25; i++) {
      await repo.saveEntry(_sample('iso$i', '正文 $i'));
    }

    final engine = SyncEngine(vault, remote, 'mobile');
    final res = await engine.sync();

    // 25 个条目超过哈希 isolate 阈值（20），走后台 isolate 路径；全部应上传。
    expect(res.uploaded, hasLength(25));
    expect(res.errors, isEmpty);
    expect(remote.objects, hasLength(25));
  });

  test('asset hash cache: 未变化复用、变化后重算', () async {
    final repo = await _repo();
    await repo.saveEntry(_sample('c1', '正文'));
    await vault.writeBytes(
        'assets/images/a1.jpg', Uint8List.fromList([1, 2, 3, 4]));

    final engine = SyncEngine(vault, remote, 'mobile');
    final m1 = await engine.buildLocalManifest();
    final assetPath = 'assets/images/a1.jpg';
    final h1 = m1.files.firstWhere((f) => f.path == assetPath).hash;
    // 本地哈希缓存文件已生成，且包含该资产。
    expect(await vault.exists(VaultLayout.hashCache), isTrue);
    final cacheRaw = await vault.readText(VaultLayout.hashCache);
    expect(cacheRaw, contains(assetPath));

    // 无变化再次构建：资产命中缓存，哈希保持一致。
    final m2 = await engine.buildLocalManifest();
    expect(
      m2.files.firstWhere((f) => f.path == assetPath).hash,
      h1,
    );

    // 原地改写资产（size 变化）→ mtime/size 不再匹配，重新哈希出新值。
    await vault.writeBytes(
        'assets/images/a1.jpg', Uint8List.fromList([9, 9, 9, 9, 9]));
    final m3 = await engine.buildLocalManifest();
    expect(
      m3.files.firstWhere((f) => f.path == assetPath).hash,
      isNot(h1),
    );
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

  test('unsyncedPaths: 无基线未同步 → 同步后清空 → 改动后重新出现', () async {
    final repo = await _repo();
    await repo.saveEntry(_sample('u1', '正文'));

    final engine = SyncEngine(vault, remote, 'mobile');
    const path = 'entries/2026/08/2026-08-17-u1.md';

    // 尚未同步：无基线 → 该条目未同步。
    expect(await engine.unsyncedPaths(), contains(path));

    // 模拟一次成功同步：把当前本地清单写为基线 → 全部已同步。
    await engine.writeLocalBaseline(await engine.buildLocalManifest());
    expect(await engine.unsyncedPaths(), isNot(contains(path)));

    // 本地改动后 → 重新标记未同步。
    await repo.saveEntry(_sample('u1', '改动后的正文'));
    expect(await engine.unsyncedPaths(), contains(path));
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

  test('首次同步（无基线）两侧内容不同 → 采纳远端，不批量判冲突', () async {
    // 本地已有一条同 id 但内容不同的条目；远端也有一条。设备从未同步过（无基线）。
    final repo = await _repo();
    await repo.saveEntry(_sample('e1', '本地内容'));
    const path = 'entries/2026/08/2026-08-17-e1.md';
    final rawRemote = serializeEntryFile(_sample('e1', '远端内容'));
    remote.objects[path] = Uint8List.fromList(utf8.encode(rawRemote));
    remote.manifest = SyncManifest(
      deviceId: 'desktop',
      files: [
        SyncFile(path: path, hash: 'ignored', size: rawRemote.length, updated: 1),
      ],
      generatedAt: 1,
    );

    final engine = SyncEngine(vault, remote, 'mobile');
    final res = await engine.sync();

    // 不产生任何冲突；以远端为准下载。
    expect(res.conflicts, isEmpty);
    expect(res.downloaded, contains(path));
    // 本地版本保留为安全副本（.replaced，不进入待解决列表）。
    expect(await vault.exists('conflicts/2026-08-17-e1.replaced.md'), isTrue);
    expect((await vault.readText(path)).contains('远端内容'), isTrue);
  });

  test('只有一侧编辑 → 上传/下载，绝不误报冲突', () async {
    final repo = await _repo();
    await repo.saveEntry(_sample('e1', '原始内容'));
    const path = 'entries/2026/08/2026-08-17-e1.md';
    final engine = SyncEngine(vault, remote, 'mobile');
    await engine.sync(); // 建立基线

    // 仅本地编辑 → 上传，无冲突。
    await repo.saveEntry(_sample('e1', '本地修改'));
    final res1 = await engine.sync();
    expect(res1.conflicts, isEmpty);
    expect(res1.uploaded, contains(path));

    // 仅远端编辑（模拟桌面端）→ 下载，无冲突。
    final rawRemote = serializeEntryFile(_sample('e1', '远端修改'));
    remote.objects[path] = Uint8List.fromList(utf8.encode(rawRemote));
    remote.manifest = SyncManifest(
      deviceId: 'desktop',
      files: [
        SyncFile(path: path, hash: sha256Hex(utf8.encode(rawRemote)),
            size: rawRemote.length, updated: 2),
      ],
      generatedAt: 2,
    );
    final res2 = await engine.sync();
    expect(res2.conflicts, isEmpty);
    expect(res2.downloaded, contains(path));
    expect((await vault.readText(path)).contains('远端修改'), isTrue);
  });

  test('冲突保持待解决，不被自动覆盖；解决后不再复发', () async {
    final repo = await _repo();
    await repo.saveEntry(_sample('e1', '原始内容'));
    const path = 'entries/2026/08/2026-08-17-e1.md';
    final engine = SyncEngine(vault, remote, 'mobile');
    await engine.sync(); // 建立基线

    // 两侧同时编辑 → 冲突。
    await repo.saveEntry(_sample('e1', '本地修改'));
    final rawRemote = serializeEntryFile(_sample('e1', '远端修改'));
    remote.objects[path] = Uint8List.fromList(rawRemote.codeUnits);
    remote.manifest = SyncManifest(
      deviceId: 'desktop',
      files: [
        SyncFile(path: path, hash: 'remotehash',
            size: rawRemote.length, updated: 2),
      ],
      generatedAt: 2,
    );
    final res1 = await engine.sync();
    expect(res1.conflicts, hasLength(1));

    // 未解决前再次同步：不得把本地较新的编辑覆盖成远端。
    final res2 = await engine.sync();
    expect(res2.conflicts, isEmpty); // 不重复上报
    expect(res2.downloaded, isNot(contains(path)));
    expect((await vault.readText(path)).contains('本地修改'), isTrue);
    expect(await vault.exists('conflicts/2026-08-17-e1.local.md'), isTrue);

    // 用户选择「保留本地」→ 解决；再次同步不再出现冲突，也不会把文件改回去。
    await engine.resolveConflict(path, ConflictResolution.local);
    final res3 = await engine.sync();
    expect(res3.conflicts, isEmpty);
    expect(res3.downloaded, isNot(contains(path)));
    expect((await vault.readText(path)).contains('本地修改'), isTrue);
    expect(await vault.exists('conflicts/2026-08-17-e1.local.md'), isFalse);
  });
}
