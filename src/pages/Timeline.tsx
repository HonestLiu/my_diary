import { useMemo } from "react";
import { useNavigate } from "react-router-dom";
import { motion } from "framer-motion";
import { useAppStore } from "@/store/appStore";
import { MOOD_MAP } from "@/lib/constants";
import { formatHumanDate } from "@/lib/utils";
import type { JournalEntry } from "@/types/journal";

/**
 * Timeline — a "life timeline" view: years contain months, months contain the
 * days that have entries. Clicking a day opens that entry in the editor.
 */
export default function Timeline() {
  const entries = useAppStore((s) => s.entries);
  const setActiveDate = useAppStore((s) => s.setActiveDate);
  const navigate = useNavigate();

  const years = useMemo(() => groupByYear(entries), [entries]);

  const open = (date: string) => {
    setActiveDate(date);
    navigate("/editor");
  };

  if (entries.length === 0) {
    return (
      <div className="flex h-full items-center justify-center">
        <p className="text-muted-foreground">还没有日记，去写第一篇吧。</p>
      </div>
    );
  }

  return (
    <div className="h-full overflow-y-auto px-8 py-10">
      <div className="mx-auto max-w-3xl">
        <h1 className="mb-8 text-3xl font-semibold text-foreground">时间轴</h1>
        {years.map((year) => (
          <section key={year.year} className="mb-10">
            <div className="mb-4 flex items-baseline gap-3">
              <span className="text-2xl font-bold text-foreground">
                {year.year}
              </span>
              <span className="text-sm text-muted-foreground">
                {year.total} 篇日记
              </span>
            </div>
            <div className="border-l-2 border-border pl-6">
              {year.months.map((month) => (
                <div key={month.key} className="mb-6">
                  <p className="mb-2 text-sm font-medium text-muted-foreground">
                    {month.label}
                  </p>
                  <div className="flex flex-col gap-2">
                    {month.days.map((e, i) => {
                      const mood = MOOD_MAP[e.mood];
                      return (
                        <motion.button
                          key={e.date}
                          type="button"
                          initial={{ opacity: 0, x: -8 }}
                          animate={{ opacity: 1, x: 0 }}
                          transition={{ delay: i * 0.02 }}
                          onClick={() => open(e.date)}
                          className="group relative flex items-start gap-3 rounded-xl px-3 py-2 text-left transition hover:bg-muted"
                        >
                          <span className="absolute -left-[31px] top-3 h-2.5 w-2.5 rounded-full border-2 border-white bg-amber-400" />
                          <span className="mt-0.5 w-12 shrink-0 text-right text-xs text-muted-foreground">
                            {e.date.slice(8)}
                          </span>
                          <span className="text-lg leading-none">
                            {mood?.emoji ?? "📝"}
                          </span>
                          <div className="min-w-0">
                            <p className="truncate text-sm font-medium text-foreground group-hover:text-amber-700">
                              {e.title || "未命名"}
                            </p>
                            <p className="line-clamp-1 text-xs text-muted-foreground">
                              {e.body.replace(/[#>*_`~]/g, "").slice(0, 60) ||
                                formatHumanDate(new Date(e.date + "T00:00:00"))}
                            </p>
                          </div>
                        </motion.button>
                      );
                    })}
                  </div>
                </div>
              ))}
            </div>
          </section>
        ))}
      </div>
    </div>
  );
}

interface YearGroup {
  year: number;
  total: number;
  months: MonthGroup[];
}
interface MonthGroup {
  key: string;
  label: string;
  days: JournalEntry[];
}

function groupByYear(entries: JournalEntry[]): YearGroup[] {
  const sorted = [...entries].sort((a, b) => (a.date < b.date ? 1 : -1));
  const byYear = new Map<number, JournalEntry[]>();
  for (const e of sorted) {
    const y = Number(e.date.slice(0, 4));
    if (!byYear.has(y)) byYear.set(y, []);
    byYear.get(y)!.push(e);
  }
  const groups: YearGroup[] = [];
  for (const [year, list] of [...byYear.entries()].sort((a, b) => b[0] - a[0])) {
    const byMonth = new Map<string, JournalEntry[]>();
    for (const e of list) {
      const mk = e.date.slice(0, 7);
      if (!byMonth.has(mk)) byMonth.set(mk, []);
      byMonth.get(mk)!.push(e);
    }
    const months: MonthGroup[] = [];
    for (const [mk, days] of [...byMonth.entries()].sort((a, b) =>
      a[0] < b[0] ? 1 : -1,
    )) {
      const m = Number(mk.slice(5, 7));
      months.push({
        key: mk,
        label: `${m} 月`,
        days,
      });
    }
    groups.push({ year, total: list.length, months });
  }
  return groups;
}
