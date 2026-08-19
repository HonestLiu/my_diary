import { useMemo } from "react";
import { Plus, Trash2 } from "lucide-react";
import { cn } from "@/lib/utils";
import { EntryCard } from "@/components/EntryCard";
import { MarkdownPreview } from "@/components/MarkdownPreview";
import { entryFilePath, firstCoverAsset } from "@/lib/vault";
import { useAppStore } from "@/store/appStore";
import type { JournalEntry } from "@/types/journal";

interface Props {
  entries: JournalEntry[];
  activeId: string | null;
  onSelect: (entry: JournalEntry) => void;
  /** Add another entry to a specific day. */
  onAddForDate: (date: string) => void;
  onDelete: (entry: JournalEntry) => void;
}

const WEEKDAYS = ["日", "一", "二", "三", "四", "五", "六"];

/**
 * Left rail: every entry, grouped by day, newest first.
 *
 * A day is a heading, not a slot — it can hold any number of entries, and each
 * day header carries a "+" to add one more to that same day. 条目用与移动端
 * 首页同款的 EntryCard（含封面 / 心情天气图标 / meta 胶囊）。
 */
export function EntryNavigator({
  entries,
  activeId,
  onSelect,
  onAddForDate,
  onDelete,
}: Props) {
  const groups = useMemo(() => groupByDate(entries), [entries]);
  const unsyncedPaths = useAppStore((s) => s.unsyncedPaths);

  return (
    <div className="flex h-full flex-col overflow-y-auto p-3">
      <div className="flex flex-col gap-4">
        {groups.map((g) => (
          <div key={g.date}>
            <div className="group/day mb-2 flex items-center gap-2 px-1">
              <span className="text-xs font-semibold text-foreground">
                {g.label}
              </span>
              <span className="text-[10px] text-muted-foreground">
                {g.weekday}
                {g.entries.length > 1 ? ` · ${g.entries.length} 篇` : ""}
              </span>
              <button
                type="button"
                title={`在 ${g.date} 再写一篇`}
                onClick={() => onAddForDate(g.date)}
                className="ml-auto flex h-5 w-5 items-center justify-center rounded-md text-muted-foreground opacity-0 transition hover:bg-muted hover:text-primary focus:opacity-100 group-hover/day:opacity-100"
              >
                <Plus className="h-3.5 w-3.5" />
              </button>
            </div>

            <div className="flex flex-col gap-2.5">
              {g.entries.map((e) => {
                const active = e.id === activeId;
                return (
                  <div
                    key={e.id}
                    className={cn(
                      "group/item relative",
                      active && "rounded-xl ring-2 ring-primary",
                    )}
                  >
                    <EntryCard
                      title={e.title}
                      mood={e.mood}
                      weather={e.weather}
                      preview={preview(e)}
                      location={e.location}
                      tags={e.tags}
                      cover={firstCoverAsset(e.assets)}
                      unsynced={unsyncedPaths.has(
                        entryFilePath({ id: e.id, date: e.date }),
                      )}
                      onClick={() => onSelect(e)}
                    />
                    <button
                      type="button"
                      title="删除这篇日记"
                      onClick={() => onDelete(e)}
                      className="absolute right-2 top-2 z-10 flex h-6 w-6 items-center justify-center rounded-md bg-muted text-muted-foreground opacity-0 transition hover:text-red-500 focus:opacity-100 group-hover/item:opacity-100"
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </button>
                  </div>
                );
              })}
            </div>
          </div>
        ))}

        {groups.length === 0 && (
          <p className="px-3 py-6 text-center text-sm text-muted-foreground">
            还没有日记
          </p>
        )}
      </div>
    </div>
  );
}

function preview(e: JournalEntry): React.ReactNode {
  if (e.body.trim()) {
    return <MarkdownPreview body={e.body} />;
  }
  return e.tags.slice(0, 3).join(" · ") || "空白日记";
}

interface DateGroup {
  date: string;
  label: string;
  weekday: string;
  entries: JournalEntry[];
}

function groupByDate(entries: JournalEntry[]): DateGroup[] {
  const byDate = new Map<string, JournalEntry[]>();
  for (const e of entries) {
    const list = byDate.get(e.date);
    if (list) list.push(e);
    else byDate.set(e.date, [e]);
  }
  return [...byDate.entries()]
    .sort((a, b) => (a[0] < b[0] ? 1 : -1))
    .map(([date, list]) => {
      const [y, m, d] = date.split("-");
      const dow = new Date(date + "T00:00:00").getDay();
      return {
        date,
        label: `${y}.${m}.${d}`,
        weekday: WEEKDAYS[dow] ? `周${WEEKDAYS[dow]}` : "",
        entries: [...list].sort((a, b) =>
          a.created_at < b.created_at ? 1 : a.created_at > b.created_at ? -1 : 0,
        ),
      };
    });
}
