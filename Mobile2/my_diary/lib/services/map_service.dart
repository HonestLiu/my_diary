import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:my_diary_mobile/model/tian_map_decode.dart';

/// 天地图（Tianditu，国家地理信息公共服务平台）地图服务封装。
///
/// 瓦片为 CGCS2000 坐标系（与 WGS-84 偏差 < 1m），与 [Geolocator] 返回的
/// WGS-84 坐标可直接共用，无需做任何坐标偏移。Key 由用户在设置页自备，不硬编码。
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

/// 影像底图瓦片层 URL（带 tk=key）。
String tdtImgUrl(String key) =>
    'https://t{s}.tianditu.gov.cn/img_w/wmts'
    '?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
    '&LAYER=img&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles'
    '&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=$key';

/// 中文注记叠层 URL（带 tk=key，透明 PNG 叠加在影像之上）。
String tdtCiaUrl(String key) =>
    'https://t{s}.tianditu.gov.cn/cia_w/wmts'
    '?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
    '&LAYER=cia&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles'
    '&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=$key';

/// 构建天地图瓦片层（影像 + 中文注记）。key 为空时返回空列表，由调用方提示配置。
List<TileLayer> tdtTileLayers(String key) {
  if (key.isEmpty) return const [];
  return [
    TileLayer(
      urlTemplate: tdtImgUrl(key),
      subdomains: _tdtSubdomains,
      tileDimension: 256,
      maxZoom: _tdtMaxZoom,
      maxNativeZoom: _tdtMaxNativeZoom,
      userAgentPackageName: 'com.mydiary.my_diary_mobile',
    ),
    TileLayer(
      urlTemplate: tdtCiaUrl(key),
      subdomains: _tdtSubdomains,
      tileDimension: 256,
      maxZoom: _tdtMaxZoom,
      maxNativeZoom: _tdtMaxNativeZoom,
    ),
  ];
}

/// 逆地理编码：经纬度 → 人类可读地址（天地图 geocoder）。
/// 成功返回地址字符串，未配置 key / 失败返回 null。
Future<String?> reverseGeocode(double lat, double lon, String key) async {
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

/// 获取当前 GPS 位置（含权限申请与 Android 兜底）。失败返回 null。
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
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } on TimeoutException {
      if (Platform.isAndroid) {
        return await Geolocator.getCurrentPosition(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 8),
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
