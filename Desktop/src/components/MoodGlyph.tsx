import type { Mood } from "@/types/journal";
import { MOOD_MAP } from "@/lib/constants";

/**
 * 心情矢量图标（moodfont 字形，与移动端同款），色随 currentColor。
 * mood 为 null/undefined 时返回 null。
 */
export function MoodGlyph({
  mood,
  className,
}: {
  mood: Mood | null | undefined;
  className?: string;
}) {
  const m = mood ? MOOD_MAP[mood] : undefined;
  if (!m) return null;
  return (
    <span className={`font-mood leading-none ${className ?? ""}`} aria-hidden>
      {m.char}
    </span>
  );
}
