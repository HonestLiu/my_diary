// S3StorageProvider（SigV4）回归测试。
//
// 用本地 HttpServer 扮演 MinIO，验证：
//   1. 每次请求的 x-amz-date 是合法的 16 位 AWS 日期（YYYYMMDDTHHMMSSZ）。
//      曾因 DateTime.toIso8601String() 带微秒而被 `\.\d{3}` 截断成
//      19 位非法日期，导致 minIO 拒签、同步完全不可用。
//   2. 上传 → 列举 → 下载 全链路可用。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:my_diary_mobile/models/sync_types.dart';
import 'package:my_diary_mobile/s3_remote.dart';
import 'package:my_diary_mobile/sync/crypto.dart';

final _amzDateRe = RegExp(r'^\d{8}T\d{6}Z$');

/// 服务端 SigV4 验签（镜像 S3/MinIO 的逻辑），防止签名类 bug 逃过单测。
///
/// 签名用独立的正确实现（crypto.Hmac 直接算 hex），不依赖被测代码的
/// hmacSha256Hex —— 否则两侧同坏会互相匹配、掩盖问题。校验失败返回错误
/// 描述，成功返回 null。
String? _verifySigV4(HttpRequest req, String secretKey) {
  final auth = req.headers.value('authorization');
  if (auth == null) return 'missing Authorization';
  final m = RegExp(
          r'^AWS4-HMAC-SHA256 Credential=([^/]+)/(\d{8})/([^/]+)/([^/]+)/aws4_request, '
          r'SignedHeaders=([^,]+), Signature=([0-9a-f]+)$')
      .firstMatch(auth.trim());
  if (m == null) return 'bad Authorization: $auth';
  final dateStamp = m.group(2)!;
  final region = m.group(3)!;
  final service = m.group(4)!;
  final signedHeaders = m.group(5)!.split(';');
  final expectedSig = m.group(6)!;

  final dt = req.headers.value('x-amz-date') ?? '';
  final payloadHash = req.headers.value('x-amz-content-sha256') ?? '';
  if (!_amzDateRe.hasMatch(dt)) return 'bad x-amz-date: $dt';

  final canonicalHeaders = signedHeaders
      .map((n) => '$n:${(req.headers.value(n) ?? '').trim()}\n')
      .join();
  final canonicalRequest = [
    req.method,
    req.uri.path,
    req.uri.query,
    canonicalHeaders,
    signedHeaders.join(';'),
    payloadHash,
  ].join('\n');
  final scope = '$dateStamp/$region/$service/aws4_request';
  final stringToSign = [
    'AWS4-HMAC-SHA256',
    dt,
    scope,
    sha256Hex(utf8.encode(canonicalRequest)),
  ].join('\n');

  var key = Uint8List.fromList(utf8.encode('AWS4$secretKey'));
  key = hmacSha256(key, dateStamp);
  key = hmacSha256(key, region);
  key = hmacSha256(key, service);
  key = hmacSha256(key, 'aws4_request');
  final actual = crypto.Hmac(crypto.sha256, key)
      .convert(utf8.encode(stringToSign))
      .bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  if (actual != expectedSig) {
    return 'SignatureDoesNotMatch ${expectedSig.substring(0, 8)}… '
        '!= ${actual.substring(0, 8)}…';
  }
  return null;
}

void main() {
  late HttpServer server;
  late int port;
  final objects = <String, Uint8List>{};
  final receivedDates = <String>[];
  final receivedPayloadHashes = <String>[];
  final receivedQueries = <String>[];

  setUp(() async {
    objects.clear();
    receivedDates.clear();
    receivedPayloadHashes.clear();
    receivedQueries.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((req) async {
      receivedDates.add(req.headers.value('x-amz-date') ?? '');
      receivedPayloadHashes
          .add(req.headers.value('x-amz-content-sha256') ?? '');
      receivedQueries.add(req.uri.query);
      // 验签：签名非法直接 403，与真实 S3/MinIO 一致。
      final sigError = _verifySigV4(req, 'minioadmin');
      if (sigError != null) {
        req.response.statusCode = 403;
        req.response.write('<Error><Code>SignatureDoesNotMatch</Code>'
            '<Message>$sigError</Message></Error>');
        await req.response.close();
        return;
      }
      // 与真实 S3/MinIO 一致：key 相对 bucket（去掉 /test-bucket/ 前缀）。
      final path = req.uri.path;
      final key = path.startsWith('/test-bucket/')
          ? path.substring('/test-bucket/'.length)
          : path;
      if (req.method == 'PUT') {
        final data = await req.fold<BytesBuilder>(BytesBuilder(),
            (b, c) => b..add(c));
        objects[key] = data.takeBytes();
        req.response.statusCode = 200;
      } else if (req.method == 'GET') {
        // ListObjectsV1：带 prefix 查询参数即列举请求（无 list-type=2）。
        if (req.uri.queryParameters.containsKey('prefix')) {
          final keys = objects.keys.map((k) => '<Key>$k</Key>').join();
          req.response.headers.contentType =
              ContentType('application', 'xml');
          req.response.write(
              '<ListBucketResult><Contents>$keys</Contents></ListBucketResult>');
        } else if (objects.containsKey(key)) {
          req.response.add(objects[key]!);
        } else {
          req.response.statusCode = 404;
        }
      } else {
        req.response.statusCode = 200;
      }
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  S3StorageProvider provider() => S3StorageProvider(S3Config(
        endpoint: 'http://127.0.0.1:$port',
        bucket: 'test-bucket',
        region: 'us-east-1',
        accessKey: 'minioadmin',
        secretKey: 'minioadmin',
        pathStyle: true,
      ));

  test('x-amz-date 是合法的 16 位 AWS 日期，且签名头完整', () async {
    await provider().upload(
        'entries/2026/08/2026-08-17-e1.md',
        Uint8List.fromList(utf8.encode('本地内容')));
    expect(receivedDates, hasLength(1));
    expect(receivedDates.single, matches(_amzDateRe));
  });

  test('payload 校验头用 UNSIGNED-PAYLOAD（阿里云 OSS 兼容，避免 403）', () async {
    await provider().upload(
        'entries/a.md', Uint8List.fromList(utf8.encode('hello')));
    expect(receivedPayloadHashes.single, 'UNSIGNED-PAYLOAD');
  });

  test('上传 → 列举 → 下载 全链路可用', () async {
    final p = provider();
    final data = Uint8List.fromList(utf8.encode('hello minio'));
    await p.upload('entries/a.md', data);

    final keys = await p.list('entries/');
    expect(keys, contains('entries/a.md'));
    for (final d in receivedDates) {
      expect(d, matches(_amzDateRe));
    }
    // 阿里云 OSS 不支持 ListObjectsV2：列举请求必须不带 list-type=2。
    final listQuery = receivedQueries[1];
    expect(listQuery.startsWith('prefix='), isTrue);
    expect(listQuery.contains('list-type'), isFalse);

    final back = await p.download('entries/a.md');
    expect(utf8.decode(back), 'hello minio');
  });

  test('fetchManifest 在远端不存在时返回 null', () async {
    final p = provider();
    expect(await p.fetchManifest(), isNull);
  });

  group('effectivePathStyle', () {
    SyncConfig cfg(
            {SyncProvider p = SyncProvider.s3,
            String? endpoint,
            bool? ps,
            String? region}) =>
        SyncConfig(
          provider: p,
          endpoint: endpoint,
          pathStyle: ps,
          region: region,
        );

    test('MinIO 默认开启 path-style，避免解析 bucket.<endpoint>', () {
      expect(cfg(p: SyncProvider.minio, endpoint: 'http://192.168.1.5:9000')
          .effectivePathStyle(), isTrue);
      expect(cfg(p: SyncProvider.minio, endpoint: 'http://minio.local:9000')
          .effectivePathStyle(), isTrue);
    });

    test('显式配置的 pathStyle 优先于默认', () {
      expect(
          cfg(p: SyncProvider.minio, endpoint: 'http://minio:9000', ps: false)
              .effectivePathStyle(),
          isFalse);
    });

    test('S3 + IP / localhost 端点必须 path-style，域名端点默认 virtual-hosted',
        () {
      expect(cfg(endpoint: 'http://192.168.1.5:9000').effectivePathStyle(),
          isTrue);
      expect(cfg(endpoint: 'http://localhost:9000').effectivePathStyle(),
          isTrue);
      expect(cfg(endpoint: 'https://s3.us-east-1.amazonaws.com')
          .effectivePathStyle(), isFalse);
    });

    test('OSS 默认开启 path-style', () {
      expect(
          cfg(p: SyncProvider.oss,
              endpoint: 'https://oss-cn-hangzhou.aliyuncs.com')
              .effectivePathStyle(),
          isTrue);
    });

    test('OSS region 从 Endpoint 自动推导，避免 us-east-1 被拒签', () {
      expect(
          cfg(p: SyncProvider.oss, endpoint: 'https://oss-cn-hangzhou.aliyuncs.com')
              .effectiveRegion(),
          'oss-cn-hangzhou');
      expect(
          cfg(p: SyncProvider.oss,
              endpoint: 'https://my-bucket.oss-ap-southeast-1.aliyuncs.com')
              .effectiveRegion(),
          'oss-ap-southeast-1');
    });

    test('OSS 显式 region 优先；其余提供者留空按 us-east-1', () {
      expect(
          cfg(p: SyncProvider.oss,
                  endpoint: 'https://oss-cn-shanghai.aliyuncs.com',
                  region: 'oss-cn-beijing')
              .effectiveRegion(),
          'oss-cn-beijing');
      expect(cfg(p: SyncProvider.minio, endpoint: 'http://minio:9000')
          .effectiveRegion(), 'us-east-1');
      expect(cfg(p: SyncProvider.s3, endpoint: 'https://s3.amazonaws.com')
          .effectiveRegion(), 'us-east-1');
    });
  });
}
