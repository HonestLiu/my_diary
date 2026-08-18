import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';
import 'package:my_diary_mobile/models/settings.dart';
import 'package:my_diary_mobile/repository/journal_repository.dart';
import 'package:my_diary_mobile/models/sync_types.dart';
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
  String? _docsPath; // 应用文档目录（头像等非 vault 文件存放处）
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
    _docsPath = docs.path;
    final vaultRoot = '${docs.path}/my-diary';
    await repo.init(vaultRoot);

    var loaded = await repo.loadSettings();
    // 去掉可能来自桌面端的凭据，避免移动端写回 / 泄露。
    loaded = loaded.copyWith(sync: loaded.sync.copyWith(clearCredentials: true));
    _settings = loaded;

    // 旧版头像（文档目录裸文件）迁移到 vault profile/（2026-08-18 早前方案）。
    await _migrateLegacyAvatar();

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

  /// 切换喜欢标记（轻量元数据更新，不归档历史版本）。
  Future<void> setFavorite(JournalEntry entry, bool fav) async {
    await repo.saveEntry(entry.copyWith(favorite: fav), archive: false);
    await refreshEntries();
  }

  Future<void> deleteEntry(String id) async {
    await repo.deleteEntry(id);
    await refreshEntries();
  }

  Future<List<JournalEntry>> search(String q,
          {Set<SearchScope> filters = const {}}) =>
      repo.search(q, filters: filters);

  Future<void> saveSettings(AppSettings s) async {
    _settings = s;
    await repo.saveSettings(s);
    notifyListeners();
  }

  /// 当前头像文件。新方案：vault 内 `profile/avatar.<ext>`（随备份/同步/还原，
  /// settings.json 存 vault 相对路径）；旧方案兼容：应用文档目录下裸文件名。
  /// 未设置或文件丢失时返回 null。
  File? get avatarFile {
    final ref = _settings.avatar;
    if (ref.isEmpty) return null;
    if (ref.contains('/')) {
      final f = repo.storage.resolveFile(ref);
      return f.existsSync() ? f : null;
    }
    if (_docsPath != null) {
      final f = File('$_docsPath/$ref');
      return f.existsSync() ? f : null;
    }
    return null;
  }

  /// 设置头像：把所选图片写入 vault 的 `profile/`（替换旧文件），
  /// vault 相对路径写入 settings.json —— 导出完整备份 / 导入还原均可完全复原。
  Future<File> setAvatar(File source) async {
    await _deleteAvatarFiles();
    final ext = _safeExtension(
        source.path, source.uri.pathSegments.last, AssetKind.image);
    final rel = profileAvatarPath('avatar$ext');
    await repo.storage.writeBytes(rel, await source.readAsBytes());
    await saveSettings(_settings.copyWith(avatar: rel));
    return repo.storage.resolveFile(rel);
  }

  /// 移除头像（删 vault 文件 + 旧文档目录文件，清 settings.avatar）。
  Future<void> clearAvatar() async {
    await _deleteAvatarFiles();
    await saveSettings(_settings.copyWith(avatar: ''));
  }

  Future<void> _deleteAvatarFiles() async {
    final ref = _settings.avatar;
    if (ref.isEmpty) return;
    try {
      if (ref.contains('/')) {
        final f = repo.storage.resolveFile(ref);
        if (await f.exists()) await f.delete();
      } else if (_docsPath != null) {
        final f = File('$_docsPath/$ref');
        if (await f.exists()) await f.delete();
      }
    } catch (_) {/* 文件不存在等，忽略 */}
  }

  /// 迁移旧版头像（<docs>/<裸文件名>，2026-08-18 早前方案）到 vault `profile/`。
  Future<void> _migrateLegacyAvatar() async {
    final ref = _settings.avatar;
    if (ref.isEmpty || ref.contains('/') || _docsPath == null) return;
    final legacy = File('$_docsPath/$ref');
    if (!await legacy.exists()) return;
    try {
      final rel = profileAvatarPath(
          RegExp(r'\.\w+$').hasMatch(ref) ? ref : 'avatar.png');
      await repo.storage.writeBytes(rel, await legacy.readAsBytes());
      await saveSettings(_settings.copyWith(avatar: rel));
      await legacy.delete();
    } catch (_) {/* 迁移失败保留旧文件，不阻断启动 */}
  }

  /// 设置座右铭（个人主页展示）。
  Future<void> setMotto(String motto) async {
    await saveSettings(_settings.copyWith(motto: motto.trim()));
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
  Future<AssetRef> importImage(File source, {String? name}) =>
      importAsset(source, AssetKind.image, name: name);

  /// 通用资源导入：按 kind 落到 `assets/{images,audio,video,attachments}/`。
  ///
  /// 文件名用 uuid，扩展名沿用原文件（做白名单归一），原始名保存在 AssetRef.name 里，
  /// 与桌面端的 vault 约定一致，两端互通后都能正确显示与播放。
  Future<AssetRef> importAsset(
    File source,
    AssetKind kind, {
    String? name,
  }) async {
    final original = name ?? source.path.split(RegExp(r'[/\\]')).last;
    final ext = _safeExtension(source.path, original, kind);
    final filename = '${const Uuid().v4()}$ext';
    final rel = assetPath(kind, filename);
    final bytes = await source.readAsBytes();
    await repo.storage.writeBytes(rel, bytes);
    return AssetRef(
      kind: kind,
      path: rel,
      name: original,
      size: bytes.length,
    );
  }

  static const Map<AssetKind, List<String>> _knownExtensions = {
    AssetKind.image: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'bmp'],
    AssetKind.audio: ['m4a', 'mp3', 'aac', 'wav', 'ogg', 'flac', 'amr', 'caf'],
    AssetKind.video: ['mp4', 'mov', 'm4v', 'webm', 'mkv', '3gp', 'avi'],
    AssetKind.attachment: [],
  };

  static const Map<AssetKind, String> _fallbackExtensions = {
    AssetKind.image: '.jpg',
    AssetKind.audio: '.m4a',
    AssetKind.video: '.mp4',
    AssetKind.attachment: '',
  };

  String _safeExtension(String path, String original, AssetKind kind) {
    String extOf(String s) {
      final dot = s.lastIndexOf('.');
      if (dot <= 0 || dot == s.length - 1) return '';
      final ext = s.substring(dot + 1).toLowerCase();
      return RegExp(r'^[a-z0-9]{1,8}$').hasMatch(ext) ? ext : '';
    }

    final ext = extOf(original).isNotEmpty ? extOf(original) : extOf(path);
    if (ext.isEmpty) return _fallbackExtensions[kind] ?? '';
    final allow = _knownExtensions[kind] ?? const <String>[];
    if (allow.isEmpty || allow.contains(ext)) return '.$ext';
    return _fallbackExtensions[kind] ?? '.$ext';
  }
}
