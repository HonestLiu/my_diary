import { motion } from "framer-motion";
import { cn } from "@/lib/utils";
import { MOOD_MAP } from "@/lib/constants";
import type { JournalEntry } from "@/types/journal";

interface Props {
  entries: JournalEntry[];
  activeDate: string;
  onSelect: (date: string) => void;
}

/** Left rail: every day that has an entry, newest first. */
export function DateNavigator({ entries, activeDate, onSelect }: Props) {
  const sorted = [...entries].sort((a, b) => (a.date < b.date ? 1 : -1));

  return (
    <div className="flex h-full flex-col overflow-y-auto p-3">
      <p className="px-2 pb-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
        日记
      </p>
      <div className="flex flex-col gap-1">
        {sorted.map((e) => {
          const [y, m, d] = e.date.split("-");
          const active = e.date === activeDate;
          const mood = MOOD_MAP[e.mood];
          return (
            <button
              key={e.date}
              type="button"
              onClick={() => onSelect(e.date)}
              className={cn(
                "group flex items-center gap-3 rounded-xl px-3 py-2 text-left transition",
                active ? "bg-card shadow-soft" : "hover:bg-card/60",
              )}
            >
              <div className="flex w-10 flex-col items-center">
                <span className="text-lg font-semibold leading-none text-foreground">
                  {d}
                </span>
                <span className="text-[10px] text-muted-foreground">
                  {y}.{m}
                </span>
              </div>
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-medium text-foreground">
                  {e.title || "未命名"}
                </p>
                <p className="truncate text-xs text-muted-foreground">
                  {mood?.emoji} {e.tags.slice(0, 2).join(" · ") || "无标签"}
                </p>
              </div>
              {active && (
                <motion.span
                  layoutId="nav-active"
                  className="h-6 w-1 rounded-full bg-amber-400"
                />
              )}
            </button>
          );
        })}
        {sorted.length === 0 && (
          <p className="px-3 py-6 text-center text-sm text-muted-foreground">
            还没有日记
          </p>
        )}
      </div>
    </div>
  );
}
