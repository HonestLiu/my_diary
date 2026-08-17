import { parseEntryFile } from "@/lib/markdown";
import { versionDir, versionFilePath } from "@/lib/vault";
import type { StorageAdapter } from "@/lib/storage/types";
import type { JournalEntry } from "@/types/journal";

export interface VersionMeta {
  version: number;
  /**
   * Folder key the version was read from — the entry id for anything written
   * by the current build, or a date key for vaults created before entries were
   * decoupled from dates. Needed to read the file back.
   */
  key: string;
  date: string;
  title: string;
  updated_at: string;
  /** Short plain-text preview of the body. */
  preview: string;
}

/**
 * All stored versions for the given folder keys, newest first.
 *
 * Several keys may be passed so an entry can surface both its own history
 * (`versions/<entry-id>/`) and the legacy per-date history (`versions/<date>/`)
 * written before one day could hold several entries.
 */
export async function listVersions(
  storage: StorageAdapter,
  keys: string | string[],
): Promise<VersionMeta[]> {
  const list = (Array.isArray(keys) ? keys : [keys]).filter(Boolean);
  const seenKeys = new Set<string>();
  const versions: VersionMeta[] = [];

  for (const key of list) {
    if (seenKeys.has(key)) continue;
    seenKeys.add(key);
    const dir = versionDir(key);
    let files: string[] = [];
    try {
      files = await storage.list(dir + "/");
    } catch {
      continue;
    }
    for (const f of files) {
      const m = /v(\d+)\.md$/.exec(f);
      if (!m) continue;
      try {
        const raw = await storage.readText(f);
        const { meta, body } = parseEntryFile(raw);
        versions.push({
          version: Number(m[1]),
          key,
          date: meta.date,
          title: meta.title,
          updated_at: meta.updated_at,
          preview: body
            .replace(/[#>*_`~]/g, " ")
            .replace(/\s+/g, " ")
            .trim()
            .slice(0, 80),
        });
      } catch {
        /* skip unreadable version */
      }
    }
  }

  // Newest first. Version numbers restart per folder, so timestamps decide the
  // order once more than one folder contributes.
  return versions.sort((a, b) => {
    if (a.updated_at !== b.updated_at) return a.updated_at < b.updated_at ? 1 : -1;
    return b.version - a.version;
  });
}

/** Next sequential version number within one folder. */
export async function nextVersionNumber(
  storage: StorageAdapter,
  key: string,
): Promise<number> {
  const existing = await listVersions(storage, key);
  // Max, not "first" — the list is ordered by timestamp, which can disagree
  // with the numeric sequence for hand-edited or imported version files.
  return existing.reduce((max, v) => Math.max(max, v.version), 0) + 1;
}

/**
 * Archive raw entry-file content as a new version (versions/<key>/vN.md).
 * Returns the version number, or null if nothing was archived.
 */
export async function archiveCurrent(
  storage: StorageAdapter,
  key: string,
  existingRaw: string,
): Promise<number | null> {
  const n = await nextVersionNumber(storage, key);
  await storage.writeText(versionFilePath(key, n), existingRaw);
  return n;
}

/** Read a specific version file back into a JournalEntry. */
export async function readVersion(
  storage: StorageAdapter,
  key: string,
  version: number,
): Promise<JournalEntry> {
  const raw = await storage.readText(versionFilePath(key, version));
  const { meta, body } = parseEntryFile(raw);
  return { ...meta, body };
}
