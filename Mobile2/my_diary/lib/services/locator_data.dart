import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// 位置数据状态类（ChangeNotifier，供地图/定位相关页面监听）。
/// 移植自原 MyDiary 的 `lib/states/locator_data.dart`。
class LocatorData extends ChangeNotifier {
  Position? _currentPosition; // 当前定位
  Position? _lastKnownPosition; // 最近一次已知定位
  String? _userAddress; // 用户地址（逆地理编码结果）
  String? _status; // 状态信息（权限/获取进度/错误）

  Position? get currentPosition => _currentPosition;
  Position? get lastKnownPosition => _lastKnownPosition;
  String? get userAddress => _userAddress;
  String? get status => _status;

  void updateCurrentPosition(Position position) {
    _currentPosition = position;
    notifyListeners();
  }

  void updateLastKnownPosition(Position position) {
    _lastKnownPosition = position;
    notifyListeners();
  }

  void updateUserAddress(String address) {
    _userAddress = address;
    notifyListeners();
  }

  void updateStatus(String status) {
    _status = status;
    notifyListeners();
  }

  /// 清空所有位置信息。
  void clear() {
    _currentPosition = null;
    _lastKnownPosition = null;
    _userAddress = null;
    _status = null;
    notifyListeners();
  }
}
