import { useMemo, useState } from "react";
import { Smile, CloudSun } from "lucide-react";
import { Card } from "@/components/ui/card";
import { MOODS, WEATHERS } from "@/lib/constants";
import { cn } from "@/lib/utils";
import type { JournalEntry } from "@/types/journal";

/** 单个柱状图类别：字形（moodfont/iconfont）+ 标签 + 计数。 */
interface Cat {
  key: string;
  label: string;
  char: string;
  font: "font-mood" | "font-icon";
  count: number;
}

type CatSpec = Omit<Cat, "count">;

function distribution(
  entries: JournalEntry[],
  pick: (e: JournalEntry) => string,
  cats: CatSpec[],
): Cat[] {
  const map = new Map<string, number>();
  for (const e of entries) {
    const k = pick(e);
    map.set(k, (map.get(k) ?? 0) + 1);
  }
  return cats
    .map((c) => ({ ...c, count: map.get(c.key) ?? 0 }))
    .sort((a, b) => b.count - a.count);
}

const MOOD_CATS: CatSpec[] = MOODS.map((m) => ({
  key: m.key,
  label: m.label,
  char: m.char,
  font: "font-mood" as const,
}));
const WEATHER_CATS: CatSpec[] = WEATHERS.filter((w) => w.key !== "unknown").map(
  (w) => ({ key: w.key, label: w.label, char: w.char, font: "font-icon" as const }),
);

/**
 * 心情 / 天气分布统计卡 —— 与移动端「我的」页同款：
 * 顶部 Tab 切换（心情 | 天气），强调色渐变柱状图统计全部日记，
 * 0 值显示中性空槽。柱底为心情/天气矢量图标 + 中文标签。
 */
export function DistributionCard({ entries }: { entries: JournalEntry[] }) {
  const [showMood, setShowMood] = useState(true);

  const moodData = useMemo(
    () => distribution(entries, (e) => e.mood, MOOD_CATS),
    [entries],
  );
  const weatherData = useMemo(
    () => distribution(entries, (e) => e.weather, WEATHER_CATS),
    [entries],
  );

  const data = showMood ? moodData : weatherData;
  const total = data.reduce((s, d) => s + d.count, 0);
  const maxCount = data.reduce((m, d) => Math.max(m, d.count), 0) || 1;
  const primary = "hsl(var(--primary))";

  return (
    <Card className="p-5">
      <div className="flex items-center justify-between">
        <h3 className="flex items-center gap-1.5 text-base font-semibold">
          {showMood ? (
            <Smile className="h-4 w-4 text-muted-foreground" />
          ) : (
            <CloudSun className="h-4 w-4 text-muted-foreground" />
          )}
          {showMood ? "心情统计" : "天气统计"}
        </h3>
        <span className="text-xs text-muted-foreground">
          {total === 0 ? "暂无记录" : `共 ${total} 次`}
        </span>
      </div>

      {/* Tab 切换（与移动端 SegmentedButton 同款的胶囊分段） */}
      <div className="mt-3 flex w-fit items-center rounded-full bg-muted p-0.5">
        {(
          [
            [true, "心情"],
            [false, "天气"],
          ] as [boolean, string][]
        ).map(([v, label]) => (
          <button
            key={label}
            type="button"
            onClick={() => setShowMood(v)}
            className={cn(
              "rounded-full px-3.5 py-1 text-sm transition-colors",
              showMood === v
                ? "bg-card text-foreground shadow-soft"
                : "text-muted-foreground hover:text-foreground",
            )}
          >
            {label}
          </button>
        ))}
      </div>

      {total === 0 ? (
        <p className="py-8 text-center text-sm text-muted-foreground">
          还没有记录
        </p>
      ) : (
        <>
          {/* 柱状图：132px 高，强调色渐变，0 值为中性空槽 */}
          <div className="mt-4 flex h-[132px] items-end gap-1">
            {data.map((d) => {
              const ratio = maxCount === 0 ? 0 : d.count / maxCount;
              const barH = 10 + ratio * 100; // 最小 10，最大 110
              const isZero = d.count === 0;
              return (
                <div
                  key={d.key}
                  className="flex min-w-0 flex-1 flex-col items-center self-stretch justify-end"
                >
                  <span
                    className={cn(
                      "text-xs font-semibold",
                      isZero ? "text-muted-foreground" : "text-foreground",
                    )}
                  >
                    {d.count}
                  </span>
                  <div
                    className="mt-1 w-full rounded-t-md"
                    style={
                      isZero
                        ? {
                            height: barH,
                            backgroundColor: "hsl(var(--muted))",
                            border: "1px solid hsl(var(--border))",
                          }
                        : {
                            height: barH,
                            background: `linear-gradient(to bottom, ${primary}, hsl(var(--primary) / 0.5))`,
                          }
                    }
                  />
                </div>
              );
            })}
          </div>

          {/* 柱底图标 + 标签 */}
          <div className="mt-2 flex gap-1">
            {data.map((d) => (
              <div
                key={d.key}
                className="flex min-w-0 flex-1 flex-col items-center gap-1"
              >
                <span
                  className={cn(d.font, "text-base leading-none text-muted-foreground")}
                >
                  {d.char}
                </span>
                <span className="text-[11px] text-muted-foreground">
                  {d.label}
                </span>
              </div>
            ))}
          </div>
        </>
      )}
    </Card>
  );
}
