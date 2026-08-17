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

  /// 获取当前位置。多级回退：超时 → 最后一次已知位置 → 低精度重试 →
  /// Android 强制系统 LocationManager（无 GMS 环境兜底）。
  Future<void> getCurrent() async {
    if (!await _ensurePermission()) return;
    locatorData.updateStatus('获取当前定位中…');
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      locatorData.updateCurrentPosition(p);
      locatorData.updateStatus('已获取当前定位');
    } catch (e) {
      if (e is TimeoutException) {
        // Android 模拟器或室内可能拿不到首个定位，逐级回退。
        try {
          final last = await Geolocator.getLastKnownPosition();
          if (last != null) {
            locatorData.updateCurrentPosition(last);
            locatorData.updateStatus('使用最后一次已知位置');
            return;
          }
        } catch (_) {}
        try {
          final p2 = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 8),
            ),
          );
          locatorData.updateCurrentPosition(p2);
          locatorData.updateStatus('已获取当前定位(低精度)');
          return;
        } catch (_) {}
        if (Platform.isAndroid) {
          try {
            final p3 = await Geolocator.getCurrentPosition(
              locationSettings: AndroidSettings(
                accuracy: LocationAccuracy.low,
                timeLimit: Duration(seconds: 8),
                forceLocationManager: true,
              ),
            );
            locatorData.updateCurrentPosition(p3);
            locatorData.updateStatus('已获取当前定位(系统定位管理器)');
            return;
          } catch (_) {}
        }
      }
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
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } on TimeoutException {
        if (Platform.isAndroid) {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: AndroidSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 8),
              forceLocationManager: true,
            ),
          );
        } else {
          rethrow;
        }
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
