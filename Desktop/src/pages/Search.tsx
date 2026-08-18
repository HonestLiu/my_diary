import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { motion } from "framer-motion";
import { Search as SearchIcon } from "lucide-react";
import { useAppStore } from "@/store/appStore";
import { EntryCard } from "@/components/EntryCard";
import { formatHumanDate } from "@/lib/utils";
import type { IndexedEntry } from "@/lib/db/schema";
import type { Mood, Weather } from "@/types/journal";

/**
 * Search — full-text lookup across indexed title / body / tags / location.
 * Delegates to the repository, which routes to the FTS5-backed index in
 * production (in-memory index today, same interface).
 */
export default function Search() {
  const repo = useAppStore((s) => s.repo);
  const openEntry = useAppStore((s) => s.openEntry);
  const navigate = useNavigate();

  const [query, setQuery] = useState("");
  const [results, setResults] = useState<IndexedEntry[]>([]);
  const timer = useRef<number | null>(null);

  useEffect(() => {
    if (timer.current) window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => {
      void repo.search(query).then(setResults);
    }, 200);
    return () => {
      if (timer.current) window.clearTimeout(timer.current);
    };
  }, [query, repo]);

  // Index rows carry the entry id, so a hit opens that exact entry even when
  // several were written on the same day.
  const open = (hit: IndexedEntry) => {
    openEntry(hit.id, hit.date);
    navigate("/editor");
  };

  return (
    <div className="h-full overflow-y-auto px-6 py-6">
      <div className="mx-auto max-w-5xl">
        <h1 className="mb-6 text-2xl font-semibold tracking-tight text-foreground">
          搜索
        </h1>

        <div className="flex items-center gap-3 rounded-2xl border border-border bg-card px-4 py-3 shadow-sm">
          <SearchIcon className="h-5 w-5 text-muted-foreground" />
          <input
            autoFocus
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="搜索标题、正文或标签…"
            className="w-full bg-transparent text-base text-foreground outline-none"
          />
        </div>

        <p className="mb-4 mt-4 text-sm text-muted-foreground">
          {query.trim()
            ? `找到 ${results.length} 条结果`
            : "输入关键词开始搜索"}
        </p>

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          {results.map((r, i) => (
            <motion.div
              key={r.id}
              initial={{ opacity: 0, y: 6 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: i * 0.02 }}
            >
              <EntryCard
                title={r.title}
                meta={formatHumanDate(new Date(r.date + "T00:00:00"))}
                mood={r.mood as Mood}
                weather={r.weather as Weather}
                preview={makeExcerpt(r.body, query)}
                location={r.location || undefined}
                tags={r.tags ? r.tags.split(/\s+/).filter(Boolean) : undefined}
                onClick={() => open(r)}
              />
            </motion.div>
          ))}
        </div>
      </div>
    </div>
  );
}

function makeExcerpt(body: string, query: string): string {
  const clean = body.replace(/[#>*_`~]/g, " ").replace(/\s+/g, " ").trim();
  if (!query.trim()) return clean.slice(0, 120);
  const lower = clean.toLowerCase();
  const idx = lower.indexOf(query.trim().toLowerCase());
  if (idx < 0) return clean.slice(0, 120);
  const start = Math.max(0, idx - 30);
  const end = Math.min(clean.length, idx + query.length + 60);
  return (start > 0 ? "…" : "") + clean.slice(start, end) + (end < clean.length ? "…" : "");
}
