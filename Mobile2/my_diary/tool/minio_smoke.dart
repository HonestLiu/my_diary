// 临时冒烟测试：用与 App 完全相同的 S3StorageProvider 代码路径，
// 直连本地 MinIO 验证签名 / 上传 / 列举 / 下载 / 清单全链路。
//
// 用法：dart run tool/minio_smoke.dart
//
// 可选环境变量覆盖：
//   MINIO_ENDPOINT / MINIO_BUCKET / MINIO_ACCESS / MINIO_SECRET

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:my_diary_mobile/models/sync_types.dart';
import 'package:my_diary_mobile/s3_remote.dart';

const _endpoint = 'http://127.0.0.1:9000';
const _bucket = 'my-files';
const _access = 'admin';
const _secret = 'your-strong-password';

void main() async {
  final endpoint = Platform.environment['MINIO_ENDPOINT'] ?? _endpoint;
  final bucket = Platform.environment['MINIO_BUCKET'] ?? _bucket;
  final access = Platform.environment['MINIO_ACCESS'] ?? _access;
  final secret = Platform.environment['MINIO_SECRET'] ?? _secret;

  // 与 lib/sync/sync_engine.dart buildRemoteStorage 一致的配置解析：
  // MinIO 自动 path-style、Region 留空走 us-east-1。
  final cfg = SyncConfig(
    provider: SyncProvider.minio,
    endpoint: endpoint,
    bucket: bucket,
  );
  final provider = S3StorageProvider(S3Config(
    endpoint: endpoint,
    bucket: bucket,
    region: cfg.effectiveRegion(),
    accessKey: access,
    secretKey: secret,
    pathStyle: cfg.effectivePathStyle(),
  ));
  print('endpoint=$endpoint bucket=$bucket region=${cfg.effectiveRegion()} '
      'pathStyle=${cfg.effectivePathStyle()}');

  var ok = true;
  Future<void> step(String name, Future<void> Function() fn) async {
    try {
      await fn();
      print('  [OK] $name');
    } catch (e) {
      ok = false;
      print('  [FAIL] $name -> $e');
    }
  }

  final key = 'smoke-test/hello.txt';
  final body = Uint8List.fromList(utf8.encode('minio smoke ${DateTime.now()}'));

  await step('upload $key', () => provider.upload(key, body));
  await step('list (prefix smoke-test/)',
      () async => print('       keys=${await provider.list('smoke-test/')}'));
  await step('download + 内容一致', () async {
    final got = await provider.download(key);
    if (utf8.decode(got) != utf8.decode(body)) {
      throw StateError('下载内容不一致');
    }
  });
  await step('fetchManifest（清掉残留后应返回 null）', () async {
    // 上次运行可能已推送过清单，先删掉再断言，保证脚本可重复跑。
    try {
      await provider.delete('metadata/sync.json');
    } catch (_) {/* 不存在则忽略 */}
    final m = await provider.fetchManifest();
    if (m != null) throw StateError('预期 null，实际有清单');
  });
  await step('pushManifest + fetchManifest 回读', () async {
    final m = SyncManifest(
      deviceId: 'smoke',
      files: [
        SyncFile(
          path: key,
          hash: 'abc',
          size: body.length,
          updated: 1,
        ),
      ],
      generatedAt: 1,
    );
    await provider.pushManifest(m);
    final back = await provider.fetchManifest();
    if (back == null || back.files.single.path != key) {
      throw StateError('清单回读失败: $back');
    }
  });
  await step('delete $key', () => provider.delete(key));

  // 收尾清理：删掉本次推送的清单，避免污染真实桶。
  try {
    await provider.delete('metadata/sync.json');
  } catch (_) {/* 忽略 */}

  print(ok ? '\n全部通过 ✔' : '\n存在失败 ✘');
  exit(ok ? 0 : 1);
}
