import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { motion } from "framer-motion";
import { Plus, History } from "lucide-react";
import { useAppStore } from "@/store/appStore";
import { byRecency } from "@/lib/journal";
import { formatDateKey, formatHumanDate } from "@/lib/utils";
import type { AssetRef, JournalEntry, Mood, Weather } from "@/types/journal";
import { EditorCanvas } from "@/components/editor/EditorCanvas";
import { PropertyPanel } from "@/components/editor/PropertyPanel";
import { EntryNavigator } from "@/components/editor/EntryNavigator";
import { VersionHistory } from "@/components/editor/VersionHistory";
import { Button } from "@/components/ui/button";

/**
 * Editor page — three-column journal workspace:
 *   left  : entry navigator (all entries, grouped by day)
 *   center: editable title + rich-text editor (TipTap) + floating toolbar
 *   right : property rail (date / mood / weather / location / tags / attachments)
 *
 * An entry is addressed by its id, so a day can hold any number of entries and
 * the title is free text (never derived from the date). The on-disk Markdown
 * file stays the source of truth: edits are debounced and written through the
 * repository, metadata is persisted in frontmatter.
 */
export default function Editor() {
  const repo = useAppStore((s) => s.repo);
  const activeDate = useAppStore((s) => s.activeDate);
  const activeEntryId = useAppStore((s) => s.activeEntryId);
  const openEntry = useAppStore((s) => s.openEntry);
  const startNewEntry = useAppStore((s) => s.startNewEntry);
  const removeEntry = useAppStore((s) => s.removeEntry);
  const setActiveDate = useAppStore((s) => s.setActiveDate);
  const baseEntries = useAppStore((s) => s.entries);

  const [entry, setEntry] = useState<JournalEntry | null>(null);
  const [loading, setLoading] = useState(true);
  const [showHistory, setShowHistory] = useState(false);
  const [reloadKey, setReloadKey] = useState(0);
  const saveTimer = useRef<number | null>(null);
  /** Id currently held in local state — guards against needless reloads. */
  const loadedId = useRef<string | null>(null);

  // Load the selected entry, or scaffold a blank draft for the active day.
  useEffect(() => {
    // The store catching up with a draft we just persisted is not a new
    // selection; reloading here would clobber keystrokes typed since the save.
    if (activeEntryId && loadedId.current === activeEntryId) return;

    let cancelled = false;
    void (async () => {
      setLoading(true);
      const loaded = activeEntryId ? await repo.getEntry(activeEntryId) : null;
      // A blank draft is deliberately NOT written to disk — the first real
      // edit persists it, so opening "new entry" and walking away is free.
      const next = loaded ?? repo.newEntry(activeDate);
      if (cancelled) return;
      loadedId.current = next.id;
      setEntry(next);
      setLoading(false);
    })();
    return () => {
      cancelled = true;
    };
  }, [activeEntryId, activeDate, repo]);

  const persist = useCallback((next: JournalEntry) => {
    if (saveTimer.current) window.clearTimeout(saveTimer.current);
    saveTimer.current = window.setTimeout(() => {
      // Route through the store so every save also refreshes the global
      // entries/stats — otherwise Timeline/Calendar/Dashboard/Search would
      // keep showing stale data until the app is restarted.
      void useAppStore.getState().upsertEntry(next);
      // First save of a draft: adopt it as the selection so the navigator
      // highlights it and a later refresh cannot drop it.
      if (useAppStore.getState().activeEntryId !== next.id) {
        useAppStore.getState().openEntry(next.id, next.date);
      }
    }, 600);
  }, []);

  // Flush a pending save when leaving the page / closing the window.
  useEffect(
    () => () => {
      if (saveTimer.current) window.clearTimeout(saveTimer.current);
    },
    [],
  );

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

  /** Move this entry to another day (the date is plain metadata). */
  const onDateChange = (date: string) => {
    if (!date || date === entry?.date) return;
    patch({ date });
    setActiveDate(date);
  };

  // Restore a historical version: swap in the restored entry and force the
  // editor canvas to reload its content (same entry, so entryKey is unchanged).
  const onRestoreVersion = (restored: JournalEntry) => {
    loadedId.current = restored.id;
    setEntry(restored);
    setReloadKey((k) => k + 1);
    setShowHistory(false);
  };

  const onDeleteEntry = async (target: JournalEntry) => {
    await removeEntry(target.id);
    if (target.id === entry?.id) loadedId.current = null;
  };

  // Merge the live entry into the navigator list so title/mood edits show up
  // immediately — and so an unsaved draft is visible while being written.
  const viewEntries = useMemo(() => {
    if (!entry) return baseEntries;
    const without = baseEntries.filter((e) => e.id !== entry.id);
    return [entry, ...without].sort(byRecency);
  }, [baseEntries, entry]);

  const humanDate = entry
    ? formatHumanDate(new Date(entry.date + "T00:00:00"))
    : "";

  return (
    <div className="flex h-full min-h-0">
      {/* Left: entry navigator */}
      <aside className="w-80 shrink-0 border-r border-border/70 bg-muted/50">
        <div className="flex items-center justify-between px-3 pb-1 pt-3">
          <span className="text-sm font-semibold text-foreground">日记</span>
          <button
            type="button"
            title="新写一篇（今天）"
            onClick={() => startNewEntry(formatDateKey())}
            className="flex h-7 w-7 items-center justify-center rounded-lg text-muted-foreground hover:bg-muted hover:text-primary"
          >
            <Plus className="h-4 w-4" />
          </button>
        </div>
        <div className="h-[calc(100%-2.75rem)]">
          <EntryNavigator
            entries={viewEntries}
            activeId={entry?.id ?? activeEntryId}
            onSelect={(e) => openEntry(e.id, e.date)}
            onAddForDate={(date) => startNewEntry(date)}
            onDelete={(e) => void onDeleteEntry(e)}
          />
        </div>
      </aside>

      {/* Center: editor */}
      <main className="flex min-w-0 flex-1 flex-col">
        <div className="flex items-start justify-between gap-4 px-6 pt-5">
          <div className="min-w-0 flex-1">
            <p className="text-sm text-muted-foreground">{humanDate}</p>
            <input
              value={entry?.title ?? ""}
              onChange={(e) => patch({ title: e.target.value })}
              disabled={!entry}
              placeholder="无标题"
              aria-label="日记标题"
              className="w-full border-0 bg-transparent p-0 text-2xl font-semibold text-foreground outline-none placeholder:text-muted-foreground/50"
            />
          </div>
          <div className="flex shrink-0 items-center gap-2 pt-1">
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
              entryKey={entry.id}
              reloadKey={reloadKey}
              initialContent={entry.body}
              onUpdate={onBodyChange}
              onAssetsAdded={onAssetsAdded}
            />
            </div>
          )}
        </motion.div>
      </main>

      {showHistory && entry && (
        <VersionHistory
          entry={entry}
          onRestore={onRestoreVersion}
          onClose={() => setShowHistory(false)}
        />
      )}

      {/* Right: property rail */}
      <aside className="w-80 shrink-0 border-l border-border/70 bg-muted/50">
        {entry && (
          <PropertyPanel
            date={entry.date}
            mood={entry.mood}
            weather={entry.weather}
            location={entry.location ?? ""}
            tags={entry.tags}
            assets={entry.assets ?? []}
            onDateChange={onDateChange}
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
