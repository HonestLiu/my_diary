import { useEffect, useRef, useState } from "react";
import L from "leaflet";
import { Loader2, LocateFixed, Search, X } from "lucide-react";
import { cn } from "@/lib/utils";
import {
  DEFAULT_CENTER,
  TDT_TYPE_INFO,
  isMapConfigured,
  TdtMapType,
} from "@/lib/map/config";
import { createTdtLayers } from "@/lib/map/tiles";
import { getCurrentPosition } from "@/lib/map/geolocation";
import { geocodePlace, reverseGeocode } from "@/lib/map/geocode";
import { Button } from "@/components/ui/button";

export interface MapPickResult {
  lat: number;
  lon: number;
  name: string;
}

interface MapPickerProps {
  initialLat?: number;
  initialLon?: number;
  initialName?: string;
  onConfirm: (result: MapPickResult) => void;
  onClose: () => void;
}

const PICK_ZOOM = 14;
const LOCATE_ZOOM = 15;

/**
 * 地图选点弹窗 —— 与移动端 MapPickerPage 同构：
 * 点击落点 + 逆地理编码回填地址，支持地址搜索与一键定位。
 * 确定后回传 {lat, lon, name}。
 */
export function MapPicker({
  initialLat,
  initialLon,
  initialName,
  onConfirm,
  onClose,
}: MapPickerProps) {
  const mapEl = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<L.Map | null>(null);
  const tileLayersRef = useRef<L.TileLayer[]>([]);
  const pinRef = useRef<L.Marker | null>(null);
  const [ready, setReady] = useState(false);
  const [mapType, setMapType] = useState<TdtMapType>(TdtMapType.vector);
  const [name, setName] = useState(initialName ?? "");
  const [search, setSearch] = useState("");
  const [geocoding, setGeocoding] = useState(false);
  const [searching, setSearching] = useState(false);
  const [locating, setLocating] = useState(false);
  const [error, setError] = useState("");
  const [picked, setPicked] = useState<{ lat: number; lon: number } | null>(
    initialLat != null && initialLon != null
      ? { lat: initialLat, lon: initialLon }
      : null,
  );

  // ---- Leaflet init (once) ----
  useEffect(() => {
    if (!mapEl.current || mapRef.current) return;
    const map = L.map(mapEl.current, {
      center:
        initialLat != null && initialLon != null
          ? [initialLat, initialLon]
          : DEFAULT_CENTER,
      zoom: initialLat != null ? PICK_ZOOM : 10,
      minZoom: 0,
      maxZoom: 20,
      zoomControl: false,
      attributionControl: false,
    });
    mapRef.current = map;
    map.on("click", (ev: L.LeafletMouseEvent) => {
      void dropPin(ev.latlng.lat, ev.latlng.lng);
    });
    setReady(true);
    return () => {
      map.remove();
      mapRef.current = null;
      tileLayersRef.current = [];
      pinRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ---- Tile layers follow map type ----
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    tileLayersRef.current.forEach((t) => t.remove());
    tileLayersRef.current = createTdtLayers(mapType);
    tileLayersRef.current.forEach((t) => t.addTo(map));
  }, [mapType, ready]);

  // ---- Initial pin ----
  useEffect(() => {
    if (!ready || pinRef.current) return;
    if (initialLat != null && initialLon != null) {
      void dropPin(initialLat, initialLon);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ready]);

  async function dropPin(lat: number, lon: number) {
    const map = mapRef.current;
    if (!map) return;
    setPicked({ lat, lon });
    setGeocoding(true);
    setError("");
    if (!pinRef.current) {
      pinRef.current = L.marker([lat, lon], {
        icon: pinIcon(),
        zIndexOffset: 1000,
      }).addTo(map);
    } else {
      pinRef.current.setLatLng([lat, lon]);
    }
    const addr = await reverseGeocode(lat, lon);
    if (addr) setName(addr);
    setGeocoding(false);
  }

  async function searchAddress() {
    const kw = search.trim();
    if (!kw) return;
    setSearching(true);
    setError("");
    const place = await geocodePlace(kw);
    setSearching(false);
    const map = mapRef.current;
    if (!place || !map) {
      setError("未找到匹配地址，请尝试更具体的名称");
      return;
    }
    setName(place.name);
    setPicked({ lat: place.lat, lon: place.lon });
    if (!pinRef.current) {
      pinRef.current = L.marker([place.lat, place.lon], {
        icon: pinIcon(),
        zIndexOffset: 1000,
      }).addTo(map);
    } else {
      pinRef.current.setLatLng([place.lat, place.lon]);
    }
    map.flyTo([place.lat, place.lon], PICK_ZOOM);
  }

  async function locate() {
    setLocating(true);
    setError("");
    const pos = await getCurrentPosition();
    setLocating(false);
    const map = mapRef.current;
    if (!pos || !map) {
      setError("无法获取定位，请检查系统定位权限");
      return;
    }
    map.flyTo([pos.latitude, pos.longitude], LOCATE_ZOOM);
    await dropPin(pos.latitude, pos.longitude);
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-6"
      onClick={onClose}
    >
      <div
        className="flex h-[85vh] w-full max-w-3xl flex-col overflow-hidden rounded-2xl border border-border bg-card shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        {/* 头部 */}
        <div className="flex items-center justify-between border-b border-border px-5 py-3.5">
          <h2 className="text-base font-semibold text-foreground">选择位置</h2>
          <div className="flex items-center gap-2">
            <div className="flex items-center gap-1 rounded-full border border-border bg-muted p-1">
              {(Object.keys(TDT_TYPE_INFO) as TdtMapType[]).map((t) => (
                <button
                  key={t}
                  type="button"
                  onClick={() => setMapType(t)}
                  className={cn(
                    "rounded-full px-3 py-1 text-xs transition-colors",
                    mapType === t
                      ? "bg-accent text-accent-foreground"
                      : "text-muted-foreground hover:bg-card",
                  )}
                >
                  {TDT_TYPE_INFO[t].label}
                </button>
              ))}
            </div>
            <button
              type="button"
              onClick={onClose}
              aria-label="关闭"
              className="rounded-lg p-1.5 text-muted-foreground transition-colors hover:bg-muted"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        </div>

        {/* 地图 + 搜索 */}
        <div className="relative min-h-0 flex-1">
          {!isMapConfigured ? (
            <div className="flex h-full items-center justify-center">
              <p className="max-w-sm text-center text-sm text-muted-foreground">
                未配置天地图密钥，无法加载地图
                <br />
                请在 src/lib/map/config.ts 中填写 Key
              </p>
            </div>
          ) : (
            <div ref={mapEl} className="h-full w-full" />
          )}

          {/* 地址搜索栏 */}
          <div className="absolute left-3 right-14 top-3">
            <div className="flex items-center gap-2 rounded-full border border-border bg-card px-3 py-1.5 shadow-soft">
              <Search className="h-4 w-4 shrink-0 text-muted-foreground" />
              <input
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    e.preventDefault();
                    void searchAddress();
                  }
                }}
                placeholder="搜索地址 / 地点"
                className="w-full bg-transparent text-sm text-foreground outline-none placeholder:text-muted-foreground"
              />
              {searching ? (
                <Loader2 className="h-4 w-4 shrink-0 animate-spin text-muted-foreground" />
              ) : (
                <button
                  type="button"
                  onClick={() => void searchAddress()}
                  aria-label="搜索"
                  className="shrink-0 rounded-full p-1 text-muted-foreground transition-colors hover:bg-muted hover:text-primary"
                >
                  <Search className="h-4 w-4" />
                </button>
              )}
            </div>
          </div>

          {/* 定位按钮 */}
          <button
            type="button"
            onClick={() => void locate()}
            disabled={locating}
            aria-label="定位"
            className="absolute right-3 top-3 flex h-9 w-9 items-center justify-center rounded-xl border border-border bg-card text-foreground shadow-soft transition-colors hover:bg-muted disabled:opacity-60"
          >
            {locating ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <LocateFixed className="h-4 w-4" />
            )}
          </button>

          {/* 版权 */}
          <span className="absolute bottom-2 right-2 rounded bg-black/60 px-1.5 py-0.5 text-[11px] text-white">
            © 天地图
          </span>
        </div>

        {/* 底部：已选点信息 + 确认 */}
        <div className="border-t border-border px-5 py-3.5">
          {picked ? (
            <div className="flex items-center gap-3">
              <div className="min-w-0 flex-1">
                <input
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="地点名称（可修改）"
                  className="w-full rounded-lg border border-border bg-muted px-3 py-1.5 text-sm font-medium text-foreground outline-none focus:border-primary"
                />
                <div className="mt-1 flex items-center gap-1.5 text-xs text-muted-foreground">
                  {geocoding && (
                    <Loader2 className="h-3 w-3 animate-spin" />
                  )}
                  <span>
                    {picked.lat.toFixed(5)}, {picked.lon.toFixed(5)}
                  </span>
                </div>
              </div>
              {error && (
                <span className="max-w-[180px] shrink-0 text-xs text-red-500">
                  {error}
                </span>
              )}
              <Button
                onClick={() => onConfirm({ lat: picked.lat, lon: picked.lon, name: name.trim() })}
              >
                确定
              </Button>
            </div>
          ) : (
            <div className="flex items-center justify-between">
              <span className="text-sm text-muted-foreground">
                在地图上点击选择位置
              </span>
              {error && <span className="text-xs text-red-500">{error}</span>}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

/** 选点红色大头针。 */
function pinIcon(): L.DivIcon {
  return L.divIcon({
    className: "tdt-marker",
    iconSize: [40, 40],
    iconAnchor: [20, 38],
    html: `<span style="display:block;width:36px;height:36px;color:#ff5252;">${pinSvg()}</span>`,
  });
}

function pinSvg(): string {
  return `<svg width="36" height="36" viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 10c0 4.993-5.539 10.193-7.399 11.799a1 1 0 0 1-1.202 0C9.539 20.193 4 14.993 4 10a8 8 0 0 1 16 0"/><circle cx="12" cy="10" r="3"/></svg>`;
}
