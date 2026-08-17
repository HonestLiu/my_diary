/// 地图 API 配置（源码内配置，不在设置页）。
///
/// 天地图（Tianditu，国家地理信息公共服务平台）为合规持牌地图源。
/// 瓦片坐标系为 CGCS2000，与 GPS 的 WGS-84 偏差 < 1m，可直接共用，无需偏移。
class MapConfig {
  /// 天地图访问密钥（tk）。构建期可通过
  /// `--dart-define=TIANDITU_KEY=你的Key` 注入；未注入时回退到下方源码内的
  /// [sourceMapApiKey]。两种方式都不在「设置页」中配置。
  static const String mapApiKey =
      String.fromEnvironment('TIANDITU_KEY', defaultValue: sourceMapApiKey);

  /// 源码内配置的天地图 Key（不在设置页）。留空则地图不加载。
  /// 申请：https://tiditu.gov.cn → 应用管理 → 创建应用（浏览器端 / 服务端 Key，免费）。
  static const String sourceMapApiKey = ''; // TODO: 填入你的天地图 Key

  /// 瓦片版权标识。
  static const String attribution = '© 天地图';

  /// 逆地理编码服务主机。
  static const String geocoderHost = 'api.tianditu.gov.cn';

  /// 是否已配置可用密钥。
  static bool get isConfigured => mapApiKey.isNotEmpty;
}
