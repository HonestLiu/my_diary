import { useMemo } from "react";
import { useNavigate } from "react-router-dom";
import { motion } from "framer-motion";
import { useAppStore } from "@/store/appStore";
import { byRecency } from "@/lib/journal";
import { EntryCard } from "@/components/EntryCard";
import { formatHumanDate } from "@/lib/utils";
import type { JournalEntry } from "@/types/journal";

/**
 * Timeline — a "life timeline" view: years contain months, months contain the
 * entries written in them (a single day may contribute several). On desktop the
 * months within a year flow into a multi-column grid so the wide canvas is
 * actually used. Clicking an entry opens exactly that entry in the editor.
 */
export default function Timeline() {
  const entries = useAppStore((s) => s.entries);
  const openEntry = useAppStore((s) => s.openEntry);
  const navigate = useNavigate();

  const years = useMemo(() => groupByYear(entries), [entries]);

  const open = (entry: JournalEntry) => {
    openEntry(entry.id, entry.date);
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
    <div className="h-full overflow-y-auto px-6 py-6">
      <div className="mx-auto max-w-6xl">
        <h1 className="mb-6 text-2xl font-semibold tracking-tight text-foreground">
          时间轴
        </h1>
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
            <div className="grid grid-cols-1 gap-x-6 gap-y-5 sm:grid-cols-2 lg:grid-cols-3">
              {year.months.map((month) => (
                <div key={month.key} className="border-l-2 border-border pl-4">
                  <p className="mb-2.5 text-sm font-medium text-muted-foreground">
                    {month.label}
                  </p>
                  <div className="flex flex-col gap-3">
                    {month.entries.map((e, i) => (
                      <motion.div
                        key={e.id}
                        initial={{ opacity: 0, x: -8 }}
                        animate={{ opacity: 1, x: 0 }}
                        transition={{ delay: i * 0.015 }}
                      >
                        <EntryCard
                          title={e.title}
                          meta={e.date.slice(8)}
                          mood={e.mood}
                          weather={e.weather}
                          preview={
                            e.body.replace(/[#>*_`~]/g, "").slice(0, 48) ||
                            formatHumanDate(new Date(e.date + "T00:00:00"))
                          }
                          location={e.location}
                          tags={e.tags}
                          coverPath={e.assets.find((a) => a.kind === "image")?.path}
                          onClick={() => open(e)}
                        />
                      </motion.div>
                    ))}
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
  /** Every entry of that month, newest first — a day may appear more than once. */
  entries: JournalEntry[];
}

function groupByYear(entries: JournalEntry[]): YearGroup[] {
  const sorted = [...entries].sort(byRecency);
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
    for (const [mk, monthEntries] of [...byMonth.entries()].sort((a, b) =>
      a[0] < b[0] ? 1 : -1,
    )) {
      const m = Number(mk.slice(5, 7));
      months.push({
        key: mk,
        label: `${m} 月`,
        entries: monthEntries,
      });
    }
    groups.push({ year, total: list.length, months });
  }
  return groups;
}
