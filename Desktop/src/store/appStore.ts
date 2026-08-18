import { create } from "zustand";
import type { AppSettings, JournalEntry, Mood, Theme } from "@/types/journal";
import { formatDateKey, formatHumanDate } from "@/lib/utils";
import {
  getRepository,
  type JournalRepository,
} from "@/lib/journal";
import {
  ensureRegistry,
  loadRegistry,
  makeVault,
  resolveRootForVault,
  saveRegistry,
  type VaultDescriptor,
} from "@/lib/vaultManager";

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

  /* ---- Multi-vault ---- */
  vaults: VaultDescriptor[];
  activeVaultId: string;

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
  switchVault: (id: string) => Promise<void>;
  createVault: (name: string, path?: string) => Promise<void>;
  renameVault: (id: string, name: string) => Promise<void>;
  removeVault: (id: string) => Promise<void>;
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
    weekStartsOn: 1,
    defaultMood: "neutral",
    sync: { enabled: false, provider: "none" },
  },

  vaults: [],
  activeVaultId: "",

  initialize: async () => {
    if (get().initialized || get().loading) return;
    set({ loading: true, error: undefined });
    try {
      const reg = ensureRegistry();
      const active =
        reg.vaults.find((v) => v.id === reg.activeId) ?? reg.vaults[0];
      if (!active) {
        set({ error: "未找到任何日记库", loading: false, initialized: true });
        return;
      }
      const root = await resolveRootForVault(active);
      const repo = get().repo;
      await repo.init(root);
      const seeded = await repo.seedIfEmpty();
      const entries = await repo.listEntries();
      const stats = await repo.stats();
      const settings = await repo.loadSettings();
      const startDate = seeded ? formatDateKey() : get().activeDate;
      set({
        vaults: reg.vaults,
        activeVaultId: active.id,
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

  /**
   * Load (or reload) the active vault's data into the store after (re)pointing
   * the repository at a vault root. Shared by initialize() and switchVault().
   */
  switchVault: async (id: string) => {
    const reg = loadRegistry();
    const target = reg.vaults.find((v) => v.id === id);
    if (!target) return;
    set({ loading: true, error: undefined });
    try {
      const root = await resolveRootForVault(target);
      const repo = get().repo;
      await repo.init(root);
      await repo.seedIfEmpty();
      const entries = await repo.listEntries();
      const stats = await repo.stats();
      const settings = await repo.loadSettings();
      saveRegistry({ vaults: reg.vaults, activeId: id });
      set({
        vaults: reg.vaults,
        activeVaultId: id,
        // Entry ids belong to a vault — never carry one across a switch.
        activeEntryId:
          entries.find((e) => e.date === get().activeDate)?.id ?? null,
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
        loading: false,
      });
    } catch (e) {
      set({
        error: e instanceof Error ? e.message : String(e),
        loading: false,
      });
    }
  },

  createVault: async (name: string, path?: string) => {
    const reg = loadRegistry();
    const vault = makeVault(name, path);
    const next = {
      vaults: [...reg.vaults, vault],
      activeId: vault.id,
    };
    saveRegistry(next);
    await get().switchVault(vault.id);
  },

  renameVault: async (id: string, name: string) => {
    const reg = loadRegistry();
    const vaults = reg.vaults.map((v) =>
      v.id === id ? { ...v, name: name.trim() || v.name } : v,
    );
    saveRegistry({ vaults, activeId: reg.activeId });
    set({ vaults });
  },

  removeVault: async (id: string) => {
    const reg = loadRegistry();
    if (reg.vaults.length <= 1) return; // never remove the last vault
    const vaults = reg.vaults.filter((v) => v.id !== id);
    const activeId = reg.activeId === id ? (vaults[0]?.id ?? reg.activeId) : reg.activeId;
    saveRegistry({ vaults, activeId });
    if (reg.activeId === id) {
      await get().switchVault(activeId);
    } else {
      set({ vaults });
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
