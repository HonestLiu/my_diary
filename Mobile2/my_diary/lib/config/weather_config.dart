/// 天气 API 配置（源码内配置，不在设置页）。
///
/// 使用心知天气（Seniverse）实况天气接口，与地图 Key 同一套管理方式。
class WeatherConfig {
  /// 心知天气访问密钥。构建期可通过
  /// `--dart-define=SENIVERSE_KEY=你的Key` 注入；未注入时回退到下方源码内的
  /// [sourceWeatherApiKey]。
  static const String weatherApiKey =
      String.fromEnvironment('SENIVERSE_KEY', defaultValue: sourceWeatherApiKey);

  /// 源码内配置的心知天气 Key（不在设置页）。留空则不请求网络。
  /// 申请：https://www.seniverse.com 注册后获取私钥。
  static const String sourceWeatherApiKey = 'ShO8h-8U9cfzNF7Th'; // TODO: 填入你的心知天气 Key

  /// 是否已配置可用密钥。
  static bool get isConfigured => weatherApiKey.isNotEmpty;
}
