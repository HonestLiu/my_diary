import type { AssetKind } from "@/types/journal";

/**
 * Vault layout (the canonical, open on-disk structure):
 *
 * MyDiary/
 * ├── entries/YYYY/MM/YYYY-MM-DD-<shortid>.md
 * ├── assets/{images,audio,video,attachments}/
 * ├── metadata/{index.json,sync.json}
 * ├── versions/<entry-id>/vN.md
 * ├── conflicts/<entry-file-name>.{local,remote}.md
 * └── settings.json
 *
 * An entry is identified by its `id`, NOT by its date: any number of entries
 * may share the same day. The date is ordinary metadata (it decides which
 * folder the file lives in and how the UI groups it), so moving an entry to
 * another day is just a metadata edit plus a file move.
 *
 * Files written by older versions of the app (`entries/YYYY/MM/YYYY-MM-DD.md`,
 * one per day) are still read normally — see `dateKeyFromEntryPath` and
 * `JournalRepository.reindex()`.
 *
 * All functions return paths RELATIVE to the vault root so the same code
 * works against any StorageAdapter (disk via Tauri, or IndexedDB in browser).
 */

export const VAULT_LAYOUT = {
  settings: "settings.json",
  index: "metadata/index.json",
  sync: "metadata/sync.json",
  entries: "entries",
  assets: "assets",
  versions: "versions",
  conflicts: "conflicts",
} as const;

/** Minimal shape needed to derive an entry's on-disk location. */
export interface EntryFileRef {
  id: string;
  date: string;
}

/**
 * Short, filename-safe fragment of an entry id. Keeps filenames readable
 * (`2026-08-17-9f1c2e0a.md`) while still distinguishing several entries that
 * share a date.
 */
export function shortEntryId(id: string): string {
  const clean = id.replace(/[^0-9a-zA-Z]/g, "").toLowerCase();
  return clean.slice(0, 8) || "entry";
}

export function entryFileName(entry: EntryFileRef): string {
  return `${entry.date}-${shortEntryId(entry.id)}.md`;
}

/** Canonical path of an entry file: entries/YYYY/MM/YYYY-MM-DD-<shortid>.md */
export function entryFilePath(entry: EntryFileRef): string {
  return `${entryDir(entry.date)}/${entryFileName(entry)}`;
}

export function entryDir(dateKey: string): string {
  const [y, m] = dateKey.split("-");
  return `entries/${y}/${m}`;
}

export function assetDir(kind: AssetKind): string {
  switch (kind) {
    case "image":
      return "assets/images";
    case "audio":
      return "assets/audio";
    case "video":
      return "assets/video";
    case "attachment":
      return "assets/attachments";
  }
}

export function assetPath(kind: AssetKind, filename: string): string {
  return `${assetDir(kind)}/${filename}`;
}

/**
 * Version folder for an entry. The key is the entry id; vaults written by
 * older builds used the date key, which `listVersions` still reads.
 */
export function versionDir(entryKey: string): string {
  return `versions/${sanitizeKey(entryKey)}`;
}

export function versionFilePath(entryKey: string, version: number): string {
  return `${versionDir(entryKey)}/v${version}.md`;
}

export function conflictFilePath(key: string, side: "local" | "remote"): string {
  return `conflicts/${sanitizeKey(key)}.${side}.md`;
}

/** Strip anything that is unsafe (or path-traversing) in a file name. */
export function sanitizeKey(key: string): string {
  return key.replace(/[^0-9a-zA-Z._-]/g, "_") || "entry";
}

/**
 * Extract the date key (YYYY-MM-DD) from an entry file path. Accepts both the
 * current `YYYY-MM-DD-<shortid>.md` naming and the legacy `YYYY-MM-DD.md`.
 */
export function dateKeyFromEntryPath(path: string): string | null {
  const m = /entries\/\d{4}\/\d{2}\/(\d{4}-\d{2}-\d{2})(?:-[0-9a-zA-Z]+)?\.md$/.exec(
    path,
  );
  return m?.[1] ?? null;
}

/**
 * Stable, collision-free key for naming conflict copies of a synced file:
 * the entry file's own base name when possible, otherwise the flattened path.
 */
export function conflictKeyFromPath(path: string): string {
  const base = /([^/]+)\.md$/.exec(path)?.[1];
  if (base && dateKeyFromEntryPath(path)) return base;
  return path.replace(/\//g, "_").replace(/\.md$/, "");
}

/** All directories that should exist at the root of a fresh vault. */
export function requiredDirectories(): string[] {
  return [
    "entries",
    "assets/images",
    "assets/audio",
    "assets/video",
    "assets/attachments",
    "metadata",
    "versions",
    "conflicts",
    "profile",
  ];
}

/** 个人资料文件（如头像）：`profile/<filename>`，随 vault 导出/同步。 */
export function profileAvatarPath(filename: string): string {
  return `profile/${filename}`;
}
