import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:my_diary_mobile/config/map_config.dart';
import 'package:my_diary_mobile/services/locator_data.dart';
import 'package:my_diary_mobile/services/map_service.dart';

/// 定位服务：权限检查、多级回退获取当前位置、最后已知位置与逆地理编码，
/// 所有状态通过 [LocatorData] 广播。移植自原 MyDiary 的 `lib/tools/locator_tool.dart`。
class LocatorService {
  final LocatorData locatorData;

  LocatorService(this.locatorData);

  /// 检查定位服务与权限，失败时写入状态并返回 false。
  Future<bool> _ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      locatorData.updateStatus('定位服务未开启');
      return false;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        locatorData.updateStatus('用户拒绝权限');
        return false;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      locatorData.updateStatus('权限被永久拒绝，请到系统设置开启');
      return false;
    }
    return true;
  }

  /// 位置新鲜度阈值（秒）：小于该值视为可复用的缓存定位。
  static const int _freshSeconds = 60;

  bool _isFresh(Position p) {
    final t = p.timestamp;
    if (t == null) return false;
    return DateTime.now().difference(t).inSeconds < _freshSeconds;
  }

  /// 快速获取位置：新鲜的最后已知位置秒回；否则短超时（5s）尝试新定位；
  /// 超时依次退回已知位置、低精度、Android 强制系统 LocationManager。
  Future<Position> _acquirePosition() async {
    Position? last;
    try {
      last = await Geolocator.getLastKnownPosition();
    } catch (_) {}
    if (last != null && _isFresh(last)) return last; // 毫秒级秒回
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } on TimeoutException {
      if (last != null) return last; // 新定位超时，退回已知位置（可能较旧）
      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 4),
          ),
        );
      } catch (_) {
        if (Platform.isAndroid) {
          return await Geolocator.getCurrentPosition(
            locationSettings: AndroidSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 4),
              forceLocationManager: true,
            ),
          );
        }
        rethrow;
      }
    }
  }

  /// 后台刷新一次当前位置（不阻塞调用方，失败静默保留现有位置）。
  Future<void> _refreshPosition() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      locatorData.updateCurrentPosition(p);
      locatorData.updateStatus('已获取当前定位');
    } catch (_) {
      // 后台刷新失败忽略。
    }
  }

  /// 获取当前位置。优先复用 60s 内的缓存/最后已知位置（秒回），后台再刷新；
  /// 否则按多级回退快速获取（缩短等待）。
  Future<void> getCurrent() async {
    if (!await _ensurePermission()) return;
    locatorData.updateStatus('获取当前定位中…');
    try {
      final cached = locatorData.currentPosition;
      if (cached != null && _isFresh(cached)) {
        locatorData.updateStatus('使用最近定位');
        unawaited(_refreshPosition());
        return;
      }
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && _isFresh(last)) {
        locatorData.updateCurrentPosition(last);
        locatorData.updateStatus('使用最后已知位置');
        unawaited(_refreshPosition());
        return;
      }
    } catch (_) {}
    try {
      final p = await _acquirePosition();
      locatorData.updateCurrentPosition(p);
      locatorData.updateStatus('已获取当前定位');
    } catch (e) {
      locatorData.updateStatus('获取失败: $e');
    }
  }

  /// 获取最后一次已知位置。
  Future<void> getLastKnown() async {
    if (!await _ensurePermission()) return;
    final p = await Geolocator.getLastKnownPosition();
    if (p != null) locatorData.updateLastKnownPosition(p);
    locatorData.updateStatus(p == null ? '无最后已知位置' : '已获取最后已知位置');
  }

  /// 逆地理编码：当前 GPS 位置 → 人类可读地址（天地图 geocoder）。
  Future<void> getUserAddress() async {
    if (!await _ensurePermission()) return;
    locatorData.updateStatus('请求中…');
    try {
      Position pos;
      final cached = locatorData.currentPosition;
      if (cached != null && _isFresh(cached)) {
        pos = cached; // 秒回：复用 60s 内定位，后台再刷新
        unawaited(_refreshPosition());
      } else {
        pos = await _acquirePosition();
      }
      locatorData.updateCurrentPosition(pos);

      if (!MapConfig.isConfigured) {
        locatorData.updateUserAddress('未配置地图密钥');
        locatorData.updateStatus('未配置地图密钥');
        return;
      }
      final addr = await reverseGeocode(pos.latitude, pos.longitude);
      if (addr != null && addr.isNotEmpty) {
        locatorData.updateUserAddress(addr);
        locatorData.updateStatus('地址获取成功');
      } else {
        locatorData.updateUserAddress('无有效地址');
        locatorData.updateStatus('返回异常或无有效地址');
      }
    } catch (e) {
      locatorData.updateStatus('请求失败: $e');
      locatorData.updateUserAddress('请求失败');
    }
  }

  /// 格式化坐标，null 显示 '--'。
  String fmt(Position? p) => p == null
      ? '--'
      : '(${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)})';
}
