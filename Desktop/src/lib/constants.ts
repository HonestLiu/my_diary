import type { Mood, Weather } from "@/types/journal";

export interface MoodInfo {
  key: Mood;
  label: string;
  emoji: string;
  /** Tailwind-friendly accent color (hsl) for chips. */
  color: string;
}

export const MOODS: MoodInfo[] = [
  { key: "happy", label: "开心", emoji: "😊", color: "hsl(45 90% 60%)" },
  { key: "excited", label: "兴奋", emoji: "🤩", color: "hsl(20 90% 60%)" },
  { key: "calm", label: "平静", emoji: "😌", color: "hsl(200 70% 65%)" },
  { key: "neutral", label: "普通", emoji: "😐", color: "hsl(40 10% 60%)" },
  { key: "tired", label: "疲惫", emoji: "😪", color: "hsl(260 30% 60%)" },
  { key: "sad", label: "难过", emoji: "😢", color: "hsl(220 50% 60%)" },
  { key: "angry", label: "生气", emoji: "😠", color: "hsl(0 70% 60%)" },
];

export const MOOD_MAP: Record<Mood, MoodInfo> = Object.fromEntries(
  MOODS.map((m) => [m.key, m]),
) as Record<Mood, MoodInfo>;

export interface WeatherInfo {
  key: Weather;
  label: string;
  emoji: string;
}

export const WEATHERS: WeatherInfo[] = [
  { key: "sunny", label: "晴", emoji: "☀️" },
  { key: "cloudy", label: "多云", emoji: "⛅" },
  { key: "rainy", label: "雨", emoji: "🌧️" },
  { key: "snowy", label: "雪", emoji: "❄️" },
  { key: "foggy", label: "雾", emoji: "🌫️" },
  { key: "windy", label: "风", emoji: "💨" },
  { key: "unknown", label: "未知", emoji: "🌡️" },
];

export const WEATHER_MAP: Record<Weather, WeatherInfo> = Object.fromEntries(
  WEATHERS.map((w) => [w.key, w]),
) as Record<Weather, WeatherInfo>;
