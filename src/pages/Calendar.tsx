import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { motion } from "framer-motion";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { useAppStore } from "@/store/appStore";
import { MOOD_MAP } from "@/lib/constants";
import { formatDateKey } from "@/lib/utils";

/**
 * Calendar — month grid marking every day that has an entry. Clicking a day
 * navigates to the editor (opening the entry, or scaffolding a blank one).
 */
export default function Calendar() {
  const entries = useAppStore((s) => s.entries);
  const activeDate = useAppStore((s) => s.activeDate);
  const setActiveDate = useAppStore((s) => s.setActiveDate);
  const navigate = useNavigate();

  const today = new Date();
  const [view, setView] = useState({
    year: Number(activeDate.slice(0, 4)) || today.getFullYear(),
    month: (Number(activeDate.slice(5, 7)) - 1) || today.getMonth(),
  });

  const entryByDate = useMemo(() => {
    const m = new Map<string, (typeof entries)[number]>();
    for (const e of entries) m.set(e.date, e);
    return m;
  }, [entries]);

  const cells = useMemo(
    () => buildMonthGrid(view.year, view.month),
    [view],
  );

  const shift = (delta: number) => {
    setView((v) => {
      const d = new Date(v.year, v.month + delta, 1);
      return { year: d.getFullYear(), month: d.getMonth() };
    });
  };

  const open = (dateKey: string) => {
    setActiveDate(dateKey);
    navigate("/editor");
  };

  const weekdayLabels = ["日", "一", "二", "三", "四", "五", "六"];

  return (
    <div className="h-full overflow-y-auto px-8 py-10">
      <div className="mx-auto max-w-3xl">
        <div className="mb-6 flex items-center justify-between">
          <h1 className="text-3xl font-semibold text-foreground">
            {view.year} 年 {view.month + 1} 月
          </h1>
          <div className="flex items-center gap-1">
            <button
              type="button"
              onClick={() => shift(-1)}
              className="flex h-9 w-9 items-center justify-center rounded-lg text-muted-foreground hover:bg-muted"
            >
              <ChevronLeft className="h-5 w-5" />
            </button>
            <button
              type="button"
              onClick={() => shift(1)}
              className="flex h-9 w-9 items-center justify-center rounded-lg text-muted-foreground hover:bg-muted"
            >
              <ChevronRight className="h-5 w-5" />
            </button>
          </div>
        </div>

        <div className="mb-2 grid grid-cols-7 gap-2 text-center text-xs font-medium text-muted-foreground">
          {weekdayLabels.map((w) => (
            <div key={w} className="py-1">
              {w}
            </div>
          ))}
        </div>

        <div className="grid grid-cols-7 gap-2">
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
                transition={{ delay: i * 0.006 }}
                onClick={() => open(cell.key)}
                className={`flex aspect-square flex-col items-center justify-center rounded-2xl border text-sm transition ${
                  isActive
                    ? "border-amber-400 bg-accent"
                    : e
                      ? "border-border bg-card hover:border-amber-300"
                      : "border-transparent text-muted-foreground hover:bg-muted"
                }`}
              >
                <span
                  className={`text-base ${isToday ? "font-bold text-amber-600" : "text-foreground"}`}
                >
                  {cell.day}
                </span>
                {mood && <span className="text-base leading-none">{mood.emoji}</span>}
              </motion.button>
            );
          })}
        </div>

        <p className="mt-6 text-center text-sm text-muted-foreground">
          点击任意日期开始记录，标记了表情的日期已有日记。
        </p>
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
