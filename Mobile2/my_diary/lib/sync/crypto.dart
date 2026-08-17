import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// SHA-256 / HMAC-SHA256 助手（同步引擎文件指纹 + S3 SigV4 签名）。无原生依赖。
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

Uint8List hmacSha256(Uint8List key, String message) =>
    Uint8List.fromList(Hmac(sha256, key).convert(utf8.encode(message)).bytes);

String hmacSha256Hex(Uint8List key, String message) =>
    hmacSha256(key, message).toString();
