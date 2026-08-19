import { create } from "zustand";
import type { AppSettings, JournalEntry, Mood, Theme } from "@/types/journal";
import { formatDateKey, formatHumanDate } from "@/lib/utils";
import {
  getRepository,
  type JournalRepository,
} from "@/lib/journal";
import { isTauri } from "@/lib/storage/types";

interface AppState {
  /* ---- lifecycle ---- */
  initialized: boolean;
  loading: boolean;
  error?: string;

  /* ---- UI state ---- */
  theme: Theme;
  sidebarCollapsed: boolean;
  /**
   * The day the editor / calendar is focused on. Used for grouping and as the
   * default date of a new entry — it no longer identifies "the" entry.
   */
  activeDate: string;
  /**
   * Id of the entry open in the editor. `null` means "a fresh unsaved entry
   * for activeDate", which the editor scaffolds and persists on first edit.
   */
  activeEntryId: string | null;
  exportOpen: boolean;

  /* ---- Data (backed by the real repository) ---- */
  repo: JournalRepository;
  entries: JournalEntry[];
  recentEntries: JournalEntry[];
  streak: number;
  stats: { entries: number; words: number; images: number };
  settings: AppSettings;

  /* ---- Actions ---- */
  initialize: () => Promise<void>;
  setTheme: (t: Theme) => void;
  updateSettings: (patch: Partial<AppSettings>) => void;
  toggleSidebar: () => void;
  setActiveDate: (date: string) => void;
  /** Open an existing entry in the editor (by id). */
  openEntry: (id: string, date?: string) => void;
  /** Open the first entry of a day, or a blank one when the day is empty. */
  openDate: (date: string) => void;
  /** Start a brand-new (unsaved) entry, optionally on a given day. */
  startNewEntry: (date?: string) => void;
  setExportOpen: (open: boolean) => void;
  upsertEntry: (entry: JournalEntry) => Promise<void>;
  removeEntry: (id: string) => Promise<void>;
  refresh: () => Promise<void>;
}

/**
 * 唯一日记库根目录：
 * - Tauri（桌面）：系统文档目录下 my-diary，与移动端
 *   `getApplicationDocumentsDirectory()/my-diary` 一致，两端数据互通。
 * - 浏览器（预览）：固定 IndexedDB 库名。
 */
async function resolveSingleVaultRoot(): Promise<string> {
  if (isTauri()) {
    const { documentDir } = await import("@tauri-apps/api/path");
    const dir = (await documentDir()).replace(/\\/g, "/").replace(/\/+$/, "");
    return `${dir}/my-diary`;
  }
  return "my-diary-vault";
}

function computeStreak(dates: string[]): number {
  const set = new Set(dates);
  let count = 0;
  const d = new Date();
  // Walk backwards from today; break on the first missing day.
  for (;;) {
    const key = formatDateKey(d);
    if (!set.has(key)) break;
    count += 1;
    d.setDate(d.getDate() - 1);
  }
  return count;
}

export const useAppStore = create<AppState>((set, get) => ({
  initialized: false,
  loading: false,
  theme: "light",
  sidebarCollapsed: false,
  activeDate: formatDateKey(),
  activeEntryId: null,
  exportOpen: false,

  repo: getRepository(),
  entries: [],
  recentEntries: [],
  streak: 0,
  stats: { entries: 0, words: 0, images: 0 },
  settings: {
    version: 1,
    theme: "light",
    accent: "sky",
    font: "sans",
    displayName: "",
    motto: "",
    avatar: "",
    weekStartsOn: 1,
    defaultMood: "neutral",
    sync: { enabled: false, provider: "none" },
  },

  initialize: async () => {
    if (get().initialized || get().loading) return;
    set({ loading: true, error: undefined });
    try {
      const root = await resolveSingleVaultRoot();
      const repo = get().repo;
      await repo.init(root);
      const seeded = await repo.seedIfEmpty();
      const entries = await repo.listEntries();
      const stats = await repo.stats();
      const settings = await repo.loadSettings();
      const startDate = seeded ? formatDateKey() : get().activeDate;
      set({
        entries,
        recentEntries: entries.slice(0, 4),
        streak: computeStreak(entries.map((e) => e.date)),
        stats: {
          entries: stats.entries,
          words: stats.words,
          images: stats.images,
        },
        settings,
        theme: settings.theme,
        initialized: true,
        loading: false,
        // If we just seeded a sample "today", surface it as the active date.
        activeDate: startDate,
        // Open the latest entry of that day, if the day already has one.
        activeEntryId:
          entries.find((e) => e.date === startDate)?.id ?? null,
      });
    } catch (e) {
      set({
        error: e instanceof Error ? e.message : String(e),
        loading: false,
        initialized: true,
      });
    }
  },

  setTheme: (theme) => {
    set({ theme });
    const s = get().settings;
    const next = { ...s, theme };
    set({ settings: next });
    void get().repo.saveSettings(next).catch(() => undefined);
  },

  toggleSidebar: () => set((s) => ({ sidebarCollapsed: !s.sidebarCollapsed })),
  setActiveDate: (activeDate) => set({ activeDate }),
  setExportOpen: (exportOpen) => set({ exportOpen }),

  openEntry: (id, date) => {
    const known = date ?? get().entries.find((e) => e.id === id)?.date;
    set({ activeEntryId: id, activeDate: known ?? get().activeDate });
  },

  openDate: (date) => {
    // A day can hold several entries; open the most recent one, or offer a
    // blank entry when nothing has been written that day yet.
    const ofDay = get().entries.filter((e) => e.date === date);
    set({ activeDate: date, activeEntryId: ofDay[0]?.id ?? null });
  },

  startNewEntry: (date) =>
    set({ activeDate: date ?? formatDateKey(), activeEntryId: null }),

  updateSettings: (patch) => {
    const next = { ...get().settings, ...patch };
    set({ settings: next });
    void get().repo.saveSettings(next).catch(() => undefined);
  },

  upsertEntry: async (entry) => {
    await get().repo.saveEntry(entry);
    await get().refresh();
  },

  removeEntry: async (id) => {
    await get().repo.deleteEntry(id);
    if (get().activeEntryId === id) set({ activeEntryId: null });
    await get().refresh();
  },

  refresh: async () => {
    const repo = get().repo;
    const entries = await repo.listEntries();
    const stats = await repo.stats();
    const activeId = get().activeEntryId;
    set({
      // Drop a dangling selection (entry deleted here or by an external sync).
      activeEntryId:
        activeId && entries.some((e) => e.id === activeId) ? activeId : null,
      entries,
      recentEntries: entries.slice(0, 4),
      streak: computeStreak(entries.map((e) => e.date)),
      stats: {
        entries: stats.entries,
        words: stats.words,
        images: stats.images,
      },
    });
  },
}));

/** Convenience selector for the human-readable active date. */
export function useActiveHumanDate(): string {
  const activeDate = useAppStore((s) => s.activeDate);
  const [yStr, mStr, dStr] = activeDate.split("-");
  const y = Number(yStr ?? "2026");
  const m = Number(mStr ?? "1");
  const d = Number(dStr ?? "1");
  return formatHumanDate(new Date(y, m - 1, d));
}

export type { Mood };
