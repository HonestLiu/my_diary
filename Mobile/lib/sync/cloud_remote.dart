import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:my_diary_mobile/models/sync_types.dart';
import 'package:my_diary_mobile/sync/auth_service.dart';
import 'package:my_diary_mobile/sync/remote_storage.dart';

/// 通过云服务（FastAPI 预签名中枢）访问对象存储的远程存储实现。
///
/// 云服务的核心契约：**永不接收或存储日记正文**——它只签发短期、用户命名空间内的
/// 预签名 URL，并登记同步元数据。本实现：
///   - 用 `X-Sync-Token` 鉴权
///   - 请求 presign（op=upload→PUT / op=download→GET）
///   - 直接用返回的 URL 上传/下载正文到对象存储
///
/// 与桌面端 `cloud/app/routers/sync.py` 的 `/sync/presign` 完全一致。
class CloudServiceRemote implements RemoteStorage {
  @override
  final String name = 'cloud';

  final AuthService auth;

  CloudServiceRemote(this.auth);

  String get _base {
    final b = auth.baseUrl;
    if (b == null) throw StateError('未配置云服务地址');
    return b;
  }

  String get _token {
    final t = auth.syncToken;
    if (t == null) throw StateError('未登录或缺少同步令牌');
    return t;
  }

  Future<Map<String, ({String url, String method})>> _presign(
    List<String> keys,
    String op,
  ) async {
    final resp = await http.post(
      Uri.parse('$_base/sync/presign'),
      headers: {
        'x-sync-token': _token,
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'keys': keys,
        'op': op,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('预签名失败 (${resp.statusCode}): ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final items = (data['items'] as List).cast<Map<String, dynamic>>();
    final map = <String, ({String url, String method})>{};
    for (final it in items) {
      map[it['key'] as String] =
          (url: it['url'] as String, method: it['method'] as String);
    }
    return map;
  }

  @override
  Future<void> upload(String remotePath, Uint8List data) async {
    final map = await _presign([remotePath], 'upload');
    final item = map[remotePath];
    if (item == null) throw Exception('未获得上传预签名: $remotePath');
    final res = await http.put(
      Uri.parse(item.url),
      headers: {'content-type': 'application/octet-stream'},
      body: data,
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('云上传失败 ($remotePath): ${res.statusCode}');
    }
  }

  @override
  Future<Uint8List> download(String remotePath) async {
    final map = await _presign([remotePath], 'download');
    final item = map[remotePath];
    if (item == null) throw Exception('未获得下载预签名: $remotePath');
    final res = await http.get(Uri.parse(item.url));
    if (res.statusCode != 200) {
      throw Exception('云下载失败 ($remotePath): ${res.statusCode}');
    }
    return res.bodyBytes;
  }

  @override
  Future<void> delete(String remotePath) async {
    // 云服务的 presign 仅支持 upload/download，不签发 DELETE。
    // 同步引擎在正常流程中不会删除远程对象，故此处为安全空实现。
  }

  @override
  Future<List<String>> list([String prefix = '']) async {
    // 云服务无 list 端点：以远程清单的文件集合作为已知对象集合。
    final m = await fetchManifest();
    if (m == null) return [];
    if (prefix.isEmpty) return m.files.map((f) => f.path).toList();
    return m.files
        .where((f) => f.path.startsWith(prefix))
        .map((f) => f.path)
        .toList();
  }

  @override
  Future<SyncManifest?> fetchManifest() async {
    try {
      final data = await download('metadata/sync.json');
      return SyncManifest.fromJson(
          jsonDecode(utf8.decode(data)) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> pushManifest(SyncManifest manifest) async {
    await upload(
      'metadata/sync.json',
      Uint8List.fromList(utf8.encode(jsonEncode(manifest.toJson()))),
    );
  }

  /// 记录一次同步日志（元数据，不含内容）。可选。
  Future<void> recordLog({
    required int filesCount,
    required int bytesCount,
    required int conflictsCount,
    String action = 'sync',
  }) async {
    try {
      await http.post(
        Uri.parse('$_base/sync/logs'),
        headers: {
          'x-sync-token': _token,
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'action': action,
          'files_count': filesCount,
          'bytes_count': bytesCount,
          'conflicts_count': conflictsCount,
        }),
      );
    } catch (_) {
      // 日志失败不影响同步结果
    }
  }
}
