import { useEffect, useMemo, useRef, useState } from "react";
import { useLocation, useNavigate } from "react-router-dom";
import { Search as SearchIcon, Type, FileText, Tag, MapPin, ChevronDown, ChevronUp, Smile } from "lucide-react";
import { motion } from "framer-motion";
import { useAppStore } from "@/store/appStore";
import { EntryCard } from "@/components/EntryCard";
import { MarkdownPreview } from "@/components/MarkdownPreview";
import { MoodGlyph } from "@/components/MoodGlyph";
import { entryFilePath, firstCoverAsset } from "@/lib/vault";
import { MOODS } from "@/lib/constants";
import { byRecency } from "@/lib/journal";
import { cn, formatHumanDate } from "@/lib/utils";
import type { JournalEntry, Mood } from "@/types/journal";

/** 搜索范围（与移动端 SearchScope 一致）。 */
type SearchScope = "title" | "body" | "tags" | "location";

const SCOPE_INFO: { key: SearchScope; label: string; icon: typeof Type }[] = [
  { key: "title", label: "标题", icon: Type },
  { key: "body", label: "正文", icon: FileText },
  { key: "tags", label: "标签", icon: Tag },
  { key: "location", label: "地点", icon: MapPin },
];

/**
 * 搜索 —— 与移动端 SearchScreen 同构：
 * 支持字段范围多选（标题/正文/标签/地点，取并集）与心情筛选；
 * 宽屏下结果用双栏网格铺排，提升空间利用率。
 */
export default function Search() {
  const entries = useAppStore((s) => s.entries);
  const openEntry = useAppStore((s) => s.openEntry);
  const unsyncedPaths = useAppStore((s) => s.unsyncedPaths);
  const navigate = useNavigate();
  const location = useLocation();

  // 支持从外部带预填关键词进入（如点击标签云）。
  const [query, setQuery] = useState(
    (location.state as { q?: string } | null)?.q ?? "",
  );
  const [filters, setFilters] = useState<Set<SearchScope>>(new Set());
  const [mood, setMood] = useState<Mood | null>(null);
  const [moodExpanded, setMoodExpanded] = useState(false);
  const inputRef = useRef<HTMLInputElement | null>(null);

  // 进入时若已有关键词则聚焦；否则点开页面即聚焦。
  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  const results = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (q === "" && mood == null) return [];
    const scope = filters;
    return entries
      .filter((e) => {
        if (mood != null && e.mood !== mood) return false;
        if (q === "") return true;
        const matchTitle = e.title.toLowerCase().includes(q);
        const matchBody = e.body.toLowerCase().includes(q);
        const matchTags = e.tags.some((t) => t.toLowerCase().includes(q));
        const matchLocation = (e.location ?? "")
          .toLowerCase()
          .includes(q);
        if (scope.size === 0) {
          return matchTitle || matchBody || matchTags || matchLocation;
        }
        return (
          (scope.has("title") && matchTitle) ||
          (scope.has("body") && matchBody) ||
          (scope.has("tags") && matchTags) ||
          (scope.has("location") && matchLocation)
        );
      })
      .sort(byRecency);
  }, [query, filters, mood, entries]);

  const toggleScope = (s: SearchScope) => {
    setFilters((prev) => {
      const next = new Set(prev);
      if (next.has(s)) next.delete(s);
      else next.add(s);
      return next;
    });
  };

  const open = (e: JournalEntry) => {
    openEntry(e.id, e.date);
    navigate("/editor");
  };

  const hasActive = query.trim() !== "" || mood != null;

  return (
    <div className="h-full overflow-y-auto px-6 py-6">
      <div className="mx-auto max-w-[1400px]">
        <h1 className="mb-6 text-2xl font-semibold tracking-tight text-foreground">
          搜索
        </h1>

        {/* 搜索框 */}
        <div className="flex items-center gap-3 rounded-2xl border border-border bg-card px-4 py-3 shadow-sm">
          <SearchIcon className="h-5 w-5 text-muted-foreground" />
          <input
            ref={inputRef}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="搜索标题、正文、标签、地点…"
            className="w-full bg-transparent text-base text-foreground outline-none"
          />
        </div>

        {/* 范围筛选 + 心情筛选 */}
        <div className="mt-3 flex flex-wrap items-center gap-2">
          {SCOPE_INFO.map((s) => {
            const selected = filters.has(s.key);
            return (
              <button
                key={s.key}
                type="button"
                onClick={() => toggleScope(s.key)}
                className={cn(
                  "inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-sm transition-colors",
                  selected
                    ? "border-primary bg-accent text-accent-foreground"
                    : "border-border bg-card text-muted-foreground hover:bg-muted",
                )}
              >
                <s.icon className="h-3.5 w-3.5" />
                {s.label}
              </button>
            );
          })}

          {/* 心情筛选胶囊 */}
          <div className="relative">
            <button
              type="button"
              onClick={() => setMoodExpanded((v) => !v)}
              className={cn(
                "inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-sm transition-colors",
                mood != null || moodExpanded
                  ? "border-primary bg-accent text-accent-foreground"
                  : "border-border bg-card text-muted-foreground hover:bg-muted",
              )}
            >
              <Smile className="h-3.5 w-3.5" />
              {mood != null ? (
                <>
                  <MoodGlyph mood={mood} className="text-base leading-none" />
                  {MOODS.find((m) => m.key === mood)?.label}
                </>
              ) : (
                "心情"
              )}
              {moodExpanded ? (
                <ChevronUp className="h-3.5 w-3.5" />
              ) : (
                <ChevronDown className="h-3.5 w-3.5" />
              )}
            </button>

            {moodExpanded && (
              <>
                <div
                  className="fixed inset-0 z-30"
                  onClick={() => setMoodExpanded(false)}
                  aria-hidden
                />
                <div className="absolute left-0 z-40 mt-2 w-56 rounded-xl border border-border bg-card p-2 shadow-2xl">
                  <button
                    type="button"
                    onClick={() => {
                      setMood(null);
                      setMoodExpanded(false);
                    }}
                    className={cn(
                      "flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm transition-colors hover:bg-muted",
                      mood == null ? "text-primary" : "text-foreground",
                    )}
                  >
                    全部心情
                  </button>
                  {MOODS.map((m) => (
                    <button
                      key={m.key}
                      type="button"
                      onClick={() => {
                        setMood(m.key);
                        setMoodExpanded(false);
                      }}
                      className={cn(
                        "flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm transition-colors hover:bg-muted",
                        mood === m.key ? "text-primary" : "text-foreground",
                      )}
                    >
                      <MoodGlyph mood={m.key} className="text-lg leading-none" />
                      {m.label}
                    </button>
                  ))}
                </div>
              </>
            )}
          </div>
        </div>

        {/* 结果状态 */}
        <p className="mb-4 mt-4 text-sm text-muted-foreground">
          {hasActive ? `找到 ${results.length} 条结果` : "输入关键词开始搜索"}
        </p>

        {/* 结果列表：宽屏双栏网格 */}
        {hasActive && results.length === 0 ? (
          <div className="flex flex-col items-center rounded-2xl border border-border bg-card p-12 text-muted-foreground">
            <SearchIcon className="mb-3 h-8 w-8 text-primary" />
            <p>没有匹配的日记</p>
          </div>
        ) : (
          <div className="grid grid-cols-1 gap-3 lg:grid-cols-2">
            {results.map((e, i) => (
              <motion.div
                key={e.id}
                initial={{ opacity: 0, y: 6 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: Math.min(i * 0.02, 0.3) }}
              >
                <EntryCard
                  title={e.title}
                  meta={formatHumanDate(new Date(e.date + "T00:00:00"))}
                  mood={e.mood}
                  weather={e.weather}
                  preview={
                    e.body.trim() ? (
                      <MarkdownPreview body={e.body} />
                    ) : (
                      "（空白日记）"
                    )
                  }
                  location={e.location}
                  tags={e.tags}
                  cover={firstCoverAsset(e.assets)}
                  unsynced={unsyncedPaths.has(
                    entryFilePath({ id: e.id, date: e.date }),
                  )}
                  onClick={() => open(e)}
                />
              </motion.div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
