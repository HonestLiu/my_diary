/// 心知天气（Seniverse）实况天气请求返回值解析。
/// 移植自原 MyDiary 的 `lib/model/weather_now.dart`。
class WeatherLocation {
  final String id;
  final String name;
  final String country;
  final String path;
  final String timezone;
  final String timezoneOffset;

  WeatherLocation({
    required this.id,
    required this.name,
    required this.country,
    required this.path,
    required this.timezone,
    required this.timezoneOffset,
  });

  factory WeatherLocation.fromJson(Map<String, dynamic> json) =>
      WeatherLocation(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        country: json['country'] ?? '',
        path: json['path'] ?? '',
        timezone: json['timezone'] ?? '',
        timezoneOffset: json['timezone_offset'] ?? '',
      );
}

class WeatherNow {
  final WeatherLocation location;
  final String text; // 天气现象文字
  final String code; // 天气代码（数字字符串）
  final String temperature; // 温度（字符串）
  final DateTime lastUpdate;

  WeatherNow({
    required this.location,
    required this.text,
    required this.code,
    required this.temperature,
    required this.lastUpdate,
  });

  factory WeatherNow.fromJson({
    required Map<String, dynamic> location,
    required Map<String, dynamic> now,
    required String lastUpdate,
  }) {
    return WeatherNow(
      location: WeatherLocation.fromJson(location),
      text: now['text'] ?? '-',
      code: now['code'] ?? '-',
      temperature: now['temperature'] ?? '-',
      lastUpdate: DateTime.tryParse(lastUpdate) ?? DateTime.now(),
    );
  }
}
