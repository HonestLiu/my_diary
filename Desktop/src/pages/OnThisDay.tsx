import { useMemo } from "react";
import { useNavigate } from "react-router-dom";
import { Stars, Dice5 } from "lucide-react";
import { useAppStore } from "@/store/appStore";
import { byRecency } from "@/lib/journal";
import { formatDateKey, formatHumanDate } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { EntryCard } from "@/components/EntryCard";
import type { JournalEntry } from "@/types/journal";

function snippet(body: string): string {
  const clean = body
    .replace(/[#>*_`~\[\]()]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  return clean.length > 80 ? clean.slice(0, 80) + "…" : clean;
}

/** "On this day" — every year's entry for today's month-day. */
export default function OnThisDay() {
  const entries = useAppStore((s) => s.entries);
  const openEntry = useAppStore((s) => s.openEntry);
  const navigate = useNavigate();

  const today = formatDateKey();
  const mmdd = today.slice(5);

  // Any given past year may hold several entries for this month-day.
  const matches = useMemo(
    () =>
      entries
        .filter((e) => e.date.slice(5) === mmdd && e.date !== today)
        .sort(byRecency),
    [entries, mmdd, today],
  );

  const open = (entry: JournalEntry) => {
    openEntry(entry.id, entry.date);
    navigate("/editor");
  };

  const random = () => {
    if (entries.length === 0) return;
    const e = entries[Math.floor(Math.random() * entries.length)];
    if (!e) return;
    open(e);
  };

  return (
    <div className="h-full overflow-y-auto">
      <div className="mx-auto max-w-5xl px-6 py-6">
        <div className="flex items-start justify-between gap-4">
          <div>
            <h1 className="text-3xl font-semibold tracking-tight">一年前的今天</h1>
            <p className="mt-1 text-muted-foreground">
              每年的 {mmdd.replace("-", " 月 ")} 日，你都写了什么
            </p>
          </div>
          <Button variant="outline" onClick={random} className="shrink-0">
            <Dice5 className="h-4 w-4" />
            随机回顾
          </Button>
        </div>

        {matches.length === 0 ? (
          <div className="mt-10 flex flex-col items-center rounded-2xl border border-border bg-card p-10 text-center text-muted-foreground">
            <Stars className="mb-3 h-8 w-8 text-primary" />
            <p>往年这一天还没有日记。</p>
            <p className="mt-1 text-sm">继续记录，明年此时就能在这里与过去的自己重逢。</p>
          </div>
        ) : (
          <ul className="mt-8 grid grid-cols-1 gap-3 sm:grid-cols-2">
            {matches.map((e) => (
              <li key={e.id}>
                <EntryCard
                  title={e.title}
                  meta={formatHumanDate(new Date(e.date + "T00:00:00"))}
                  mood={e.mood}
                  preview={e.body ? snippet(e.body) : undefined}
                  location={e.location}
                  tags={e.tags}
                  onClick={() => open(e)}
                />
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
