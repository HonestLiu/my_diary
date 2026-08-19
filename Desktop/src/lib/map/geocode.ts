import { MAP_API_KEY } from "./config";

/** 天地图 Geocoder（逆地理编码查询）响应模型。 */
interface TdtAddressComponent {
  address: string;
}

interface TdtResult {
  formatted_address?: string;
  addressComponent?: TdtAddressComponent;
}

interface TdtGeocodeResponse {
  status: string;
  result?: TdtResult | null;
}

/** 地址搜索（ds 接口）返回的匹配点：`location` 是扁平对象。 */
export interface TdtPlace {
  name: string;
  level?: string;
  lat: number;
  lon: number;
}

/**
 * 逆地理编码：经纬度 → 人类可读地址（天地图 geocoder）。
 * 成功返回地址字符串，未配置 key / 失败返回 null。
 */
export async function reverseGeocode(
  lat: number,
  lon: number,
  key: string = MAP_API_KEY,
): Promise<string | null> {
  if (key.trim() === "") return null;
  try {
    const postStr = JSON.stringify({ lon, lat, ver: 1 });
    const uri = new URL("https://api.tianditu.gov.cn/geocoder");
    uri.searchParams.set("postStr", postStr);
    uri.searchParams.set("type", "geocode");
    uri.searchParams.set("tk", key);
    const resp = await fetch(uri.toString());
    if (!resp.ok) return null;
    const parsed = (await resp.json()) as TdtGeocodeResponse;
    if (parsed.status !== "0") return null;
    const addr = parsed.result?.addressComponent?.address;
    if (addr && addr.trim() !== "") return addr;
    const formatted = parsed.result?.formatted_address;
    if (formatted && formatted.trim() !== "") return formatted;
    return null;
  } catch {
    return null;
  }
}

/**
 * 正地理编码（地址搜索）：关键词 → 坐标（天地图 geocoder ds 接口）。
 * 成功返回首个匹配点，失败 / 未配置 key / 无结果返回 null。
 */
export async function geocodePlace(
  keyword: string,
  key: string = MAP_API_KEY,
): Promise<TdtPlace | null> {
  const kw = keyword.trim();
  if (key.trim() === "" || kw === "") return null;
  try {
    const ds = JSON.stringify({ keyWord: kw });
    const uri = new URL("https://api.tianditu.gov.cn/geocoder");
    uri.searchParams.set("ds", ds);
    uri.searchParams.set("type", "geocode");
    uri.searchParams.set("tk", key);
    const resp = await fetch(uri.toString());
    if (!resp.ok) return null;
    const json = (await resp.json()) as Record<string, unknown>;
    if (String(json["status"]) !== "0") return null;
    const loc = json["location"] as Record<string, unknown> | null;
    if (!loc) return null;
    const place: TdtPlace = {
      name: String(loc["keyWord"] ?? kw),
      level: typeof loc["level"] === "string" ? loc["level"] : undefined,
      lat: Number.parseFloat(String(loc["lat"])) || 0,
      lon: Number.parseFloat(String(loc["lon"])) || 0,
    };
    if (place.lat === 0 && place.lon === 0) return null;
    return place;
  } catch {
    return null;
  }
}
