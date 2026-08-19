/**
 * 地图 API 配置（源码内配置，不在设置页）。
 *
 * 天地图（Tianditu，国家地理信息公共服务平台）为合规持牌地图源。
 * 瓦片坐标系为 CGCS2000，与 GPS 的 WGS-84 偏差 < 1m，可直接共用，无需偏移。
 * Key 与移动端 `lib/config/map_config.dart` 保持一致。
 */

/** 天地图访问密钥（tk，浏览器端 Key）。 */
export const MAP_API_KEY = "dd7d5d87a02a4a81dede7722d39ea1e9";

/** 瓦片版权标识。 */
export const TDT_COPYRIGHT = "© 天地图";

/** 天地图瓦片子域（Leaflet 以 {s} 轮询）。 */
export const TDT_SUBDOMAINS = ["0", "1", "2", "3", "4", "5", "6", "7"];

/** 天地图原生瓦片最大级别（以上拉伸）。 */
export const TDT_MAX_NATIVE_ZOOM = 18;
/** 允许继续放大的最大级别。 */
export const TDT_MAX_ZOOM = 20;

/** 地图初始中心（北京兜底）。 */
export const DEFAULT_CENTER: [number, number] = [39.909187, 116.397451];

/** 天地图底图类型（2D，`_w` 球面墨卡托投影，与 Leaflet 默认投影一致）。 */
export enum TdtMapType {
  vector = "vector",
  satellite = "satellite",
}

interface TdtTypeInfo {
  label: string;
  base: string;
  anno: string;
}

/** 每种类型 = 底图层 + 注记层，见天地图服务列表。 */
export const TDT_TYPE_INFO: Record<TdtMapType, TdtTypeInfo> = {
  [TdtMapType.vector]: { label: "矢量", base: "vec", anno: "cva" },
  [TdtMapType.satellite]: { label: "影像", base: "img", anno: "cia" },
};

/** 是否已配置可用密钥。 */
export const isMapConfigured = MAP_API_KEY.trim().length > 0;
