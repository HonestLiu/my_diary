import { useState } from "react";
import { CalendarDays, MapPin, Tag, X, Paperclip, FileText } from "lucide-react";
import { MoodSelector } from "@/components/dashboard/MoodSelector";
import { WEATHERS } from "@/lib/constants";
import { cn, formatHumanDate } from "@/lib/utils";
import type { AssetRef, Mood, Weather } from "@/types/journal";

interface Props {
  /** The day this entry belongs to — plain metadata, freely changeable. */
  date: string;
  mood: Mood;
  weather: Weather;
  location: string;
  tags: string[];
  assets: AssetRef[];
  onDateChange: (v: string) => void;
  onMoodChange: (m: Mood) => void;
  onWeatherChange: (w: Weather) => void;
  onLocationChange: (v: string) => void;
  onTagsChange: (tags: string[]) => void;
  onRemoveAsset: (path: string) => void;
}

/**
 * Right-hand property rail: metadata + attachments for the active entry.
 *
 * The title lives in the editor header (it is the entry's headline, not a
 * side property); this rail owns the date, which merely decides where the
 * entry is filed and grouped.
 */
export function PropertyPanel({
  date,
  mood,
  weather,
  location,
  tags,
  assets,
  onDateChange,
  onMoodChange,
  onWeatherChange,
  onLocationChange,
  onTagsChange,
  onRemoveAsset,
}: Props) {
  const [tagInput, setTagInput] = useState("");

  const addTag = () => {
    const t = tagInput.trim();
    if (t && !tags.includes(t)) onTagsChange([...tags, t]);
    setTagInput("");
  };

  return (
    <div className="flex h-full flex-col gap-5 overflow-y-auto p-4">
      <Section title="日期">
        <div className="flex items-center gap-2 rounded-xl border border-border px-3 py-2">
          <CalendarDays className="h-4 w-4 shrink-0 text-muted-foreground" />
          <input
            type="date"
            value={date}
            onChange={(e) => onDateChange(e.target.value)}
            aria-label="日记日期"
            className="w-full bg-transparent text-sm text-foreground outline-none"
          />
        </div>
        <p className="mt-1.5 text-xs text-muted-foreground">
          {date ? formatHumanDate(new Date(date + "T00:00:00")) : ""}
          <span className="ml-1">· 改日期即把这篇移到那一天</span>
        </p>
      </Section>

      <Section title="心情">
        <MoodSelector value={mood} onSelect={onMoodChange} />
      </Section>

      <Section title="天气">
        <div className="flex flex-wrap gap-1.5">
          {WEATHERS.map((w) => (
            <button
              key={w.key}
              type="button"
              onClick={() => onWeatherChange(w.key)}
              className={cn(
                "flex items-center gap-1 rounded-full px-2.5 py-1 text-sm transition",
                weather === w.key
                  ? "bg-accent text-accent-foreground"
                  : "text-muted-foreground hover:bg-muted",
              )}
            >
              <span>{w.emoji}</span>
              <span>{w.label}</span>
            </button>
          ))}
        </div>
      </Section>

      <Section title="地点">
        <div className="flex items-center gap-2 rounded-xl border border-border px-3 py-2">
          <MapPin className="h-4 w-4 text-muted-foreground" />
          <input
            value={location}
            onChange={(e) => onLocationChange(e.target.value)}
            placeholder="你在哪里？"
            className="w-full bg-transparent text-sm text-foreground outline-none"
          />
        </div>
      </Section>

      <Section title="标签">
        <div className="flex flex-wrap gap-1.5">
          {tags.map((t) => (
            <span
              key={t}
              className="flex items-center gap-1 rounded-full bg-muted px-2.5 py-1 text-sm text-muted-foreground"
            >
              <Tag className="h-3 w-3" />
              {t}
              <button
                type="button"
                onClick={() => onTagsChange(tags.filter((x) => x !== t))}
                className="text-muted-foreground hover:text-foreground"
              >
                <X className="h-3 w-3" />
              </button>
            </span>
          ))}
        </div>
        <input
          value={tagInput}
          onChange={(e) => setTagInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              e.preventDefault();
              addTag();
            }
          }}
          placeholder="输入后回车添加"
          className="mt-2 w-full rounded-xl border border-border px-3 py-2 text-sm outline-none focus:border-primary"
        />
      </Section>

      <Section title={`附件${assets.length ? ` (${assets.length})` : ""}`}>
        {assets.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            把图片、音频、视频或文件拖入编辑器即可添加。
          </p>
        ) : (
          <div className="flex flex-col gap-1.5">
            {assets.map((a) => (
              <div
                key={a.path}
                className="flex items-center gap-2 rounded-lg bg-muted px-2.5 py-2 text-sm"
              >
                {a.kind === "image" ? (
                  <Paperclip className="h-4 w-4 text-primary" />
                ) : (
                  <FileText className="h-4 w-4 text-muted-foreground" />
                )}
                <span className="min-w-0 flex-1 truncate text-muted-foreground">
                  {a.name ?? a.path}
                </span>
                <button
                  type="button"
                  onClick={() => onRemoveAsset(a.path)}
                  className="text-muted-foreground hover:text-red-500"
                >
                  <X className="h-3.5 w-3.5" />
                </button>
              </div>
            ))}
          </div>
        )}
      </Section>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div>
      <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
        {title}
      </h3>
      {children}
    </div>
  );
}
