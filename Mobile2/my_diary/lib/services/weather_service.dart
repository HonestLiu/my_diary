import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:my_diary_mobile/config/weather_config.dart';
import 'package:my_diary_mobile/model/weather_now.dart';
import 'package:my_diary_mobile/models/journal_entry.dart';

/// 心知天气（Seniverse）实况天气服务。
/// 移植自原 MyDiary 的 `lib/services/weather_service.dart`。
class WeatherService {
  static const String _base = 'https://api.seniverse.com/v3/weather/now.json';

  final String location; // 形如 "纬度:经度"
  final String? apiKey; // 为空则不请求网络（缺省取 WeatherConfig.weatherApiKey）

  WeatherService({required this.location, String? apiKey})
      : apiKey = apiKey ?? WeatherConfig.weatherApiKey;

  /// 拉取当前天气。若 [overrideLocation] 提供则临时使用它，否则用实例中的 [location]。
  Future<WeatherNow> fetchNow({
    String? overrideLocation,
    String language = 'zh-Hans',
    String unit = 'c',
  }) async {
    if (apiKey == null || apiKey!.trim().isEmpty) {
      // 不做网络请求，返回占位
      return WeatherNow.fromJson(
        location: {
          'id': '',
          'name': '',
          'country': '',
          'path': '',
          'timezone': '',
          'timezone_offset': '',
        },
        now: {'text': '-', 'code': '', 'temperature': ''},
        lastUpdate: DateTime.now().toIso8601String(),
      );
    }
    final loc = (overrideLocation ?? location).isEmpty
        ? '39.93:116.40' // 兜底默认（北京）
        : (overrideLocation ?? location);
    final key = apiKey!.trim();
    final uri = Uri.parse(
        '$_base?key=$key&location=$loc&language=$language&unit=$unit');
    final resp = await http.get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    final results = map['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) {
      throw Exception('Empty results');
    }
    final first = results.first as Map<String, dynamic>;
    final locationMap = (first['location'] ?? {}) as Map<String, dynamic>;
    final now = (first['now'] ?? {}) as Map<String, dynamic>;
    final lastUpdate = first['last_update'] as String? ?? '';
    return WeatherNow.fromJson(
      location: locationMap,
      now: now,
      lastUpdate: lastUpdate,
    );
  }
}

/// 心知天气 code → 移动端 [Weather] 枚举映射（未识别返回 [Weather.unknown]）。
/// 参见心知天气「天气代码」表。
Weather weatherFromSeniverseCode(String code) {
  switch (code) {
    case '0': // 晴
      return Weather.sunny;
    case '1': // 多云
    case '2': // 阴
    case '37': // 晴间多云
    case '38': // 多云间阴
      return Weather.cloudy;
    case '3': // 阵雨
    case '4': // 雷阵雨
    case '5': // 雷阵雨伴有冰雹
    case '6': // 雨夹雪
    case '7': // 小雨
    case '8': // 中雨
    case '9': // 大雨
    case '10': // 暴雨
    case '11': // 大暴雨
    case '12': // 特大暴雨
    case '19': // 冻雨
    case '21': // 小到中雨
    case '22': // 中到大雨
    case '23': // 大到暴雨
    case '24': // 暴雨到大暴雨
    case '25': // 大暴雨到特大暴雨
      return Weather.rainy;
    case '13': // 阵雪
    case '14': // 小雪
    case '15': // 中雪
    case '16': // 大雪
    case '17': // 暴雪
    case '26': // 小到中雪
    case '27': // 中到大雪
    case '28': // 大到暴雪
    case '34': // 弱高吹雪
      return Weather.snowy;
    case '18': // 雾
    case '35': // 轻雾
    case '36': // 霾
      return Weather.foggy;
    case '20': // 沙尘暴
    case '29': // 浮尘
    case '30': // 扬沙
    case '31': // 强沙尘暴
    case '32': // 飑
    case '33': // 龙卷风
    case '49': // 强风
      return Weather.windy;
    default:
      return Weather.unknown;
  }
}
