import { parseEntryFile, serializeEntryFile } from "@/lib/markdown";
import { entryFilePath, versionDir, versionFilePath } from "@/lib/vault";
import type { StorageAdapter } from "@/lib/storage/types";
import type { JournalEntry } from "@/types/journal";

export interface VersionMeta {
  version: number;
  date: string;
  title: string;
  updated_at: string;
  /** Short plain-text preview of the body. */
  preview: string;
}

/** All stored versions for a given date, newest first. */
export async function listVersions(
  storage: StorageAdapter,
  dateKey: string,
): Promise<VersionMeta[]> {
  const dir = versionDir(dateKey);
  let files: string[] = [];
  try {
    files = await storage.list(dir + "/");
  } catch {
    return [];
  }
  const versions: VersionMeta[] = [];
  for (const f of files) {
    const m = /v(\d+)\.md$/.exec(f);
    if (!m) continue;
    try {
      const raw = await storage.readText(f);
      const { meta, body } = parseEntryFile(raw);
      versions.push({
        version: Number(m[1]),
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
  return versions.sort((a, b) => b.version - a.version);
}

/** Next sequential version number for a date. */
export async function nextVersionNumber(
  storage: StorageAdapter,
  dateKey: string,
): Promise<number> {
  const existing = await listVersions(storage, dateKey);
  return (existing[0]?.version ?? 0) + 1;
}

/**
 * Archive the CURRENT on-disk content of an entry as a new version file
 * (versions/<date>/vN.md). Returns the version number, or null if nothing was
 * archived.
 */
export async function archiveCurrent(
  storage: StorageAdapter,
  dateKey: string,
  existingRaw: string,
): Promise<number | null> {
  const n = await nextVersionNumber(storage, dateKey);
  await storage.writeText(versionFilePath(dateKey, n), existingRaw);
  return n;
}

/** Read a specific version file back into a JournalEntry. */
export async function readVersion(
  storage: StorageAdapter,
  dateKey: string,
  version: number,
): Promise<JournalEntry> {
  const raw = await storage.readText(versionFilePath(dateKey, version));
  const { meta, body } = parseEntryFile(raw);
  return { ...meta, body };
}

/** Restore a version to be the current entry; returns the restored entry. */
export async function restoreVersion(
  storage: StorageAdapter,
  dateKey: string,
  version: number,
): Promise<JournalEntry> {
  const entry = await readVersion(storage, dateKey, version);
  await storage.writeText(entryFilePath(dateKey), serializeEntryFile(entry));
  return entry;
}
