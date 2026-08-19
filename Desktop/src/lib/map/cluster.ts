import type { JournalEntry } from "@/types/journal";

/** 一个聚簇：质心坐标 + 簇内日记 + 代表性日记（有图优先）。 */
export interface EntryCluster {
  lat: number;
  lon: number;
  entries: JournalEntry[];
  representative: JournalEntry;
}

/** 网格聚簇的像素大小（与移动端 map_screen.dart 一致）。 */
const GRID_PX = 80;
/** 聚簇网格的最大地理跨度（约 0.5° ≈ 55km，城市级）。 */
const MAX_BUCKET_DEG = 0.5;

/**
 * 按缩放级别网格聚类：把全部带经纬度的日记分桶，每个桶取质心，
 * 返回按桶合并后的聚簇列表。算法与移动端 `map_screen.dart _buildMarkers`
 * 保持一致。
 */
export function clusterEntries(
  entries: JournalEntry[],
  zoom: number,
): EntryCluster[] {
  const pixelsPerWorld = 256 * Math.pow(2, zoom);
  const degPerPixelLon = 360 / pixelsPerWorld;
  const bucketDegLon = Math.min(degPerPixelLon * GRID_PX, MAX_BUCKET_DEG);
  const bucketDegLat = bucketDegLon;

  const bucketKey = (lat: number, lon: number) => {
    const by = Math.floor(lat / bucketDegLat);
    const bx = Math.floor(lon / bucketDegLon);
    return `${by},${bx}`;
  };

  const buckets = new Map<string, JournalEntry[]>();
  for (const e of entries) {
    if (e.latitude == null || e.longitude == null) continue;
    const key = bucketKey(e.latitude, e.longitude);
    const list = buckets.get(key);
    if (list) list.push(e);
    else buckets.set(key, [e]);
  }

  const clusters: EntryCluster[] = [];
  for (const list of buckets.values()) {
    if (list.length === 0) continue;
    let latSum = 0;
    let lonSum = 0;
    for (const e of list) {
      latSum += e.latitude ?? 0;
      lonSum += e.longitude ?? 0;
    }
    const first = list[0];
    if (!first) continue;
    const representative =
      list.find((e) => e.assets.some((a) => a.kind === "image")) ?? first;
    clusters.push({
      lat: latSum / list.length,
      lon: lonSum / list.length,
      entries: list,
      representative,
    });
  }
  return clusters;
}
