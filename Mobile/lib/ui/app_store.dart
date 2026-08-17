import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/models/settings.dart';
import 'package:my_diary_mobile/models/sync_types.dart';
import 'package:my_diary_mobile/repository/journal_repository.dart';
import 'package:my_diary_mobile/repository/version.dart';
import 'package:my_diary_mobile/sync/auth_service.dart';
import 'package:my_diary_mobile/sync/sync_engine.dart';
import 'package:my_diary_mobile/vault/vault_layout.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 全局状态：聚合仓储、鉴权与同步，供 UI 消费。
class AppStore extends ChangeNotifier {
  final AuthService auth;
  final SharedPreferences prefs;
  final JournalRepository repo;

  AppSettings _settings = defaultSettings;
  List<JournalEntry> _entries = [];
  bool _initialized = false;
  bool _busy = false;
  String _deviceId = 'mobile';
  SyncResult? _lastSync;
  String? _syncError;
  DateTime? _lastSyncAt;

  AppStore({
    required this.auth,
    required this.prefs,
    required this.repo,
  });

  AppSettings get settings => _settings;
  List<JournalEntry> get entries => _entries;
  bool get initialized => _initialized;
  bool get busy => _busy;
  SyncResult? get lastSync => _lastSync;
  String? get syncError => _syncError;
  DateTime? get lastSyncAt => _lastSyncAt;
  String get deviceId => _deviceId;

  /// 当前待解决的冲突（本地冲突副本存在即视为待处理）。返回条目文件相对路径。
  Future<List<String>> pendingConflictPaths() async {
    final files = await repo.storage.list('conflicts/');
    final bases = <String>{};
    for (final f in files) {
      final m = RegExp(r'conflicts/([^/]+)\.local\.md$').firstMatch(f);
      if (m != null) bases.add(m.group(1)!);
    }
    return bases.map((base) {
      final dm = RegExp(r'(\d{4})-(\d{2})-\d{2}-').firstMatch(base);
      if (dm != null) return 'entries/${dm.group(1)}/${dm.group(2)}/$base.md';
      return 'entries/$base.md';
    }).toList();
  }

  Future<void> init() async {
    _deviceId = prefs.getString('local_device_id') ?? const Uuid().v4();
    await prefs.setString('local_device_id', _deviceId);

    final docs = await getApplicationDocumentsDirectory();
    final vaultRoot = '${docs.path}/my-diary';
    await repo.init(vaultRoot);

    var loaded = await repo.loadSettings();
    // 去掉可能来自桌面端的凭据，避免移动端写回 / 泄露。
    loaded = loaded.copyWith(sync: loaded.sync.copyWith(clearCredentials: true));
    _settings = loaded;

    await refreshEntries();
    _initialized = true;
    notifyListeners();
  }

  Future<void> refreshEntries() async {
    _entries = await repo.listEntries();
    notifyListeners();
  }

  Future<void> saveEntry(JournalEntry entry) async {
    await repo.saveEntry(entry);
    await refreshEntries();
  }

  Future<void> deleteEntry(String id) async {
    await repo.deleteEntry(id);
    await refreshEntries();
  }

  Future<List<JournalEntry>> search(String q) => repo.search(q);

  Future<void> saveSettings(AppSettings s) async {
    _settings = s;
    await repo.saveSettings(s);
    notifyListeners();
  }

  /// 立即同步（上传 / 下载 / 冲突检测）。
  Future<void> syncNow() async {
    if (_busy) return;
    _busy = true;
    _syncError = null;
    notifyListeners();
    try {
      final remote = buildRemoteStorage(_settings.sync, auth);
      final engine = SyncEngine(repo.storage, remote, _deviceId);
      final res = await engine.sync();
      _lastSync = res;
      _lastSyncAt = DateTime.now();
      await refreshEntries();
    } catch (e) {
      _syncError = e.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> resolveConflict(String path, ConflictResolution r) async {
    final remote = buildRemoteStorage(_settings.sync, auth);
    final engine = SyncEngine(repo.storage, remote, _deviceId);
    await engine.resolveConflict(path, r);
    await refreshEntries();
    notifyListeners();
  }

  /// 读取某条目的全部历史版本（最新在前），附带版本号。
  Future<List<({int version, JournalEntry entry})>> entryVersions(
      JournalEntry e) async {
    final vs = await repo.listVersions(e);
    final out = <({int version, JournalEntry entry})>[];
    for (final v in vs) {
      final ver = await readVersion(repo.storage, e.id, v);
      if (ver != null) out.add((version: v, entry: ver));
    }
    return out.reversed.toList();
  }

  /// 解析附件为本地文件（供 Image.file 渲染）。
  File resolveAsset(String relPath) => repo.storage.resolveFile(relPath);

  /// 将选中的图片存入 vault 的 assets/images，返回 AssetRef。
  Future<AssetRef> importImage(File source, {String? name}) async {
    final ext = source.path.split('.').last.toLowerCase();
    final safeExt = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic']
            .contains(ext)
        ? ext
        : 'jpg';
    final filename = '${const Uuid().v4()}.$safeExt';
    final rel = assetPath(AssetKind.image, filename);
    final bytes = await source.readAsBytes();
    await repo.storage.writeBytes(rel, bytes);
    return AssetRef(
      kind: AssetKind.image,
      path: rel,
      name: name ?? source.path.split('/').last,
      size: bytes.length,
    );
  }
}
