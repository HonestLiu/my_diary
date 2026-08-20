import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { motion } from "framer-motion";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { useAppStore } from "@/store/appStore";
import { EntryCard } from "@/components/EntryCard";
import { MarkdownPreview } from "@/components/MarkdownPreview";
import { firstCoverAsset, entryFilePath } from "@/lib/vault";
import { cn, formatDateKey } from "@/lib/utils";
import type { JournalEntry } from "@/types/journal";

/**
 * Calendar — 与移动端日历视图保持一致，但利用桌面宽屏：
 * 左侧单月网格（今天/选中圆形高亮、有日记打点），右侧展示选中日期的
 * 日记列表（首页同款 EntryCard）。
 */
export default function Calendar() {
  const entries = useAppStore((s) => s.entries);
  const activeDate = useAppStore((s) => s.activeDate);
  const openEntry = useAppStore((s) => s.openEntry);
  const unsyncedPaths = useAppStore((s) => s.unsyncedPaths);
  const conflictPaths = useAppStore((s) => s.conflictPaths);
  const weekStartsOn = useAppStore((s) => s.settings.weekStartsOn);
  const navigate = useNavigate();

  const today = new Date();
  const [base, setBase] = useState({
    year: Number(activeDate.slice(0, 4)) || today.getFullYear(),
    month: (Number(activeDate.slice(5, 7)) - 1) || today.getMonth(),
  });
  const [selected, setSelected] = useState(
    activeDate || formatDateKey(today),
  );
  const [dir, setDir] = useState(1); // 月份切换方向，用于滑动动画

  const entriesByDate = useMemo(() => {
    const m = new Map<string, JournalEntry[]>();
    for (const e of entries) {
      const list = m.get(e.date);
      if (list) list.push(e);
      else m.set(e.date, [e]);
    }
    return m;
  }, [entries]);

  const cells = useMemo(
    () => buildMonthGrid(base.year, base.month, weekStartsOn),
    [base, weekStartsOn],
  );

  const shift = (delta: number) => {
    setDir(delta > 0 ? 1 : -1);
    setBase((v) => stepMonth(v, delta));
  };

  const jumpToToday = () => {
    const now = new Date();
    setDir(
      now.getFullYear() * 12 + now.getMonth() >= base.year * 12 + base.month
        ? 1
        : -1,
    );
    setBase({ year: now.getFullYear(), month: now.getMonth() });
    setSelected(formatDateKey(now));
  };

  const open = (e: JournalEntry) => {
    openEntry(e.id, e.date);
    navigate("/editor");
  };

  const mondayStart = weekStartsOn === 1;
  const weekdayLabels = mondayStart
    ? ["一", "二", "三", "四", "五", "六", "日"]
    : ["日", "一", "二", "三", "四", "五", "六"];

  const isThisMonth =
    today.getFullYear() === base.year && today.getMonth() === base.month;
  const items = entriesByDate.get(selected) ?? [];

  return (
    <div className="h-full overflow-y-auto px-6 py-6">
      <div className="mx-auto flex h-full max-w-[1500px] items-stretch gap-6">
        {/* 左列：月份卡片 + 页头（同移动端 AppBar）。 */}
        <div className="flex w-[420px] shrink-0 flex-col">
          <div className="mb-5 flex items-center justify-between">
            <h1 className="text-2xl font-bold tracking-tight text-foreground">
              {base.year} 年 {base.month + 1} 月
            </h1>
            <div className="flex items-center gap-1">
              <button
                type="button"
                onClick={() => shift(-1)}
                aria-label="上个月"
                className="flex h-9 w-9 items-center justify-center rounded-lg text-muted-foreground hover:bg-muted"
              >
                <ChevronLeft className="h-5 w-5" />
              </button>
              <button
                type="button"
                onClick={() => shift(1)}
                aria-label="下个月"
                className="flex h-9 w-9 items-center justify-center rounded-lg text-muted-foreground hover:bg-muted"
              >
                <ChevronRight className="h-5 w-5" />
              </button>
              <button
                type="button"
                onClick={jumpToToday}
                className="ml-2 rounded-lg px-3 py-1.5 text-sm text-muted-foreground transition-colors hover:bg-muted"
              >
                今天
              </button>
            </div>
          </div>

          {/* 月份卡片：星期行 + 网格，与移动端同款精致卡片。 */}
          <div className="rounded-2xl border border-border bg-card p-4 shadow-soft">
            <div className="grid grid-cols-7 gap-1.5 text-center text-xs font-semibold text-muted-foreground">
              {weekdayLabels.map((w) => (
                <div key={w} className="py-1">
                  {w}
                </div>
              ))}
            </div>
            <motion.div
              key={`${base.year}-${base.month}`}
              initial={{ opacity: 0, x: dir > 0 ? 24 : -24 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ duration: 0.28, ease: "easeOut" }}
              className="mt-2 grid grid-cols-7 gap-1.5"
            >
              {cells.map((cell, i) => {
                if (!cell) return <div key={`empty-${i}`} />;
                const dayEntries = entriesByDate.get(cell.key);
                const count = dayEntries?.length ?? 0;
                const isToday = isThisMonth && cell.day === today.getDate();
                const isSelected = cell.key === selected;
                return (
                  <DayCell
                    key={cell.key}
                    day={cell.day}
                    count={count}
                    isToday={isToday}
                    isSelected={isSelected}
                    onSelect={() => setSelected(cell.key)}
                  />
                );
              })}
            </motion.div>
          </div>
        </div>

        {/* 右列：选中日期的日记列表（首页同款卡片）。 */}
        <div className="min-w-0 flex-1 overflow-y-auto pr-1">
          <div className="flex items-center">
            <span className="h-4 w-[3px] rounded bg-primary" />
            <span className="ml-2 text-base font-semibold text-foreground">
              {dayLabel(selected)}
            </span>
            <span className="ml-auto text-xs text-muted-foreground">
              {items.length} 篇
            </span>
          </div>

          {items.length === 0 ? (
            <div className="flex flex-col items-center py-16 text-muted-foreground">
              <span className="text-4xl">🌱</span>
              <span className="mt-3 text-sm">这一天还没有日记</span>
            </div>
          ) : (
            <div className="mt-4 flex flex-col gap-3 pb-8">
              {items.map((e) => (
                <EntryCard
                  key={e.id}
                  title={e.title}
                  mood={e.mood}
                  weather={e.weather}
                  favorite={e.favorite}
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
                  unsynced={unsyncedPaths.has(
                    entryFilePath({ id: e.id, date: e.date }),
                  )}
                  conflict={conflictPaths.has(
                    entryFilePath({ id: e.id, date: e.date }),
                  )}
                  conflictPath={
                    conflictPaths.has(entryFilePath({ id: e.id, date: e.date }))
                      ? entryFilePath({ id: e.id, date: e.date })
                      : undefined
                  }
                  onClick={() => open(e)}
                />
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

/** 与移动端 _DayCell 同构：圆点 + 圆形选中/今天，有日记时下方打点。 */
function DayCell({
  day,
  count,
  isToday,
  isSelected,
  onSelect,
}: {
  day: number;
  count: number;
  isToday: boolean;
  isSelected: boolean;
  onSelect: () => void;
}) {
  const hasEntries = count > 0;
  const selected = isSelected && !isToday;
  const prominent = hasEntries || isToday || selected;

  return (
    <button
      type="button"
      onClick={onSelect}
      className={cn(
        "flex aspect-square flex-col items-center justify-center rounded-lg transition-opacity",
        prominent ? "opacity-100" : "opacity-45 hover:opacity-70",
      )}
    >
      <span
        className={cn(
          "flex h-[30px] w-[30px] items-center justify-center rounded-full text-sm transition-colors",
          isToday
            ? "bg-primary font-bold text-primary-foreground"
            : selected
              ? "bg-primary/15 font-bold text-primary"
              : prominent
                ? "font-bold text-foreground"
                : "font-medium text-foreground",
        )}
      >
        {day}
      </span>
      {hasEntries ? (
        <span
          className={cn(
            "mt-[3px] h-[5px] w-[5px] rounded-full",
            isToday ? "bg-primary-foreground" : "bg-primary",
          )}
        />
      ) : (
        <span className="mt-[3px] h-[5px] w-[5px]" />
      )}
    </button>
  );
}

interface Cell {
  key: string;
  day: number;
}

function buildMonthGrid(
  year: number,
  month: number,
  weekStartsOn: 0 | 1,
): (Cell | null)[] {
  const first = new Date(year, month, 1);
  // getDay(): 0 = Sunday … 6 = Saturday. Rotate so the chosen week-start
  // (Sunday or Monday) leads the grid.
  const startWeekday = (first.getDay() - weekStartsOn + 7) % 7;
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const cells: (Cell | null)[] = [];
  for (let i = 0; i < startWeekday; i++) cells.push(null);
  for (let d = 1; d <= daysInMonth; d++) {
    const mm = String(month + 1).padStart(2, "0");
    const dd = String(d).padStart(2, "0");
    cells.push({ key: `${year}-${mm}-${dd}`, day: d });
  }
  return cells;
}

function stepMonth(
  base: { year: number; month: number },
  delta: number,
): { year: number; month: number } {
  const d = new Date(base.year, base.month + delta, 1);
  return { year: d.getFullYear(), month: d.getMonth() };
}

/** 与移动端 _dayLabel 一致：今天/昨天/前天 / M 月 d 日 · 星期X。 */
function dayLabel(dateKey: string): string {
  const parts = dateKey.split("-").map(Number);
  const y = parts[0] ?? 0;
  const m = parts[1] ?? 0;
  const d = parts[2] ?? 0;
  const dt = new Date(y, m - 1, d);
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const diff = Math.round((today.getTime() - dt.getTime()) / 86400000);
  if (diff === 0) return "今天";
  if (diff === 1) return "昨天";
  if (diff === 2) return "前天";
  const weekdays = ["日", "一", "二", "三", "四", "五", "六"];
  return `${m} 月 ${d} 日 · 星期${weekdays[dt.getDay()]}`;
}
