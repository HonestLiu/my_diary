import type { AssetKind } from "@/types/journal";

/**
 * Vault layout (the canonical, open on-disk structure):
 *
 * MyDiary/
 * ├── entries/YYYY/MM/YYYY-MM-DD.md
 * ├── assets/{images,audio,video,attachments}/
 * ├── metadata/{index.json,sync.json}
 * ├── versions/YYYY-MM-DD/vN.md
 * ├── conflicts/YYYY-MM-DD.{local,remote}.md
 * └── settings.json
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

export function entryFilePath(dateKey: string): string {
  const [y, m] = dateKey.split("-");
  return `entries/${y}/${m}/${dateKey}.md`;
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

export function versionDir(dateKey: string): string {
  return `versions/${dateKey}`;
}

export function versionFilePath(dateKey: string, version: number): string {
  return `${versionDir(dateKey)}/v${version}.md`;
}

export function conflictFilePath(dateKey: string, side: "local" | "remote"): string {
  return `conflicts/${dateKey}.${side}.md`;
}

/** Extract the date key (YYYY-MM-DD) from an entry file path. */
export function dateKeyFromEntryPath(path: string): string | null {
  const m = /entries\/\d{4}\/\d{2}\/(\d{4}-\d{2}-\d{2})\.md$/.exec(path);
  return m?.[1] ?? null;
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
  ];
}
