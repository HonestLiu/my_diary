import { useEffect, useMemo, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import L from "leaflet";
import { Minus, Plus, LocateFixed, X } from "lucide-react";
import { useAppStore } from "@/store/appStore";
import { EntryCard } from "@/components/EntryCard";
import { MarkdownPreview } from "@/components/MarkdownPreview";
import { getStorage } from "@/lib/storage";
import { firstCoverAsset, thumbnailPath } from "@/lib/vault";
import { cn } from "@/lib/utils";
import type { JournalEntry } from "@/types/journal";
import {
  DEFAULT_CENTER,
  TDT_COPYRIGHT,
  isMapConfigured,
  TDT_TYPE_INFO,
  TdtMapType,
} from "@/lib/map/config";
import { createTdtLayers } from "@/lib/map/tiles";
import { getCurrentPosition } from "@/lib/map/geolocation";
import { clusterEntries, type EntryCluster } from "@/lib/map/cluster";

const MIN_ZOOM = 0;
const MAX_ZOOM = 20;
const AUTO_ZOOM = 14;
const INITIAL_ZOOM = 4;

/**
 * 足迹地图 —— 与移动端 MapScreen 同构：
 * 把全部带经纬度的日记标注在天地图上，按缩放级别网格聚类；
 * 单击标点进入日记编辑，聚簇点弹出「此位置日记」列表卡片。
 */
export default function Map() {
  const entries = useAppStore((s) => s.entries);
  const openEntry = useAppStore((s) => s.openEntry);
  const navigate = useNavigate();

  const mapEl = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<L.Map | null>(null);
  const layerGroupRef = useRef<L.LayerGroup | null>(null);
  const tileLayersRef = useRef<L.TileLayer[]>([]);
  const currentZoomRef = useRef(INITIAL_ZOOM);
  const [zoom, setZoom] = useState(INITIAL_ZOOM);
  const [ready, setReady] = useState(false);
  const [mapType, setMapType] = useState<TdtMapType>(TdtMapType.vector);
  const [group, setGroup] = useState<EntryCluster | null>(null);
  const [locating, setLocating] = useState(false);
  const [locateError, setLocateError] = useState("");

  const locatedEntries = useMemo(
    () => entries.filter((e) => e.latitude != null && e.longitude != null),
    [entries],
  );

  // ---- Leaflet init (once) ----
  useEffect(() => {
    if (!mapEl.current || mapRef.current) return;
    const map = L.map(mapEl.current, {
      center: DEFAULT_CENTER,
      zoom: INITIAL_ZOOM,
      minZoom: MIN_ZOOM,
      maxZoom: MAX_ZOOM,
      zoomControl: false,
      attributionControl: false,
    });
    mapRef.current = map;
    layerGroupRef.current = L.layerGroup().addTo(map);

    map.on("zoomend", () => {
      const z = map.getZoom();
      if (Math.abs(z - currentZoomRef.current) >= 0.25) {
        currentZoomRef.current = z;
        setZoom(z);
      }
    });

    setReady(true);
    return () => {
      map.remove();
      mapRef.current = null;
      layerGroupRef.current = null;
      tileLayersRef.current = [];
    };
  }, []);

  // ---- Tile layers follow map type ----
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    tileLayersRef.current.forEach((t) => t.remove());
    tileLayersRef.current = createTdtLayers(mapType);
    tileLayersRef.current.forEach((t) => t.addTo(map));
  }, [mapType, ready]);

  // ---- Re-cluster markers when entries / zoom change ----
  useEffect(() => {
    const map = mapRef.current;
    const layerGroup = layerGroupRef.current;
    if (!map || !layerGroup) return;
    void rebuildMarkers(
      layerGroup,
      locatedEntries,
      currentZoomRef.current,
      (cluster) => {
        const single = cluster.entries[0];
        if (cluster.entries.length === 1 && single) {
          openEntry(single.id, single.date);
          navigate("/editor");
        } else {
          setGroup(cluster);
        }
      },
    );
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [locatedEntries, zoom, ready, mapType]);

  // ---- Auto-locate once on ready (best effort) ----
  useEffect(() => {
    if (!ready) return;
    void (async () => {
      const pos = await getCurrentPosition();
      const map = mapRef.current;
      if (!pos || !map) return;
      const center = map.getCenter();
      if (center.lat === DEFAULT_CENTER[0] && center.lng === DEFAULT_CENTER[1]) {
        map.setView([pos.latitude, pos.longitude], AUTO_ZOOM);
      }
    })();
  }, [ready]);

  const handleLocate = async () => {
    setLocating(true);
    setLocateError("");
    const pos = await getCurrentPosition();
    setLocating(false);
    const map = mapRef.current;
    if (!pos || !map) {
      setLocateError("无法获取定位，请检查系统定位权限");
      return;
    }
    map.setView([pos.latitude, pos.longitude], AUTO_ZOOM);
  };

  const zoomBy = (delta: number) => {
    const map = mapRef.current;
    if (!map) return;
    const z = Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, map.getZoom() + delta));
    map.setZoom(z);
  };

  const open = (e: JournalEntry) => {
    openEntry(e.id, e.date);
    navigate("/editor");
  };

  return (
    <div className="flex h-full flex-col">
      {/* 页头 */}
      <div className="flex items-center justify-between px-6 py-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight text-foreground">
            足迹
          </h1>
          <p className="mt-0.5 text-sm text-muted-foreground">
            {locatedEntries.length} 个地点
          </p>
        </div>
        <div className="flex items-center gap-1 rounded-full border border-border bg-card p-1 shadow-sm">
          {(Object.keys(TDT_TYPE_INFO) as TdtMapType[]).map((t) => (
            <button
              key={t}
              type="button"
              onClick={() => setMapType(t)}
              className={cn(
                "rounded-full px-3 py-1 text-sm transition-colors",
                mapType === t
                  ? "bg-accent text-accent-foreground"
                  : "text-muted-foreground hover:bg-muted",
              )}
            >
              {TDT_TYPE_INFO[t].label}
            </button>
          ))}
        </div>
      </div>

      {/* 地图主体 */}
      <div className="relative min-h-0 flex-1 px-6 pb-6">
        {!isMapConfigured ? (
          <div className="flex h-full items-center justify-center rounded-2xl border border-border bg-card">
            <p className="max-w-sm text-center text-sm text-muted-foreground">
              未配置天地图密钥，无法加载地图
              <br />
              请在 src/lib/map/config.ts 中填写 Key
            </p>
          </div>
        ) : (
          <>
            <div
              ref={mapEl}
              className="h-full w-full overflow-hidden rounded-2xl border border-border bg-card"
            />

            {/* 聚簇位置日记列表 */}
            {group && (
              <div className="absolute right-4 top-4 z-[500] flex max-h-[calc(100%-2rem)] w-80 flex-col overflow-hidden rounded-2xl border border-border bg-card shadow-2xl">
                <div className="flex items-center justify-between border-b border-border px-4 py-3">
                  <span className="text-sm font-semibold text-foreground">
                    此位置日记 ({group.entries.length})
                  </span>
                  <button
                    type="button"
                    onClick={() => setGroup(null)}
                    aria-label="关闭"
                    className="rounded-lg p-1 text-muted-foreground hover:bg-muted"
                  >
                    <X className="h-4 w-4" />
                  </button>
                </div>
                <div className="flex flex-col gap-2 overflow-y-auto p-3">
                  {group.entries.map((e) => (
                    <EntryCard
                      key={e.id}
                      title={e.title}
                      meta={e.date.slice(5)}
                      mood={e.mood}
                      weather={e.weather}
                      preview={
                        e.body.trim() ? (
                          <MarkdownPreview body={e.body} />
                        ) : (
                          "（空白日记）"
                        )
                      }
                      location={e.location}
                      tags={e.tags}
                      cover={firstCoverAsset(e.assets)}
                      onClick={() => {
                        setGroup(null);
                        open(e);
                      }}
                    />
                  ))}
                </div>
              </div>
            )}

            {/* 左下角浮动控制：缩放 / 定位 */}
            <div className="absolute bottom-4 left-4 z-[400] flex flex-col gap-1.5">
              <div className="flex flex-col overflow-hidden rounded-xl border border-border bg-card shadow-soft">
                <button
                  type="button"
                  onClick={() => zoomBy(1)}
                  aria-label="放大"
                  className="flex h-9 w-9 items-center justify-center text-foreground transition-colors hover:bg-muted"
                >
                  <Plus className="h-4 w-4" />
                </button>
                <div className="h-px bg-border" />
                <button
                  type="button"
                  onClick={() => zoomBy(-1)}
                  aria-label="缩小"
                  className="flex h-9 w-9 items-center justify-center text-foreground transition-colors hover:bg-muted"
                >
                  <Minus className="h-4 w-4" />
                </button>
              </div>
              <button
                type="button"
                onClick={handleLocate}
                disabled={locating}
                aria-label="定位"
                className="flex h-9 w-9 items-center justify-center rounded-xl border border-border bg-card text-foreground shadow-soft transition-colors hover:bg-muted disabled:opacity-60"
              >
                <LocateFixed className="h-4 w-4" />
              </button>
              {locateError && (
                <div className="max-w-[180px] rounded-lg bg-black/70 px-2.5 py-1.5 text-[11px] text-white shadow-soft">
                  {locateError}
                </div>
              )}
            </div>

            {/* 右下角：缩放级别 + 版权 */}
            <div className="absolute bottom-4 right-4 z-[400] flex flex-col items-end gap-1.5">
              <span className="rounded bg-black/60 px-1.5 py-0.5 text-[11px] text-white">
                Z {zoom.toFixed(1)}
              </span>
              <span className="rounded bg-black/60 px-1.5 py-0.5 text-[11px] text-white">
                {TDT_COPYRIGHT}
              </span>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

/** 重建地图标记：网格聚类 → 每个簇生成一个 divIcon 标点。 */
async function rebuildMarkers(
  layerGroup: L.LayerGroup,
  entries: JournalEntry[],
  zoom: number,
  onClusterClick: (cluster: EntryCluster) => void,
): Promise<void> {
  layerGroup.clearLayers();
  if (entries.length === 0) return;

  const clusters = clusterEntries(entries, zoom);
  const markers = await Promise.all(
    clusters.map((c) => buildMarker(c, onClusterClick)),
  );
  markers.forEach((m) => layerGroup.addLayer(m));
}

/** 为一个聚簇构建 Leaflet 标记（含图片缩略解析与点击行为）。 */
async function buildMarker(
  cluster: EntryCluster,
  onClick: (cluster: EntryCluster) => void,
): Promise<L.Marker> {
  const rep = cluster.representative;
  const cover = firstCoverAsset(rep.assets);
  let thumbUrl: string | null = null;
  if (cover) {
    // 优先 256px 列表缩略图，不存在则回退原资产。
    try {
      const rel = cover.path;
      thumbUrl =
        (await getStorage().resolveUrl(thumbnailPath(rel)).catch(() => "")) ||
        (await getStorage().resolveUrl(rel).catch(() => ""));
    } catch {
      thumbUrl = null;
    }
  }

  const icon = L.divIcon({
    className: "tdt-marker",
    iconSize: [76, 82],
    // 锚点对准底部红点针尖：48px 图块 + 4px 间距 + 10px 圆点 = 62px。
    // 让标点指针精确指向真实坐标，而不是对齐到图标顶部。
    iconAnchor: [38, 62],
    html: markerHtml(cluster.entries.length, thumbUrl),
  });

  const marker = L.marker([cluster.lat, cluster.lon], {
    icon,
    title:
      cluster.entries.length > 1
        ? `${cluster.entries.length} 篇日记`
        : rep.title || undefined,
  });
  marker.on("click", () => onClick(cluster));
  return marker;
}

/** 与移动端 _GroupMarker 同构的标记 HTML：缩略圆/图标圆 + 红色计数角标 + 红点。 */
function markerHtml(count: number, thumbUrl: string | null): string {
  const badge =
    count > 1
      ? `<span style="position:absolute;right:-6px;bottom:-6px;min-width:20px;height:18px;padding:0 6px;border-radius:12px;background:#ff5252;color:#fff;font-size:11px;font-weight:700;line-height:18px;text-align:center;border:2px solid #fff;box-shadow:0 2px 4px rgba(0,0,0,.26);box-sizing:border-box;">${count}</span>`
      : "";
  const box = thumbUrl
    ? `<div style="width:48px;height:48px;border-radius:12px;background-size:cover;background-position:center;background-image:url('${thumbUrl}');border:2px solid #fff;box-shadow:0 2px 4px rgba(0,0,0,.26);"></div>`
    : `<div style="width:48px;height:48px;border-radius:12px;background:#673AB7;display:flex;align-items:center;justify-content:center;border:2px solid #fff;box-shadow:0 2px 4px rgba(0,0,0,.26);"><span style="color:#fff;display:flex;">${docGlyph()}</span></div>`;
  return `
    <div style="display:flex;flex-direction:column;align-items:center;width:76px;">
      <div style="position:relative;">
        ${box}
        ${badge}
      </div>
      <div style="width:10px;height:10px;border-radius:5px;background:#ff5252;border:2px solid #fff;margin-top:4px;"></div>
    </div>`;
}

/** 白色文档图标字符（inline SVG，与 lucide FileText 一致）。 */
function docGlyph(): string {
  return `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/></svg>`;
}
