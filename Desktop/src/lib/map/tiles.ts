import L from "leaflet";
import {
  MAP_API_KEY,
  TDT_MAX_NATIVE_ZOOM,
  TDT_MAX_ZOOM,
  TDT_SUBDOMAINS,
  TDT_TYPE_INFO,
  type TdtMapType,
} from "./config";

/** 指定图层的瓦片 URL 模板（带 tk=key，Leaflet 替换 {s}/{z}/{y}/{x}）。 */
export function tdtTileUrl(layer: string, key: string): string {
  return `https://t{s}.tianditu.gov.cn/${layer}_w/wmts`
    + "?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0"
    + `&LAYER=${layer}&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles`
    + `&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=${key}`;
}

/**
 * 构建天地图瓦片层（底图 + 中文注记）。[type] 缺省矢量；[key] 缺省时取
 * [MAP_API_KEY]；key 仍为空时返回空数组，由调用方提示配置。
 */
export function createTdtLayers(
  type: TdtMapType,
  key?: string,
): L.TileLayer[] {
  const tk = key ?? MAP_API_KEY;
  if (tk.trim() === "") return [];
  const info = TDT_TYPE_INFO[type];
  const opts: L.TileLayerOptions = {
    subdomains: TDT_SUBDOMAINS,
    tileSize: 256,
    maxZoom: TDT_MAX_ZOOM,
    maxNativeZoom: TDT_MAX_NATIVE_ZOOM,
  };
  return [
    L.tileLayer(tdtTileUrl(info.base, tk), opts),
    L.tileLayer(tdtTileUrl(info.anno, tk), { ...opts, opacity: 1 }),
  ];
}
