import type { Weather } from "@/types/journal";
import { WEATHER_MAP } from "@/lib/constants";

/**
 * 天气矢量图标（iconfont 字形，与移动端同款），色随 currentColor。
 * weather 为 null/undefined 时返回 null。
 */
export function WeatherGlyph({
  weather,
  className,
}: {
  weather: Weather | null | undefined;
  className?: string;
}) {
  const w = weather ? WEATHER_MAP[weather] : undefined;
  if (!w) return null;
  return (
    <span className={`font-icon leading-none ${className ?? ""}`} aria-hidden>
      {w.char}
    </span>
  );
}
