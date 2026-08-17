import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 云服务鉴权 + 设备同步令牌管理。
///
/// 与桌面端 `cloud/app` 的契约一致：
///   - POST /auth/register|login → {access_token, refresh_token}
///   - POST /auth/devices（Bearer access_token）→ {id, name, sync_token}
///     同步令牌仅返回一次，由本服务持久化在安全本地存储中。
///   - 同步请求携带请求头 `X-Sync-Token: <sync_token>`。
///
/// 同时承担「凭据保险箱」职责：直接对象存储的秘钥、云服务令牌均存于本地
/// （MVP 用 shared_preferences；生产环境建议替换为 flutter_secure_storage）。
class AuthService extends ChangeNotifier {
  final SharedPreferences _prefs;

  static const _kBaseUrl = 'cloud_base_url';
  static const _kAccess = 'cloud_access_token';
  static const _kRefresh = 'cloud_refresh_token';
  static const _kSync = 'cloud_sync_token';
  static const _kDeviceId = 'cloud_device_id';
  static const _kEmail = 'cloud_email';
  static const _kS3Access = 's3_access_key';
  static const _kS3Secret = 's3_secret_key';

  AuthService(this._prefs);

  String? get baseUrl {
    final v = _prefs.getString(_kBaseUrl);
    if (v == null) return null;
    return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  }

  String? get accessToken => _prefs.getString(_kAccess);
  String? get refreshToken => _prefs.getString(_kRefresh);
  String? get syncToken => _prefs.getString(_kSync);
  String? get deviceId => _prefs.getString(_kDeviceId);
  String? get email => _prefs.getString(_kEmail);
  String? get s3AccessKey => _prefs.getString(_kS3Access);
  String? get s3SecretKey => _prefs.getString(_kS3Secret);

  bool get isCloudAuthenticated =>
      syncToken != null && baseUrl != null;

  Future<void> configureCloud(String baseUrl) async {
    final v = baseUrl.trim();
    await _prefs.setString(
        _kBaseUrl, v.endsWith('/') ? v.substring(0, v.length - 1) : v);
    notifyListeners();
  }

  Future<void> saveS3Secrets(String accessKey, String secretKey) async {
    await _prefs.setString(_kS3Access, accessKey);
    await _prefs.setString(_kS3Secret, secretKey);
    notifyListeners();
  }

  Future<void> register(String email, String password) async {
    await _authRequest(
      '/auth/register',
      {'email': email, 'password': password},
      201,
    );
    await _prefs.setString(_kEmail, email);
    await _ensureDevice();
  }

  Future<void> login(String email, String password) async {
    await _authRequest(
      '/auth/login',
      {'email': email, 'password': password},
      200,
    );
    await _prefs.setString(_kEmail, email);
    await _ensureDevice();
  }

  /// 若已存在设备令牌则跳过；否则用 access token 注册一个移动端设备。
  Future<void> _ensureDevice() async {
    if (deviceId != null && syncToken != null) return;
    final base = baseUrl;
    final access = accessToken;
    if (base == null || access == null) {
      throw Exception('缺少云服务地址或访问令牌');
    }
    final resp = await http.post(
      Uri.parse('$base/auth/devices'),
      headers: {
        'authorization': 'Bearer $access',
        'content-type': 'application/json',
      },
      body: jsonEncode({'name': 'MyDiary Mobile'}),
    );
    if (resp.statusCode != 201) {
      throw Exception('创建设备失败: ${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    await _prefs.setString(_kDeviceId, data['id'] as String);
    // 同步令牌仅返回一次，必须立即持久化。
    await _prefs.setString(_kSync, data['sync_token'] as String);
    notifyListeners();
  }

  Future<void> _authRequest(
    String path,
    Map<String, dynamic> body,
    int expected,
  ) async {
    final base = baseUrl;
    if (base == null) throw Exception('请先在设置中配置云服务地址');
    final resp = await http.post(
      Uri.parse('$base$path'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(body),
    );
    if (resp.statusCode != expected) {
      throw Exception('认证失败 (${resp.statusCode}): ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    await _prefs.setString(_kAccess, data['access_token'] as String);
    await _prefs.setString(_kRefresh, data['refresh_token'] as String);
  }

  /// 注销：清除全部云服务凭据（本地 vault 数据不受影响）。
  Future<void> logout() async {
    await _prefs.remove(_kAccess);
    await _prefs.remove(_kRefresh);
    await _prefs.remove(_kSync);
    await _prefs.remove(_kDeviceId);
    await _prefs.remove(_kEmail);
    notifyListeners();
  }

  /// 清除直接对象存储秘钥。
  Future<void> clearS3Secrets() async {
    await _prefs.remove(_kS3Access);
    await _prefs.remove(_kS3Secret);
    notifyListeners();
  }

  /// 清空云服务地址（切走云服务时调用，避免残留的无效地址被后续同步误用）。
  Future<void> clearCloudConfig() async {
    await _prefs.remove(_kBaseUrl);
    notifyListeners();
  }
}
