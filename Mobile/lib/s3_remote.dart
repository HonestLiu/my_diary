import 'dart:convert';
import 'dart:typed_data';

import 'package:my_diary_mobile/models/sync_types.dart';
import 'package:my_diary_mobile/sync/crypto.dart';
import 'package:my_diary_mobile/sync/remote_storage.dart';
import 'package:http/http.dart' as http;

/// 直接对象存储配置（S3 / R2 / MinIO / 阿里云 OSS 兼容）。
class S3Config {
  /// 含 scheme 的源站 host，例如 "https://s3.us-east-1.amazonaws.com"。
  final String endpoint;
  final String bucket;
  final String region;
  final String accessKey;
  final String secretKey;

  /// Path-style 寻址（MinIO / R2 / OSS）。AWS S3 用 virtual-hosted。
  final bool pathStyle;

  S3Config({
    required this.endpoint,
    required this.bucket,
    required this.region,
    required this.accessKey,
    required this.secretKey,
    required this.pathStyle,
  });
}

String _stripScheme(String host) => host.replaceFirst(RegExp(r'^https?://'), '');

/// 基于 fetch + AWS SigV4 的 S3 兼容客户端。覆盖 AWS S3 / Cloudflare R2 /
/// MinIO / 阿里云 OSS，通过切换 endpoint / region / pathStyle 满足「StorageProvider
/// 抽象」要求，无需引入重型 SDK（与桌面端实现一致）。
class S3StorageProvider implements RemoteStorage {
  @override
  final String name = 's3';

  final S3Config cfg;

  S3StorageProvider(this.cfg);

  ({String url, String host, String path}) _buildUrl(String key) {
    final base = cfg.endpoint.replaceAll(RegExp(r'/+$'), '');
    if (cfg.pathStyle) {
      final path = '/${cfg.bucket}/$key';
      return (url: '$base$path', host: _stripScheme(base), path: path);
    }
    final host = '${cfg.bucket}.${_stripScheme(base)}';
    final path = '/$key';
    return (url: 'https://$host$path', host: host, path: path);
  }

  Map<String, String> _sign({
    required String method,
    required String path,
    String? query,
    Map<String, String>? extraHeaders,
    Uint8List? body,
    String? datetime,
  }) {
    const service = 's3';
    final dt = datetime ?? _amzDate(DateTime.now().toUtc());
    final dateStamp = dt.substring(0, 8);

    final payloadBytes = body ?? Uint8List(0);
    final payloadHash = sha256Hex(payloadBytes);

    final extra = extraHeaders ?? {};
    final host = extra['host'];
    if (host == null) throw StateError('signRequest requires a host header');

    const signedHeaderNames = ['host', 'x-amz-content-sha256', 'x-amz-date'];
    final headersToSign = <String, String>{
      'host': host,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': dt,
      ...extra,
    };

    final canonicalHeaders = signedHeaderNames
        .map((n) => '$n:${(headersToSign[n] ?? '').trim()}\n')
        .join('');
    final signedHeaders = signedHeaderNames.join(';');

    final canonicalUri = _uriEncode(path).replaceAll('%2F', '/');
    final canonicalQuery = query ?? '';
    final canonicalRequest = [
      method.toUpperCase(),
      canonicalUri,
      canonicalQuery,
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');

    final scope = '$dateStamp/${cfg.region}/$service/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      dt,
      scope,
      sha256Hex(utf8.encode(canonicalRequest)),
    ].join('\n');

    var key = Uint8List.fromList(utf8.encode('AWS4${cfg.secretKey}'));
    key = hmacSha256(key, dateStamp);
    key = hmacSha256(key, cfg.region);
    key = hmacSha256(key, service);
    key = hmacSha256(key, 'aws4_request');
    final signature = hmacSha256Hex(key, stringToSign);

    final authorization = 'AWS4-HMAC-SHA256 Credential=${cfg.accessKey}/$scope, '
        'SignedHeaders=$signedHeaders, Signature=$signature';

    return {
      ...extra,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': dt,
      'Authorization': authorization,
    };
  }

  Future<http.Request> _do(
    String method,
    String key, {
    Uint8List? body,
    String? query,
    String? contentType,
  }) async {
    final built = _buildUrl(key);
    final headers = <String, String>{};
    if (contentType != null) headers['content-type'] = contentType;
    final signed = _sign(
      method: method,
      path: built.path,
      query: query,
      extraHeaders: {'host': built.host, ...headers},
      body: body,
    );
    final uri = Uri.parse(built.url + (query != null ? '?$query' : ''));
    return http.Request(method, uri)
      ..headers.addAll(signed)
      ..bodyBytes = body ?? Uint8List(0);
  }

  @override
  Future<void> upload(String remotePath, Uint8List data) async {
    final req = await _do('PUT', remotePath,
        body: data, contentType: 'application/octet-stream');
    final res = await http.Response.fromStream(await req.send());
    if (!res.ok) {
      throw Exception('S3 上传失败 ($remotePath): ${res.statusCode}');
    }
  }

  @override
  Future<Uint8List> download(String remotePath) async {
    final req = await _do('GET', remotePath);
    final res = await http.Response.fromStream(await req.send());
    if (!res.ok) {
      throw Exception('S3 下载失败 ($remotePath): ${res.statusCode}');
    }
    return res.bodyBytes;
  }

  @override
  Future<void> delete(String remotePath) async {
    final req = await _do('DELETE', remotePath);
    final res = await http.Response.fromStream(await req.send());
    if (!res.ok && res.statusCode != 404) {
      throw Exception('S3 删除失败 ($remotePath): ${res.statusCode}');
    }
  }

  @override
  Future<List<String>> list([String prefix = '']) async {
    final query =
        'list-type=2&prefix=${Uri.encodeQueryComponent(prefix, encoding: utf8)}';
    final req = await _do('GET', '', query: query);
    final res = await http.Response.fromStream(await req.send());
    if (!res.ok) throw Exception('S3 列举失败: ${res.statusCode}');
    final xml = res.body;
    final keys = <String>[];
    final re = RegExp(r'<Key>([^<]+)</Key>');
    for (final m in re.allMatches(xml)) {
      keys.add(Uri.decodeComponent(m.group(1)!));
    }
    return keys..sort();
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
    await upload('metadata/sync.json',
        Uint8List.fromList(utf8.encode(jsonEncode(manifest.toJson()))));
  }
}

extension _ResponseStatus on http.Response {
  bool get ok => statusCode >= 200 && statusCode < 300;
}

/// 20210818T140503Z 形式的 AWS 日期。
String _amzDate(DateTime d) {
  final s = d.toIso8601String();
  // 去掉 ':' 与毫秒，再去掉多余的点：2026-08-17T14:58:41.123Z -> 20260817T145841Z
  return s.replaceAll(RegExp(r'[:-]|\.\d{3}'), '').replaceAll('.', '');
}

String _uriEncode(String s) =>
    Uri.encodeComponent(s).replaceAll('%2F', '/');
