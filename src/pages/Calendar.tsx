import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { motion } from "framer-motion";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { useAppStore } from "@/store/appStore";
import { MOOD_MAP } from "@/lib/constants";
import { formatDateKey } from "@/lib/utils";
import type { JournalEntry } from "@/types/journal";

/**
 * Calendar — month grid marking every day that has entries (a day can hold
 * several, so cells show a count). On desktop two months are shown side by side
 * (fills the wide canvas instead of a narrow centered column); navigation pages
 * forward/back one month at a time.
 */
export default function Calendar() {
  const entries = useAppStore((s) => s.entries);
  const activeDate = useAppStore((s) => s.activeDate);
  const openDate = useAppStore((s) => s.openDate);
  const weekStartsOn = useAppStore((s) => s.settings.weekStartsOn);
  const navigate = useNavigate();

  const today = new Date();
  const [base, setBase] = useState({
    year: Number(activeDate.slice(0, 4)) || today.getFullYear(),
    month: (Number(activeDate.slice(5, 7)) - 1) || today.getMonth(),
  });

  const entriesByDate = useMemo(() => {
    const m = new Map<string, JournalEntry[]>();
    for (const e of entries) {
      const list = m.get(e.date);
      if (list) list.push(e);
      else m.set(e.date, [e]);
    }
    return m;
  }, [entries]);

  const months = useMemo(() => [base, stepMonth(base, 1)], [base]);

  const shift = (delta: number) => setBase((v) => stepMonth(v, delta));

  // Opens that day's newest entry, or a blank draft when the day is empty.
  const open = (dateKey: string) => {
    openDate(dateKey);
    navigate("/editor");
  };

  return (
    <div className="h-full overflow-y-auto px-6 py-6">
      <div className="mx-auto max-w-[1400px]">
        <div className="mb-5 flex items-center justify-between">
          <h1 className="text-2xl font-semibold tracking-tight text-foreground">
            日历
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
              onClick={() =>
                setBase({
                  year: today.getFullYear(),
                  month: today.getMonth(),
                })
              }
              className="ml-2 rounded-lg border border-border px-3 py-1.5 text-sm text-muted-foreground transition-colors hover:bg-muted"
            >
              今天
            </button>
          </div>
        </div>

        <div className="grid gap-5 md:grid-cols-2">
          {months.map((m, mi) => (
            <MonthCard
              key={`${m.year}-${m.month}`}
              year={m.year}
              month={m.month}
              entriesByDate={entriesByDate}
              activeDate={activeDate}
              onOpen={open}
              weekStartsOn={weekStartsOn}
              animateOffset={mi * 6}
            />
          ))}
        </div>

        <p className="mt-6 text-center text-sm text-muted-foreground">
          点击任意日期开始记录；标记了表情的日期已有日记，右上角数字表示当天写了几篇。
        </p>
      </div>
    </div>
  );
}

interface MonthCardProps {
  year: number;
  month: number; // 0-based
  /** All entries of a day, newest first. */
  entriesByDate: Map<string, JournalEntry[]>;
  activeDate: string;
  onOpen: (key: string) => void;
  /** First day of the week: 0 = Sunday, 1 = Monday. */
  weekStartsOn: 0 | 1;
  animateOffset: number;
}

function MonthCard({
  year,
  month,
  entriesByDate,
  activeDate,
  onOpen,
  weekStartsOn,
  animateOffset,
}: MonthCardProps) {
  const cells = useMemo(
    () => buildMonthGrid(year, month, weekStartsOn),
    [year, month, weekStartsOn],
  );
  const weekdayLabels = ["日", "一", "二", "三", "四", "五", "六"].slice(
    weekStartsOn,
  ).concat(["日", "一", "二", "三", "四", "五", "六"].slice(0, weekStartsOn));

  return (
    <div className="rounded-2xl border border-border bg-card p-4 shadow-sm">
      <div className="mb-3 text-center text-base font-semibold text-foreground">
        {year} 年 {month + 1} 月
      </div>
      <div className="mb-2 grid grid-cols-7 gap-1.5 text-center text-xs font-medium text-muted-foreground">
        {weekdayLabels.map((w) => (
          <div key={w} className="py-1">
            {w}
          </div>
        ))}
      </div>
      <div className="grid grid-cols-7 gap-1.5">
        {cells.map((cell, i) => {
          if (!cell) return <div key={`empty-${i}`} />;
          const dayEntries = entriesByDate.get(cell.key);
          const first = dayEntries?.[0];
          const count = dayEntries?.length ?? 0;
          const isToday = cell.key === formatDateKey();
          const isActive = cell.key === activeDate;
          const mood = first ? MOOD_MAP[first.mood] : undefined;
          return (
            <motion.button
              key={cell.key}
              type="button"
              initial={{ opacity: 0, scale: 0.96 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ delay: (animateOffset + i) * 0.004 }}
              onClick={() => onOpen(cell.key)}
              title={count > 1 ? `${count} 篇日记` : first?.title || undefined}
              className={`relative flex aspect-square flex-col items-center justify-center rounded-xl border text-sm transition ${
                isActive
                  ? "border-primary bg-accent"
                  : count
                    ? "border-border bg-muted/40 hover:border-primary"
                    : "border-transparent text-muted-foreground hover:bg-muted"
              }`}
            >
              <span
                className={`text-base ${isToday ? "font-bold text-primary" : "text-foreground"}`}
              >
                {cell.day}
              </span>
              {mood && (
                <span className="text-base leading-none">{mood.emoji}</span>
              )}
              {count > 1 && (
                <span className="absolute right-1 top-1 rounded-full bg-primary/90 px-1.5 text-[10px] font-semibold leading-4 text-primary-foreground">
                  {count}
                </span>
              )}
            </motion.button>
          );
        })}
      </div>
    </div>
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
