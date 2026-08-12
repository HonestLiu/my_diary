import { useMemo } from "react";
import { useAppStore } from "@/store/appStore";
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card";
import { formatDateKey } from "@/lib/utils";
import type { Mood } from "@/types/journal";

// Map each mood to a 1..5 sentiment score for trend aggregation.
const SCORE: Record<Mood, number> = {
  happy: 5,
  excited: 5,
  calm: 4,
  neutral: 3,
  tired: 2,
  sad: 1,
  angry: 1,
};

const WEEKS = 18;

/**
 * Zero-dependency SVG insight card: a monthly mood trend line plus a
 * GitHub-style writing-frequency heatmap colored by mood intensity.
 * Uses CSS variables so it adapts to light/dark automatically.
 */
export function MoodTrend() {
  const entries = useAppStore((s) => s.entries);

  const { series, byDate } = useMemo(() => {
    const byMonth: Record<string, { sum: number; n: number }> = {};
    const map: Record<string, number> = {};
    for (const e of entries) {
      const m = e.date.slice(0, 7);
      const s = SCORE[e.mood] ?? 3;
      const bucket = (byMonth[m] ??= { sum: 0, n: 0 });
      bucket.sum += s;
      bucket.n += 1;
      map[e.date] = s;
    }
    const months = Object.keys(byMonth).sort();
    const ser = months.map((m) => {
      const b = byMonth[m] ?? { sum: 0, n: 0 };
      return { month: m, avg: b.sum / b.n };
    });
    return { series: ser, byDate: map };
  }, [entries]);

  // ---- Line chart (SVG, viewBox 0..600 x 0..160) ----
  const W = 600;
  const H = 160;
  const pad = 24;
  const n = series.length;
  const xAt = (i: number) =>
    n <= 1 ? W / 2 : pad + (i * (W - pad * 2)) / (n - 1);
  const yAt = (v: number) => H - pad - ((v - 1) / 4) * (H - pad * 2);
  const pts = series.map((s, i) => `${xAt(i).toFixed(1)},${yAt(s.avg).toFixed(1)}`);
  const linePath = pts.length ? "M" + pts.join(" L") : "";
  const areaPath = pts.length
    ? `M${xAt(0).toFixed(1)},${(H - pad).toFixed(1)} L` +
      pts.join(" L") +
      ` L${xAt(n - 1).toFixed(1)},${(H - pad).toFixed(1)} Z`
    : "";

  // ---- Heatmap cells (WEEKS columns x 7 rows) ----
  const cells: { key: string; score?: number }[] = [];
  const end = new Date();
  for (let i = WEEKS * 7 - 1; i >= 0; i--) {
    const d = new Date(end);
    d.setDate(end.getDate() - i);
    const key = formatDateKey(d);
    cells.push({ key, score: byDate[key] });
  }
  const firstDow = new Date((cells[0]?.key ?? formatDateKey()) + "T00:00:00").getDay(); // 0=Sun
  for (let i = 0; i < firstDow; i++) cells.unshift({ key: "" });

  const cell = 13;
  const gap = 3;
  const gridW = WEEKS * (cell + gap);
  const gridH = 7 * (cell + gap);

  return (
    <Card>
      <CardHeader>
        <CardTitle>心情与习惯</CardTitle>
      </CardHeader>
      <CardContent className="space-y-6">
        {/* Monthly mood trend */}
        <div>
          <div className="mb-2 text-xs text-muted-foreground">月度心情走势</div>
          {series.length === 0 ? (
            <div className="rounded-xl border border-border bg-muted/40 p-6 text-center text-sm text-muted-foreground">
              还没有足够数据，写几篇日记后这里会出现曲线。
            </div>
          ) : (
            <svg
              viewBox={`0 0 ${W} ${H}`}
              className="w-full"
              role="img"
              aria-label="月度心情走势图"
            >
              <defs>
                <linearGradient id="moodArea" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="hsl(var(--primary))" stopOpacity="0.25" />
                  <stop offset="100%" stopColor="hsl(var(--primary))" stopOpacity="0" />
                </linearGradient>
              </defs>
              {[1, 3, 5].map((g) => (
                <line
                  key={g}
                  x1={pad}
                  x2={W - pad}
                  y1={yAt(g)}
                  y2={yAt(g)}
                  stroke="hsl(var(--border))"
                  strokeWidth={1}
                />
              ))}
              {areaPath && <path d={areaPath} fill="url(#moodArea)" />}
              {linePath && (
                <path
                  d={linePath}
                  fill="none"
                  stroke="hsl(var(--primary))"
                  strokeWidth={2.5}
                  strokeLinejoin="round"
                  strokeLinecap="round"
                />
              )}
              {series.map((s, i) => (
                <circle
                  key={s.month}
                  cx={xAt(i)}
                  cy={yAt(s.avg)}
                  r={3.5}
                  fill="hsl(var(--primary))"
                />
              ))}
            </svg>
          )}
          {series.length > 0 && (
            <div className="mt-1 flex justify-between text-[11px] text-muted-foreground">
              <span>{series.at(0)?.month}</span>
              <span>{series.at(-1)?.month}</span>
            </div>
          )}
        </div>

        {/* Writing heatmap */}
        <div>
          <div className="mb-2 text-xs text-muted-foreground">
            写作频率（最近 {WEEKS} 周，颜色越深心情越好）
          </div>
          <svg
            viewBox={`0 0 ${gridW} ${gridH}`}
            className="w-full"
            style={{ maxWidth: gridW }}
            role="img"
            aria-label="写作频率热力图"
          >
            {cells.map((c, idx) => {
              const col = Math.floor(idx / 7);
              const row = idx % 7;
              const x = col * (cell + gap);
              const y = row * (cell + gap);
              if (!c.key) return <rect key={idx} x={x} y={y} width={cell} height={cell} rx={3} fill="transparent" />;
              const score = c.score ?? 0;
              const opacity = score ? 0.25 + (score / 5) * 0.75 : 0.08;
              const fill = score
                ? "hsl(var(--primary))"
                : "hsl(var(--muted-foreground))";
              return (
                <rect
                  key={c.key}
                  x={x}
                  y={y}
                  width={cell}
                  height={cell}
                  rx={3}
                  fill={fill}
                  fillOpacity={opacity}
                >
                  <title>{c.key}</title>
                </rect>
              );
            })}
          </svg>
          <div className="mt-2 flex items-center gap-2 text-[11px] text-muted-foreground">
            少
            {[0.08, 0.35, 0.55, 0.75, 1].map((o, i) => (
              <span
                key={i}
                className="inline-block h-3 w-3 rounded"
                style={{ background: "hsl(var(--primary))", opacity: o }}
              />
            ))}
            多
          </div>
        </div>

        <p className="text-[11px] text-muted-foreground">
          数据来自本地日记，不上传任何服务器。
        </p>
      </CardContent>
    </Card>
  );
}
