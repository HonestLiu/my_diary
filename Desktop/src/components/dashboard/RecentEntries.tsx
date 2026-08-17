import { useNavigate } from "react-router-dom";
import { motion } from "framer-motion";
import { Card } from "@/components/ui/card";
import { MOOD_MAP, WEATHER_MAP } from "@/lib/constants";
import { useAppStore } from "@/store/appStore";
import type { JournalEntry } from "@/types/journal";

interface RecentEntriesProps {
  entries: JournalEntry[];
}

export function RecentEntries({ entries }: RecentEntriesProps) {
  const navigate = useNavigate();
  const openEntry = useAppStore((s) => s.openEntry);

  const open = (e: JournalEntry) => {
    openEntry(e.id, e.date);
    navigate("/editor");
  };

  return (
    <Card className="overflow-hidden">
      <div className="flex items-center justify-between px-6 py-4">
        <h3 className="text-base font-semibold">最近日记</h3>
        <button
          onClick={() => navigate("/timeline")}
          className="text-sm text-muted-foreground transition-colors hover:text-primary"
        >
          查看全部 →
        </button>
      </div>
      <div className="divide-y divide-border/70">
        {entries.map((e, i) => {
          const mood = MOOD_MAP[e.mood];
          const weather = WEATHER_MAP[e.weather];
          return (
            <motion.button
              key={e.id}
              onClick={() => open(e)}
              initial={{ opacity: 0, x: -8 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ duration: 0.3, delay: i * 0.05 }}
              className="group flex w-full items-start gap-4 px-6 py-4 text-left transition-colors hover:bg-accent/50"
            >
              <div className="mt-0.5 text-2xl leading-none">{mood.emoji}</div>
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <span className="truncate font-medium">
                    {e.title || "未命名"}
                  </span>
                  <span className="text-xs text-muted-foreground">
                    {weather.emoji}
                  </span>
                </div>
                <p className="mt-0.5 line-clamp-1 text-sm text-muted-foreground">
                  {e.body || "（空白日记）"}
                </p>
              </div>
              <div className="shrink-0 text-xs text-muted-foreground">
                {e.date.slice(5)}
              </div>
            </motion.button>
          );
        })}
      </div>
    </Card>
  );
}
