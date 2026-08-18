import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:my_diary_mobile/config/map_config.dart';
import 'package:my_diary_mobile/model/tian_map_decode.dart';

/// 天地图（Tianditu，国家地理信息公共服务平台）地图服务封装。
///
/// 瓦片为 CGCS2000 坐标系（与 WGS-84 偏差 < 1m），与 [Geolocator] 返回的
/// WGS-84 坐标可直接共用，无需做任何坐标偏移。Key 在 [MapConfig] 源码内配置，
/// 不在设置页。
const List<String> _tdtSubdomains = [
  '0',
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7'
];
const int _tdtMaxNativeZoom = 18; // 天地图原生瓦片最大级别
const double _tdtMaxZoom = 20; // 允许继续放大（拉伸）
const String tdtCopyright = '© 天地图';

/// 天地图底图类型（2D，`_w` 球面墨卡托投影，与 flutter_map 默认投影一致）。
/// 每种类型 = 底图层 + 注记层，见天地图服务列表：
/// - vector: vec_w / cva_w（矢量）
/// - satellite: img_w / cia_w（影像）
enum TdtMapType {
  vector('矢量', 'vec', 'cva'),
  satellite('影像', 'img', 'cia');

  final String label; // 中文名
  final String baseLayer; // 底图层名
  final String annoLayer; // 注记层名
  const TdtMapType(this.label, this.baseLayer, this.annoLayer);
}

/// 指定类型某图层的瓦片 URL（带 tk=key）。
String tdtTileUrl(TdtMapType type, String layer, String key) =>
    'https://t{s}.tianditu.gov.cn/${layer}_w/wmts'
    '?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
    '&LAYER=$layer&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles'
    '&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=$key';

/// 构建天地图瓦片层（底图 + 中文注记）。[type] 缺省矢量；[key] 缺省时取
/// [MapConfig.mapApiKey]；key 仍为空时返回空列表，由调用方提示配置。
List<TileLayer> tdtTileLayers(
    [TdtMapType type = TdtMapType.vector, String? key]) {
  key ??= MapConfig.mapApiKey;
  if (key.isEmpty) return const [];
  return [
    TileLayer(
      urlTemplate: tdtTileUrl(type, type.baseLayer, key),
      subdomains: _tdtSubdomains,
      tileDimension: 256,
      maxZoom: _tdtMaxZoom,
      maxNativeZoom: _tdtMaxNativeZoom,
      userAgentPackageName: 'com.mydiary.my_diary_mobile',
    ),
    TileLayer(
      urlTemplate: tdtTileUrl(type, type.annoLayer, key),
      subdomains: _tdtSubdomains,
      tileDimension: 256,
      maxZoom: _tdtMaxZoom,
      maxNativeZoom: _tdtMaxNativeZoom,
    ),
  ];
}

/// 逆地理编码：经纬度 → 人类可读地址（天地图 geocoder）。
/// 成功返回地址字符串，未配置 key / 失败返回 null。[key] 缺省时取 [MapConfig.mapApiKey]。
Future<String?> reverseGeocode(double lat, double lon, [String? key]) async {
  key ??= MapConfig.mapApiKey;
  if (key.isEmpty) return null;
  try {
    final postStr = jsonEncode({'lon': lon, 'lat': lat, 'ver': 1});
    final uri = Uri.https('api.tianditu.gov.cn', '/geocoder', {
      'postStr': postStr,
      'type': 'geocode',
      'tk': key,
    });
    final resp = await http.get(uri);
    if (resp.statusCode != 200) return null;
    final parsed =
        TdtGeocodeResponse.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    if (!parsed.isOk) return null;
    final addr = parsed.result?.addressComponent?.address;
    if (addr != null && addr.isNotEmpty) return addr;
    final formatted = parsed.result?.formattedAddress;
    if (formatted != null && formatted.isNotEmpty) return formatted;
    return null;
  } catch (_) {
    return null;
  }
}

/// 正地理编码（地址搜索）：关键词 → 坐标（天地图 geocoder ds 接口）。
/// 成功返回首个匹配点，失败 / 未配置 key / 无结果返回 null。
/// [key] 缺省取 [MapConfig.mapApiKey]。
Future<TdtPlace?> geocodePlace(String keyword, [String? key]) async {
  key ??= MapConfig.mapApiKey;
  final kw = keyword.trim();
  if (key.isEmpty || kw.isEmpty) return null;
  try {
    final ds = jsonEncode({'keyWord': kw});
    final uri = Uri.https('api.tianditu.gov.cn', '/geocoder', {
      'ds': ds,
      'type': 'geocode',
      'tk': key,
    });
    final resp = await http.get(uri);
    if (resp.statusCode != 200) return null;
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    if (json['status']?.toString() != '0') return null;
    final loc = json['location'] as Map<String, dynamic>?;
    if (loc == null) return null;
    final place = TdtPlace.fromJson(loc);
    if (place.lat == 0 && place.lon == 0) return null;
    return place;
  } catch (_) {
    return null;
  }
}

/// 获取当前 GPS 位置（含权限申请与 Android 兜底）。失败返回 null。
/// 先秒回最后已知位置（缓存），再用短超时（5s）尝试新定位，超时走系统定位管理器。
Future<Position?> getCurrentPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) return null;
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last; // 毫秒级秒回缓存定位
    } catch (_) {}
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } on TimeoutException {
      if (Platform.isAndroid) {
        return await Geolocator.getCurrentPosition(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 5),
            forceLocationManager: true,
          ),
        );
      }
      rethrow;
    }
  } catch (_) {
    return null;
  }
}
