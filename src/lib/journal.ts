import { getStorage, type StorageAdapter } from "./storage";
import { createIndex } from "./db/index";
import type { IndexDatabase, IndexedEntry } from "./db/schema";
import { parseEntryFile, serializeEntryFile } from "./markdown";
import {
  entryFilePath,
  VAULT_LAYOUT,
} from "./vault";
import { archiveCurrent, listVersions, restoreVersion } from "./version";
import type { AppSettings, JournalEntry, JournalMeta } from "@/types/journal";
import { isTauri } from "./storage/types";
import { buildSampleEntries } from "./seed";

const DEFAULT_SETTINGS: AppSettings = {
  version: 1,
  theme: "light",
  defaultMood: "neutral",
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
 * The Markdown file on disk remains the source of truth. The index is a
 * derived cache; if it ever drifts, `reindex()` rebuilds it from disk.
 */
export class JournalRepository {
  private storage: StorageAdapter;
  private index: IndexDatabase | null = null;
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

  /** Rebuild the index from on-disk Markdown (idempotent). */
  async reindex(): Promise<void> {
    // Switching vaults must not leave the previous vault's entries in the
    // index — clear first, then re-derive everything from the new disk state.
    await this.idx.clear();
    const files = await this.storage.list("entries/");
    for (const f of files) {
      try {
        const raw = await this.storage.readText(f);
        const { meta, body } = parseEntryFile(raw);
        await this.idx.upsert(toIndexed(meta, body));
      } catch {
        // skip unreadable / corrupt files
      }
    }
  }

  async listEntries(): Promise<JournalEntry[]> {
    const files = await this.storage.list("entries/");
    const entries: JournalEntry[] = [];
    for (const f of files) {
      try {
        const raw = await this.storage.readText(f);
        const { meta, body } = parseEntryFile(raw);
        entries.push({ ...meta, body });
      } catch {
        /* skip */
      }
    }
    return entries.sort((a, b) => (a.date < b.date ? 1 : -1));
  }

  async getEntry(dateKey: string): Promise<JournalEntry | null> {
    const p = entryFilePath(dateKey);
    if (!(await this.storage.exists(p))) return null;
    const raw = await this.storage.readText(p);
    const { meta, body } = parseEntryFile(raw);
    return { ...meta, body };
  }

  async saveEntry(entry: JournalEntry): Promise<void> {
    const now = new Date().toISOString();
    const e: JournalEntry = { ...entry, updated_at: now };
    const path = entryFilePath(e.date);
    // Snapshot the PREVIOUS on-disk content as a version, but only when the
    // incoming content actually differs — never on the very first save.
    if (await this.storage.exists(path)) {
      const prevRaw = await this.storage.readText(path);
      const nextRaw = serializeEntryFile(e);
      if (prevRaw.trim() !== nextRaw.trim()) {
        await archiveCurrent(this.storage, e.date, prevRaw);
      }
    }
    await this.storage.writeText(path, serializeEntryFile(e));
    await this.idx.upsert(toIndexed(e, e.body));
  }

  /** List stored versions for a date (newest first). */
  async listVersions(dateKey: string) {
    return listVersions(this.storage, dateKey);
  }

  /** Restore a historical version to be the current entry. */
  async restoreVersion(dateKey: string, version: number): Promise<JournalEntry> {
    const entry = await restoreVersion(this.storage, dateKey, version);
    await this.idx.upsert(toIndexed(entry, entry.body));
    return entry;
  }

  async deleteEntry(dateKey: string): Promise<void> {
    const e = await this.getEntry(dateKey);
    const p = entryFilePath(dateKey);
    if (await this.storage.exists(p)) await this.storage.delete(p);
    if (e) await this.idx.remove(e.id);
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
