import { getStorage, type StorageAdapter } from "./storage";
import { createIndex } from "./db/index";
import type { IndexDatabase, IndexedEntry } from "./db/schema";
import { parseEntryFile, serializeEntryFile } from "./markdown";
import {
  entryFilePath,
  VAULT_LAYOUT,
} from "./vault";
import { archiveCurrent, listVersions, readVersion } from "./version";
import type { AppSettings, JournalEntry, JournalMeta } from "@/types/journal";
import { isTauri } from "./storage/types";
import { buildSampleEntries } from "./seed";
import { formatDateKey, uuid } from "./utils";

const DEFAULT_SETTINGS: AppSettings = {
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
};

/**
 * JournalRepository — the single high-level API the UI talks to.
 *
 * Responsibilities:
 *   - read/write Markdown files through a StorageAdapter
 *   - keep the SQLite-style index in sync (metadata + search extract only)
 *   - own vault creation, settings, and (dev) seeding
 *
 * Entries are addressed by `id`, never by date: a day can hold as many entries
 * as you like, and changing an entry's date just moves its file. `pathById`
 * maps ids to their actual file so entries written by older builds (one
 * `YYYY-MM-DD.md` per day) keep working untouched.
 *
 * The Markdown file on disk remains the source of truth. The index is a
 * derived cache; if it ever drifts, `reindex()` rebuilds it from disk.
 */
export class JournalRepository {
  private storage: StorageAdapter;
  private index: IndexDatabase | null = null;
  /** entry id -> vault-relative file path (rebuilt from disk on every scan). */
  private pathById = new Map<string, string>();
  /** True while `pathById` is known to mirror the vault (kept up to date by
   *  save/delete), so a missing id can be trusted as "not on disk". */
  private pathMapFresh = false;
  vaultRoot = "";

  constructor(storage?: StorageAdapter, index?: IndexDatabase) {
    this.storage = storage ?? getStorage();
    this.index = index ?? null;
  }

  /** Resolved index; throws if accessed before init(). */
  private get idx(): IndexDatabase {
    if (!this.index) throw new Error("JournalRepository used before init()");
    return this.index;
  }

  /** Expose the underlying storage backend (used by the sync engine). */
  get storageAdapter(): StorageAdapter {
    return this.storage;
  }

  async init(vaultRoot: string): Promise<void> {
    this.vaultRoot = vaultRoot;
    await this.storage.init(vaultRoot);
    if (!this.index) this.index = await createIndex();
    await this.idx.init();
    await this.reindex();
  }

  /** Rebuild the index (and the id -> path map) from on-disk Markdown. */
  async reindex(): Promise<void> {
    // Switching vaults must not leave the previous vault's entries in the
    // index — clear first, then re-derive everything from the new disk state.
    await this.idx.clear();
    this.pathById.clear();
    const files = await this.storage.list("entries/");
    for (const f of files) {
      if (!f.endsWith(".md")) continue;
      try {
        const raw = await this.storage.readText(f);
        const { meta, body } = parseEntryFile(raw);
        this.pathById.set(meta.id, f);
        await this.idx.upsert(toIndexed(meta, body));
      } catch {
        // skip unreadable / corrupt files
      }
    }
    this.pathMapFresh = true;
  }

  /** Read every entry from disk, newest first, refreshing the id -> path map. */
  async listEntries(): Promise<JournalEntry[]> {
    const files = await this.storage.list("entries/");
    const entries: JournalEntry[] = [];
    this.pathById.clear();
    for (const f of files) {
      if (!f.endsWith(".md")) continue;
      try {
        const raw = await this.storage.readText(f);
        const { meta, body } = parseEntryFile(raw);
        this.pathById.set(meta.id, f);
        entries.push({ ...meta, body });
      } catch {
        /* skip */
      }
    }
    this.pathMapFresh = true;
    return entries.sort(byRecency);
  }

  /** Locate an entry's file, rescanning the vault only when necessary. */
  private async resolvePath(id: string): Promise<string | null> {
    const known = this.pathById.get(id);
    if (known) {
      if (await this.storage.exists(known)) return known;
      // The file moved or was removed behind our back (e.g. by sync).
      this.pathById.delete(id);
      await this.listEntries();
      return this.pathById.get(id) ?? null;
    }
    if (this.pathMapFresh) return null; // brand-new entry: nothing to find
    await this.listEntries();
    return this.pathById.get(id) ?? null;
  }

  /** Load a single entry by its id. */
  async getEntry(id: string): Promise<JournalEntry | null> {
    const p = await this.resolvePath(id);
    if (!p) return null;
    try {
      const raw = await this.storage.readText(p);
      const { meta, body } = parseEntryFile(raw);
      return { ...meta, body };
    } catch {
      return null;
    }
  }

  /** All entries written for one day, newest first (a day may hold many). */
  async getEntriesByDate(dateKey: string): Promise<JournalEntry[]> {
    const all = await this.listEntries();
    return all.filter((e) => e.date === dateKey);
  }

  /**
   * Build a blank entry. It is NOT written to disk — the editor persists it on
   * the first real edit, so opening "new entry" and walking away never leaves
   * an empty file behind.
   */
  newEntry(dateKey?: string, defaults?: Partial<JournalEntry>): JournalEntry {
    const now = new Date().toISOString();
    return {
      id: uuid(),
      date: dateKey ?? formatDateKey(),
      title: "",
      mood: "neutral",
      weather: "unknown",
      tags: [],
      assets: [],
      body: "",
      created_at: now,
      updated_at: now,
      ...defaults,
    };
  }

  async saveEntry(entry: JournalEntry): Promise<void> {
    const now = new Date().toISOString();
    const e: JournalEntry = { ...entry, updated_at: now };
    const nextPath = entryFilePath(e);
    const prevPath = await this.resolvePath(e.id);
    const nextRaw = serializeEntryFile(e);

    // Snapshot the PREVIOUS on-disk content as a version, but only when the
    // incoming content actually differs — never on the very first save.
    if (prevPath) {
      try {
        const prevRaw = await this.storage.readText(prevPath);
        if (prevRaw.trim() !== nextRaw.trim()) {
          await archiveCurrent(this.storage, e.id, prevRaw);
        }
      } catch {
        /* unreadable previous file — just overwrite it */
      }
    }

    await this.storage.writeText(nextPath, nextRaw);
    // The date is metadata: when it changes (or when a legacy per-day file is
    // saved for the first time) the entry moves to its canonical location.
    if (prevPath && prevPath !== nextPath) {
      try {
        await this.storage.delete(prevPath);
      } catch {
        /* best effort — a stale copy is better than losing the new one */
      }
    }
    this.pathById.set(e.id, nextPath);
    await this.idx.upsert(toIndexed(e, e.body));
  }

  /**
   * Stored versions for an entry, newest first. Includes history recorded
   * before entries were decoupled from dates (`versions/<date>/`).
   */
  async listVersions(entry: Pick<JournalEntry, "id" | "date">) {
    return listVersions(this.storage, [entry.id, entry.date]);
  }

  /**
   * Restore a historical version as the entry's current content. The entry
   * keeps its identity, and the pre-restore content is archived first, so a
   * restore is always undoable.
   */
  async restoreVersion(
    entry: Pick<JournalEntry, "id" | "date">,
    version: number,
    versionKey?: string,
  ): Promise<JournalEntry> {
    const key = versionKey ?? entry.id;
    const snapshot = await readVersion(this.storage, key, version);
    const restored: JournalEntry = { ...snapshot, id: entry.id };
    await this.saveEntry(restored);
    return restored;
  }

  async deleteEntry(id: string): Promise<void> {
    const p = await this.resolvePath(id);
    if (p) {
      try {
        await this.storage.delete(p);
      } catch {
        /* already gone */
      }
      this.pathById.delete(id);
    }
    await this.idx.remove(id);
  }

  /** Full-text search across title / body / tags / location. */
  async search(query: string): Promise<IndexedEntry[]> {
    return this.idx.search(query);
  }

  async stats() {
    return this.idx.stats();
  }

  async loadSettings(): Promise<AppSettings> {
    const p = VAULT_LAYOUT.settings;
    if (!(await this.storage.exists(p))) return { ...DEFAULT_SETTINGS };
    try {
      const raw = await this.storage.readText(p);
      return { ...DEFAULT_SETTINGS, ...(JSON.parse(raw) as Partial<AppSettings>) };
    } catch {
      return { ...DEFAULT_SETTINGS };
    }
  }

  async saveSettings(settings: AppSettings): Promise<void> {
    await this.storage.writeText(
      VAULT_LAYOUT.settings,
      JSON.stringify(settings, null, 2),
    );
  }

  /** Dev-only: seed sample entries into an empty browser vault. */
  async seedIfEmpty(): Promise<boolean> {
    if (this.storage.kind !== "browser") return false;
    const existing = await this.storage.list("entries/");
    if (existing.length > 0) return false;
    for (const e of buildSampleEntries()) await this.saveEntry(e);
    return true;
  }
}

/** Newest first: by date, then by creation time within the same day. */
export function byRecency(a: JournalEntry, b: JournalEntry): number {
  if (a.date !== b.date) return a.date < b.date ? 1 : -1;
  if (a.created_at !== b.created_at) return a.created_at < b.created_at ? 1 : -1;
  return 0;
}

export function toIndexed(meta: JournalMeta, body: string): IndexedEntry {
  const words = (body.match(/[\p{L}\p{N}]+/gu) ?? []).length;
  const images = (body.match(/!\[[^\]]*\]\(([^)]+)\)/g) ?? []).length;
  return {
    id: meta.id,
    date: meta.date,
    title: meta.title,
    body: body.replace(/[#>*_`~\-]/g, " ").slice(0, 20000),
    tags: meta.tags.join(" "),
    mood: meta.mood,
    weather: meta.weather,
    location: meta.location ?? "",
    created_at: meta.created_at,
    updated_at: meta.updated_at,
    word_count: words,
    image_count: images,
  };
}

let repo: JournalRepository | null = null;

/** Resolve the vault root: real app-data dir in Tauri, a browser namespace otherwise. */
export async function resolveVaultRoot(): Promise<string> {
  if (isTauri()) {
    const { appDataDir } = await import("@tauri-apps/api/path");
    const dir = await appDataDir();
    return `${dir.replace(/\\/g, "/")}/my-diary`;
  }
  return "browser-vault";
}

export function getRepository(): JournalRepository {
  if (!repo) repo = new JournalRepository();
  return repo;
}
