import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// SHA-256 / HMAC-SHA256 助手（同步引擎文件指纹 + S3 SigV4 签名）。无原生依赖。
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

Uint8List hmacSha256(Uint8List key, String message) =>
    Uint8List.fromList(Hmac(sha256, key).convert(utf8.encode(message)).bytes);

/// 直接取 Digest 的 toString()（与 sha256Hex 一致，输出 64 位小写 hex）。
/// 注意不能对 Uint8List 调 toString()——它输出的是 "[217, 55, ...]" 这种
/// Dart 列表表示，会生成非法签名导致 S3/MinIO/OSS 全部拒签。
String hmacSha256Hex(Uint8List key, String message) =>
    Hmac(sha256, key).convert(utf8.encode(message)).toString();
