import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { motion } from "framer-motion";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { useAppStore } from "@/store/appStore";
import { MOOD_MAP } from "@/lib/constants";
import { formatDateKey } from "@/lib/utils";
import type { JournalEntry } from "@/types/journal";

/**
 * Calendar — month grid marking every day that has an entry. On desktop two
 * months are shown side by side (fills the wide canvas instead of a narrow
 * centered column); navigation pages forward/back one month at a time.
 */
export default function Calendar() {
  const entries = useAppStore((s) => s.entries);
  const activeDate = useAppStore((s) => s.activeDate);
  const setActiveDate = useAppStore((s) => s.setActiveDate);
  const navigate = useNavigate();

  const today = new Date();
  const [base, setBase] = useState({
    year: Number(activeDate.slice(0, 4)) || today.getFullYear(),
    month: (Number(activeDate.slice(5, 7)) - 1) || today.getMonth(),
  });

  const entryByDate = useMemo(() => {
    const m = new Map<string, JournalEntry>();
    for (const e of entries) m.set(e.date, e);
    return m;
  }, [entries]);

  const months = useMemo(() => [base, stepMonth(base, 1)], [base]);

  const shift = (delta: number) => setBase((v) => stepMonth(v, delta));

  const open = (dateKey: string) => {
    setActiveDate(dateKey);
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
              entryByDate={entryByDate}
              activeDate={activeDate}
              onOpen={open}
              animateOffset={mi * 6}
            />
          ))}
        </div>

        <p className="mt-6 text-center text-sm text-muted-foreground">
          点击任意日期开始记录，标记了表情的日期已有日记。
        </p>
      </div>
    </div>
  );
}

interface MonthCardProps {
  year: number;
  month: number; // 0-based
  entryByDate: Map<string, JournalEntry>;
  activeDate: string;
  onOpen: (key: string) => void;
  animateOffset: number;
}

function MonthCard({
  year,
  month,
  entryByDate,
  activeDate,
  onOpen,
  animateOffset,
}: MonthCardProps) {
  const cells = useMemo(() => buildMonthGrid(year, month), [year, month]);
  const weekdayLabels = ["日", "一", "二", "三", "四", "五", "六"];

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
          const e = entryByDate.get(cell.key);
          const isToday = cell.key === formatDateKey();
          const isActive = cell.key === activeDate;
          const mood = e ? MOOD_MAP[e.mood] : undefined;
          return (
            <motion.button
              key={cell.key}
              type="button"
              initial={{ opacity: 0, scale: 0.96 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ delay: (animateOffset + i) * 0.004 }}
              onClick={() => onOpen(cell.key)}
              className={`flex aspect-square flex-col items-center justify-center rounded-xl border text-sm transition ${
                isActive
                  ? "border-amber-400 bg-accent"
                  : e
                    ? "border-border bg-muted/40 hover:border-amber-300"
                    : "border-transparent text-muted-foreground hover:bg-muted"
              }`}
            >
              <span
                className={`text-base ${isToday ? "font-bold text-amber-600" : "text-foreground"}`}
              >
                {cell.day}
              </span>
              {mood && (
                <span className="text-base leading-none">{mood.emoji}</span>
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

function buildMonthGrid(year: number, month: number): (Cell | null)[] {
  const first = new Date(year, month, 1);
  const startWeekday = first.getDay(); // 0 = Sunday
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
