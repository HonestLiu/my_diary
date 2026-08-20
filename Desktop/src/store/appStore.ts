import { create } from "zustand";
import { invoke } from "@tauri-apps/api/core";
import type {
  AppSettings,
  JournalEntry,
  Mood,
  SyncResult,
  Theme,
} from "@/types/journal";
import { formatDateKey, formatHumanDate } from "@/lib/utils";
import {
  getRepository,
  type JournalRepository,
} from "@/lib/journal";
import { isTauri } from "@/lib/storage/types";
import { entryFilePath, profileFilePath } from "@/lib/vault";
import { sha256Hex } from "@/lib/crypto";

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
  /** 当前需要解决的冲突条目路径（null = 无对话框）。由 ConflictResolveDialog 读取。 */
  resolveConflictPath: string | null;

  /* ---- Sync (P7)：共享「正在同步 / 上次同步」状态，供顶栏按钮与设置页复用 ---- */
  syncing: boolean;
  syncError?: string;
  lastSyncAt?: number;
  /**
   * 尚未同步到云端的条目文件路径（相对 vault 根）。每次 refresh 后按
   * 本地基线（metadata/sync.json）与当前文件哈希比对得出；未配置同步时为空。
   * 待解决冲突的路径不计入（它们不是「未同步」，而是「冲突待解决」，见
   * conflictPaths），避免出现「无论怎么同步都显示未同步」的假象。
   */
  unsyncedPaths: Set<string>;
  /**
   * 待解决冲突的条目文件路径（metadata/conflicts.json，设备本地、不进同步）。
   * 这类条目由用户在设置页显式解决（保留本地 / 采用远端），不是同步能清除的。
   */
  conflictPaths: Set<string>;

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
  /** 设置需要解决的冲突路径（null = 无对话框）。触发后由 AppLayout 渲染确认对话框。 */
  setResolveConflictPath: (path: string | null) => void;
  upsertEntry: (entry: JournalEntry) => Promise<void>;
  removeEntry: (id: string) => Promise<void>;
  refresh: () => Promise<void>;
  /** 立即同步（Rust `sync_vault`）。使用已保存的 settings.sync 配置。 */
  syncNow: () => Promise<void>;
  /** 重新计算未同步条目的路径集合（哈希比对本地基线）。 */
  computeUnsynced: () => Promise<void>;
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

/* ------------------------------------------------------------------ */
/* 便携个人档案 profile/profile.json：displayName / motto / avatar。    */
/* 随同步在设备间迁移；本地 settings.json 仍存完整偏好（含凭据），但    */
/* 不同步。头像本体是 profile/avatar.<ext>，同样随同步迁移。            */
/* ------------------------------------------------------------------ */

interface PortableProfile {
  displayName?: string;
  motto?: string;
  avatar?: string;
}

async function readPortableProfile(
  repo: JournalRepository,
): Promise<PortableProfile | null> {
  try {
    if (!(await repo.storageAdapter.exists(profileFilePath()))) return null;
    const raw = await repo.storageAdapter.readText(profileFilePath());
    const p = JSON.parse(raw) as PortableProfile;
    return typeof p === "object" && p !== null ? p : null;
  } catch {
    return null;
  }
}

async function writePortableProfile(
  repo: JournalRepository,
  settings: AppSettings,
): Promise<void> {
  const profile: PortableProfile = {
    displayName: settings.displayName ?? "",
    motto: settings.motto ?? "",
    avatar: settings.avatar ?? "",
  };
  await repo.storageAdapter.writeText(
    profileFilePath(),
    JSON.stringify(profile, null, 2),
  );
}

/** 加载时把同步来的便携档案合并进本地设置（本地值为空时优先取档案值）。 */
async function applyPortableProfile(
  repo: JournalRepository,
  settings: AppSettings,
): Promise<AppSettings> {
  const p = await readPortableProfile(repo);
  if (!p) return settings;
  return {
    ...settings,
    displayName: p.displayName ?? settings.displayName,
    motto: p.motto ?? settings.motto,
    avatar: p.avatar ?? settings.avatar,
  };
}

/**
 * 首次加载且本地已存在档案数据时写入 profile.json 随同步导出；
 * 已有 profile.json 或本地无档案时不做任何事，避免空文件覆盖别端数据。
 */
async function bootstrapPortableProfile(
  repo: JournalRepository,
  settings: AppSettings,
): Promise<void> {
  const has = Boolean(settings.displayName || settings.motto || settings.avatar);
  if (!has) return;
  if (await readPortableProfile(repo)) return;
  await writePortableProfile(repo, settings);
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
  resolveConflictPath: null as string | null,
  syncing: false,
  unsyncedPaths: new Set<string>(),
  conflictPaths: new Set<string>(),

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
    imageCompressQuality: 80,
    videoCompressQuality: 60,
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
      // 合并同步来的便携档案（displayName / motto / avatar）。
      const settings = await applyPortableProfile(repo, await repo.loadSettings());
      await bootstrapPortableProfile(repo, settings);
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
      void get().computeUnsynced();
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
  setResolveConflictPath: (path) => set({ resolveConflictPath: path }),

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
    // 个人档案字段变化时同步写 profile/profile.json，随 vault 同步迁移。
    if ("displayName" in patch || "motto" in patch || "avatar" in patch) {
      void writePortableProfile(get().repo, next).catch(() => undefined);
    }
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
    void get().computeUnsynced();
  },

  computeUnsynced: async () => {
    const s = get();
    const cfg = s.settings.sync;
    const configured =
      !!cfg &&
      cfg.provider !== "none" &&
      !!cfg.endpoint &&
      !!cfg.bucket &&
      !!cfg.accessKey &&
      !!cfg.secretKey;
    if (!configured) {
      if (s.unsyncedPaths.size > 0 || s.conflictPaths.size > 0) {
        set({ unsyncedPaths: new Set(), conflictPaths: new Set() });
      }
      return;
    }
    const repo = s.repo;
    // 待解决冲突（metadata/conflicts.json，设备本地、不进同步）：这类路径不是
    // 「未同步」，而是「冲突待解决」，需在设置页显式处理。
    let conflictPaths = new Set<string>();
    try {
      if (await repo.storageAdapter.exists("metadata/conflicts.json")) {
        const list = JSON.parse(
          await repo.storageAdapter.readText("metadata/conflicts.json"),
        ) as string[];
        conflictPaths = new Set(list);
      }
    } catch {
      conflictPaths = new Set();
    }
    // 本地基线（Rust 每次同步后写入）：path -> 上次已同步的 sha256。
    let baseline: Record<string, string> = {};
    try {
      if (await repo.storageAdapter.exists("metadata/sync.json")) {
        const m = JSON.parse(
          await repo.storageAdapter.readText("metadata/sync.json"),
        ) as { files?: { path: string; hash: string }[] };
        baseline = Object.fromEntries(
          (m.files ?? []).map((f) => [f.path, f.hash]),
        );
      }
    } catch {
      baseline = {};
    }
    const unsynced = new Set<string>();
    await Promise.all(
      s.entries.map(async (e) => {
        const path = entryFilePath({ id: e.id, date: e.date });
        try {
          const bytes = await repo.storageAdapter.readBytes(path);
          const hash = await sha256Hex(bytes);
          if (hash !== baseline[path] && !conflictPaths.has(path)) {
            unsynced.add(path);
          }
        } catch {
          /* 文件缺失（如旧版路径）——无法比对，跳过 */
        }
      }),
    );
    set({ unsyncedPaths: unsynced, conflictPaths });
  },

  syncNow: async () => {
    const s = get();
    if (s.syncing) return;
    if (!isTauri()) {
      set({ syncError: "云同步仅在桌面端（Tauri）可用。" });
      return;
    }
    const cfg = s.settings.sync;
    if (!cfg || cfg.provider === "none") {
      set({ syncError: "同步未配置：请先在“设置 → 云同步”中填写并保存。" });
      return;
    }
    if (!cfg.endpoint || !cfg.bucket || !cfg.accessKey || !cfg.secretKey) {
      set({ syncError: "同步凭据不完整：请先在设置中补全并保存。" });
      return;
    }
    const vaultRoot = s.repo.vaultRoot;
    if (!vaultRoot) {
      set({ syncError: "未找到 vault 根目录。" });
      return;
    }
    set({ syncing: true, syncError: undefined });
    try {
      // 同步逻辑完全在 Rust 侧（src-tauri/src/sync.rs），前端只调用命令。
      // `enabled` 是历史遗留字段（桌面端 UI 未暴露开关），仅保证 Rust
      // serde 反序列化不缺字段即可，实际以 provider/凭据为准。
      await invoke<SyncResult>("sync_vault", {
        vaultRoot,
        config: { ...cfg, enabled: cfg.enabled ?? false },
      });
      set({ lastSyncAt: Date.now() });
      await get().refresh();
      await get().computeUnsynced();
      // 同步可能下载了新 profile.json —— 立即合并档案，让昵称/座右铭/头像生效。
      const cur = get().settings;
      const merged = await applyPortableProfile(get().repo, cur);
      if (
        merged.displayName !== cur.displayName ||
        merged.motto !== cur.motto ||
        merged.avatar !== cur.avatar
      ) {
        set({ settings: merged });
      }
    } catch (e) {
      set({ syncError: e instanceof Error ? e.message : String(e) });
    } finally {
      set({ syncing: false });
    }
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
