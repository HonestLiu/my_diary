import type { Mood, Weather } from "@/types/journal";

export interface MoodInfo {
  key: Mood;
  label: string;
  /** 心情矢量图标字形（moodfont，与移动端同款），UI 用 `font-mood` 渲染。 */
  char: string;
  /** 导出 HTML 等自包含场景的兜底 emoji。 */
  emoji: string;
}

export const MOODS: MoodInfo[] = [
  { key: "happy", label: "开心", char: "", emoji: "😊" },
  { key: "excited", label: "兴奋", char: "", emoji: "🤩" },
  { key: "calm", label: "平静", char: "", emoji: "😌" },
  { key: "neutral", label: "普通", char: "", emoji: "😐" },
  { key: "tired", label: "疲惫", char: "", emoji: "😪" },
  { key: "sad", label: "难过", char: "", emoji: "😢" },
  { key: "angry", label: "生气", char: "", emoji: "😠" },
];

export const MOOD_MAP: Record<Mood, MoodInfo> = Object.fromEntries(
  MOODS.map((m) => [m.key, m]),
) as Record<Mood, MoodInfo>;

export interface WeatherInfo {
  key: Weather;
  label: string;
  /** 天气矢量图标字形（iconfont，与移动端同款），UI 用 `font-icon` 渲染。 */
  char: string;
  /** 导出 HTML 等自包含场景的兜底 emoji。 */
  emoji: string;
}

export const WEATHERS: WeatherInfo[] = [
  { key: "sunny", label: "晴", char: "", emoji: "☀️" },
  { key: "cloudy", label: "多云", char: "", emoji: "⛅" },
  { key: "rainy", label: "雨", char: "", emoji: "🌧️" },
  { key: "snowy", label: "雪", char: "", emoji: "❄️" },
  { key: "foggy", label: "雾", char: "", emoji: "🌫️" },
  { key: "windy", label: "风", char: "", emoji: "💨" },
  { key: "unknown", label: "未知", char: "", emoji: "🌡️" },
];

export const WEATHER_MAP: Record<Weather, WeatherInfo> = Object.fromEntries(
  WEATHERS.map((w) => [w.key, w]),
) as Record<Weather, WeatherInfo>;
