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

// Writing-frequency heatmap greens (intensity 1..4).
const EMPTY = "hsl(var(--muted-foreground))";
const LEVELS = ["#dcfce7", "#86efac", "#4ade80", "#16a34a"];
const levelFor = (words: number) => {
  if (words <= 0) return -1;
  if (words < 300) return 0;
  if (words < 800) return 1;
  if (words < 1500) return 2;
  return 3;
};

const WEEKS = 18;

// Catmull-Rom -> cubic bezier smoothing for a polished curve.
function smoothPath(pts: [number, number][]): string {
  if (pts.length === 0) return "";
  if (pts.length === 1) return `M${pts[0]![0]},${pts[0]![1]}`;
  let d = `M${pts[0]![0].toFixed(1)},${pts[0]![1].toFixed(1)}`;
  for (let i = 0; i < pts.length - 1; i++) {
    const p1 = pts[i]!;
    const p2 = pts[i + 1]!;
    const p0 = pts[i - 1] ?? p1;
    const p3 = pts[i + 2] ?? p2;
    const c1x = p1[0] + (p2[0] - p0[0]) / 6;
    const c1y = p1[1] + (p2[1] - p0[1]) / 6;
    const c2x = p2[0] - (p3[0] - p1[0]) / 6;
    const c2y = p2[1] - (p3[1] - p1[1]) / 6;
    d += ` C${c1x.toFixed(1)},${c1y.toFixed(1)} ${c2x.toFixed(1)},${c2y.toFixed(1)} ${p2[0].toFixed(1)},${p2[1].toFixed(1)}`;
  }
  return d;
}

/**
 * Zero-dependency SVG insight card: a smoothed mood trend line plus a
 * GitHub-style writing-frequency heatmap. Both adapt to light/dark via
 * CSS variables where appropriate.
 */
export function MoodTrend() {
  const entries = useAppStore((s) => s.entries);
  const streak = useAppStore((s) => s.streak);

  const { series, byDateWords, thisMonthDays } = useMemo(() => {
    const byMonth: Record<string, { sum: number; n: number }> = {};
    const words: Record<string, number> = {};
    const ym = formatDateKey().slice(0, 7);
    let monthDays = 0;
    for (const e of entries) {
      const m = e.date.slice(0, 7);
      const s = SCORE[e.mood] ?? 3;
      const bucket = (byMonth[m] ??= { sum: 0, n: 0 });
      bucket.sum += s;
      bucket.n += 1;
      words[e.date] = (words[e.date] ?? 0) + (e.body?.length ?? 0);
      if (e.date.slice(0, 7) === ym) monthDays += 1;
    }
    const months = Object.keys(byMonth).sort();
    const ser = months.map((m) => {
      const b = byMonth[m] ?? { sum: 0, n: 0 };
      return { month: m, avg: b.sum / b.n };
    });
    return { series: ser, byDateWords: words, thisMonthDays: monthDays };
  }, [entries]);

  // ---- Mood line chart ----
  const W = 320;
  const H = 150;
  const padL = 8;
  const padR = 10;
  const padT = 12;
  const padB = 18;
  const plotW = W - padL - padR;
  const plotH = H - padT - padB;
  const n = series.length;
  const xAt = (i: number) =>
    n <= 1 ? padL + plotW / 2 : padL + (i * plotW) / (n - 1);
  const yAt = (v: number) => padT + ((5 - v) / 4) * plotH;
  const pts = series.map((s, i) => [xAt(i), yAt(s.avg)] as [number, number]);
  const linePath = smoothPath(pts);
  const areaPath = pts.length
    ? smoothPath(pts) +
      ` L${xAt(n - 1).toFixed(1)},${(padT + plotH).toFixed(1)}` +
      ` L${xAt(0).toFixed(1)},${(padT + plotH).toFixed(1)} Z`
    : "";
  const yLabels: [number, string][] = [
    [1, "低落"],
    [3, "平稳"],
    [5, "愉悦"],
  ];

  const avgNow = series.at(-1)?.avg ?? 0;
  const avgPrev = series.length > 1 ? (series.at(-2)?.avg ?? avgNow) : avgNow;
  const delta = avgNow - avgPrev;

  // ---- Heatmap cells ----
  const cell = 14;
  const gap = 3;
  const leftPad = 16;
  const topPad = 16;
  const gridW = WEEKS * (cell + gap);
  const gridH = 7 * (cell + gap);
  const end = new Date();
  const raw: { key: string; words: number }[] = [];
  for (let i = WEEKS * 7 - 1; i >= 0; i--) {
    const d = new Date(end);
    d.setDate(end.getDate() - i);
    const key = formatDateKey(d);
    raw.push({ key, words: byDateWords[key] ?? 0 });
  }
  const firstDow = new Date((raw[0]?.key ?? formatDateKey()) + "T00:00:00").getDay();
  const cells: { key: string; words: number }[] = [];
  for (let i = 0; i < firstDow; i++) cells.push({ key: "", words: 0 });
  cells.push(...raw);

  // Month labels (top) keyed by column index.
  const monthLabels: { col: number; label: string }[] = [];
  let lastMonth = "";
  for (let c = 0; c < WEEKS; c++) {
    const top = cells[c * 7];
    if (!top || !top.key) continue;
    const mm = top.key.slice(5, 7);
    if (mm !== lastMonth) {
      monthLabels.push({ col: c, label: `${Number(mm)}月` });
      lastMonth = mm;
    }
  }
  const weekdayLabels: [number, string][] = [
    [1, "一"],
    [3, "三"],
    [5, "五"],
  ];

  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between gap-3">
          <CardTitle>心情与习惯</CardTitle>
          {series.length > 0 && (
            <span
              className="flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium text-primary"
              style={{ background: "hsl(var(--primary) / 0.12)" }}
            >
              {delta >= 0 ? "▲" : "▼"} {avgNow.toFixed(1)}
            </span>
          )}
        </div>
      </CardHeader>
      <CardContent className="space-y-5">
        {/* Mood trend */}
        <div>
          <div className="mb-2 text-xs text-muted-foreground">月度心情走势</div>
          {series.length === 0 ? (
            <div className="rounded-xl border border-border bg-muted/40 p-6 text-center text-sm text-muted-foreground">
              还没有足够数据，写几篇日记后这里会出现曲线。
            </div>
          ) : (
            <div className="rounded-xl bg-muted/30 p-2">
              <svg
                viewBox={`0 0 ${W} ${H}`}
                className="mx-auto block w-full"
                style={{ maxWidth: 300 }}
                role="img"
                aria-label="月度心情走势图"
              >
                <defs>
                  <linearGradient id="moodArea" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="hsl(var(--primary))" stopOpacity="0.28" />
                    <stop offset="100%" stopColor="hsl(var(--primary))" stopOpacity="0" />
                  </linearGradient>
                </defs>
                {yLabels.map(([v, label]) => (
                  <g key={v}>
                    <line
                      x1={padL}
                      x2={W - padR}
                      y1={yAt(v)}
                      y2={yAt(v)}
                      stroke="hsl(var(--border))"
                      strokeWidth={1}
                    />
                    <text
                      x={2}
                      y={yAt(v) + 3}
                      fontSize={8}
                      fill="hsl(var(--muted-foreground))"
                    >
                      {label}
                    </text>
                  </g>
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
                    stroke="hsl(var(--card))"
                    strokeWidth={1.5}
                  >
                    <title>{`${s.month} · ${s.avg.toFixed(1)}`}</title>
                  </circle>
                ))}
                {series.length > 1 && (
                  <>
                    <text
                      x={padL}
                      y={H - 5}
                      fontSize={8}
                      fill="hsl(var(--muted-foreground))"
                    >
                      {series[0]?.month}
                    </text>
                    <text
                      x={W - padR}
                      y={H - 5}
                      fontSize={8}
                      fill="hsl(var(--muted-foreground))"
                      textAnchor="end"
                    >
                      {series.at(-1)?.month}
                    </text>
                  </>
                )}
              </svg>
            </div>
          )}
        </div>

        {/* Writing habit heatmap */}
        <div>
          <div className="mb-2 flex items-center justify-between text-xs text-muted-foreground">
            <span>写作习惯（最近 {WEEKS} 周）</span>
            <span>
              本月 {thisMonthDays} 天 · 连续 {streak} 天
            </span>
          </div>
          <div className="rounded-xl bg-muted/30 p-2">
            <svg
              viewBox={`0 0 ${leftPad + gridW} ${topPad + gridH}`}
              className="mx-auto block w-full"
              style={{ maxWidth: 360 }}
              role="img"
              aria-label="写作频率热力图"
            >
              {monthLabels.map((m) => (
                <text
                  key={m.col}
                  x={leftPad + m.col * (cell + gap)}
                  y={11}
                  fontSize={8}
                  fill="hsl(var(--muted-foreground))"
                >
                  {m.label}
                </text>
              ))}
              {weekdayLabels.map(([row, label]) => (
                <text
                  key={row}
                  x={leftPad - 3}
                  y={topPad + row * (cell + gap) + cell / 2 + 3}
                  fontSize={8}
                  textAnchor="end"
                  fill="hsl(var(--muted-foreground))"
                >
                  {label}
                </text>
              ))}
              {cells.map((c, idx) => {
                const col = Math.floor(idx / 7);
                const row = idx % 7;
                const x = leftPad + col * (cell + gap);
                const y = topPad + row * (cell + gap);
                if (!c.key)
                  return (
                    <rect key={idx} x={x} y={y} width={cell} height={cell} rx={2.5} fill="transparent" />
                  );
                const lvl = levelFor(c.words);
                const fill = lvl < 0 ? EMPTY : LEVELS[lvl] ?? EMPTY;
                return (
                  <rect
                    key={c.key}
                    x={x}
                    y={y}
                    width={cell}
                    height={cell}
                    rx={2.5}
                    fill={fill}
                    fillOpacity={lvl < 0 ? 0.15 : 1}
                  >
                    <title>{`${c.key} · ${c.words} 字`}</title>
                  </rect>
                );
              })}
            </svg>
          </div>
          <div className="mt-2 flex items-center gap-1.5 text-[11px] text-muted-foreground">
            少
            <span
              className="inline-block h-3 w-3 rounded"
              style={{ background: EMPTY, opacity: 0.15 }}
            />
            {LEVELS.map((c, i) => (
              <span key={i} className="inline-block h-3 w-3 rounded" style={{ background: c }} />
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
