import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { motion } from "framer-motion";
import { Plus, History } from "lucide-react";
import { useAppStore } from "@/store/appStore";
import { formatDateKey, formatHumanDate } from "@/lib/utils";
import { saveDroppedAssets } from "@/lib/editor/assets";
import type { AssetRef, JournalEntry, Mood, Weather } from "@/types/journal";
import { EditorCanvas } from "@/components/editor/EditorCanvas";
import { PropertyPanel } from "@/components/editor/PropertyPanel";
import { DateNavigator } from "@/components/editor/DateNavigator";
import { VersionHistory } from "@/components/editor/VersionHistory";
import { Button } from "@/components/ui/button";

/**
 * Editor page — three-column journal workspace:
 *   left  : date navigator (existing days)
 *   center: rich-text editor (TipTap) + floating toolbar
 *   right : property rail (title / mood / weather / location / tags / attachments)
 *
 * The on-disk Markdown file is the source of truth. Edits are debounced and
 * written through the repository; metadata is persisted in frontmatter.
 */
export default function Editor() {
  const repo = useAppStore((s) => s.repo);
  const activeDate = useAppStore((s) => s.activeDate);
  const setActiveDate = useAppStore((s) => s.setActiveDate);
  const baseEntries = useAppStore((s) => s.entries);
  const navigate = useNavigate();

  const [entry, setEntry] = useState<JournalEntry | null>(null);
  const [loading, setLoading] = useState(true);
  const [showHistory, setShowHistory] = useState(false);
  const [reloadKey, setReloadKey] = useState(0);
  const saveTimer = useRef<number | null>(null);

  // Load the entry for the active date, or scaffold a blank one.
  useEffect(() => {
    let cancelled = false;
    void (async () => {
      setLoading(true);
      let e = await repo.getEntry(activeDate);
      if (!e) {
        const now = new Date().toISOString();
        e = {
          id: crypto.randomUUID(),
          date: activeDate,
          title: formatHumanDate(new Date(activeDate + "T00:00:00")),
          mood: "neutral",
          weather: "unknown",
          location: undefined,
          tags: [],
          assets: [],
          body: "",
          created_at: now,
          updated_at: now,
        };
      }
      if (!cancelled) {
        setEntry(e);
        setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [activeDate, repo]);

  const persist = useCallback((next: JournalEntry) => {
    if (saveTimer.current) window.clearTimeout(saveTimer.current);
    saveTimer.current = window.setTimeout(() => {
      // Route through the store so every save also refreshes the global
      // entries/stats — otherwise Timeline/Calendar/Dashboard/Search would
      // keep showing stale data until the app is restarted.
      void useAppStore.getState().upsertEntry(next);
    }, 600);
  }, []);

  const patch = useCallback(
    (p: Partial<JournalEntry>) => {
      setEntry((prev) => {
        if (!prev) return prev;
        const next: JournalEntry = {
          ...prev,
          ...p,
          updated_at: new Date().toISOString(),
        };
        persist(next);
        return next;
      });
    },
    [persist],
  );

  const onBodyChange = (body: string) => patch({ body });

  const onAssetsAdded = (added: AssetRef[]) =>
    patch({ assets: [...(entry?.assets ?? []), ...added] });

  const onRemoveAsset = (path: string) =>
    patch({ assets: (entry?.assets ?? []).filter((a) => a.path !== path) });

  // Restore a historical version: swap in the restored entry and force the
  // editor canvas to reload its content (same date, so entryKey is unchanged).
  const onRestoreVersion = (restored: JournalEntry) => {
    setEntry(restored);
    setReloadKey((k) => k + 1);
    setShowHistory(false);
  };

  // Merge the live entry into the navigator list so title/mood edits show live.
  const viewEntries = useMemo(() => {
    if (!entry) return baseEntries;
    const without = baseEntries.filter((e) => e.date !== entry.date);
    return [entry, ...without];
  }, [baseEntries, entry]);

  const humanDate = formatHumanDate(
    new Date(activeDate + "T00:00:00"),
  );

  return (
    <div className="flex h-full min-h-0">
      {/* Left: date navigator */}
      <aside className="w-64 shrink-0 border-r border-border/70 bg-muted/50">
        <div className="flex items-center justify-between px-3 pb-1 pt-3">
          <span className="text-sm font-semibold text-foreground">日记</span>
          <button
            type="button"
            title="新建今天的日记"
            onClick={() => {
              setActiveDate(formatDateKey());
              navigate("/editor");
            }}
            className="flex h-7 w-7 items-center justify-center rounded-lg text-muted-foreground hover:bg-muted hover:text-amber-600"
          >
            <Plus className="h-4 w-4" />
          </button>
        </div>
        <div className="h-[calc(100%-2.75rem)]">
          <DateNavigator
            entries={viewEntries}
            activeDate={activeDate}
            onSelect={setActiveDate}
          />
        </div>
      </aside>

      {/* Center: editor */}
      <main className="flex min-w-0 flex-1 flex-col">
        <div className="flex items-center justify-between px-6 pt-5">
          <div>
            <p className="text-sm text-muted-foreground">{humanDate}</p>
            <h1 className="text-2xl font-semibold text-foreground">
              {entry?.title || "未命名"}
            </h1>
          </div>
          <div className="flex items-center gap-2">
            <Button
              variant="ghost"
              size="sm"
              className="text-muted-foreground"
              title="查看并恢复历史版本"
              onClick={() => setShowHistory(true)}
            >
              <History className="mr-1.5 h-4 w-4" />
              历史版本
            </Button>
            <Button variant="ghost" size="sm" className="text-muted-foreground">
              {entry ? `${entry.body.length} 字` : ""}
            </Button>
          </div>
        </div>

        <motion.div
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          className="flex-1 overflow-y-auto px-6 pb-16 pt-4"
        >
          {loading || !entry ? (
            <div className="py-20 text-center text-muted-foreground">加载中…</div>
          ) : (
            <div className="mx-auto w-full max-w-3xl">
            <EditorCanvas
              entryKey={activeDate}
              reloadKey={reloadKey}
              initialContent={entry.body}
              onUpdate={onBodyChange}
              onAssetsAdded={onAssetsAdded}
              onPickImages={async (files) => {
                const refs = await saveDroppedAssets(files);
                onAssetsAdded(refs);
              }}
            />
            </div>
          )}
        </motion.div>
      </main>

      {showHistory && (
        <VersionHistory
          dateKey={activeDate}
          onRestore={onRestoreVersion}
          onClose={() => setShowHistory(false)}
        />
      )}

      {/* Right: property rail */}
      <aside className="w-80 shrink-0 border-l border-border/70 bg-muted/50">
        {entry && (
          <PropertyPanel
            title={entry.title}
            mood={entry.mood}
            weather={entry.weather}
            location={entry.location ?? ""}
            tags={entry.tags}
            assets={entry.assets ?? []}
            onTitleChange={(title) => patch({ title })}
            onMoodChange={(mood: Mood) => patch({ mood })}
            onWeatherChange={(weather: Weather) => patch({ weather })}
            onLocationChange={(location) => patch({ location })}
            onTagsChange={(tags) => patch({ tags })}
            onRemoveAsset={onRemoveAsset}
          />
        )}
      </aside>
    </div>
  );
}
