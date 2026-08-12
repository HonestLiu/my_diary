import type { StorageAdapter } from "./types";
import { isTauri } from "./types";
import { BrowserAdapter } from "./browser";
import { TauriFsAdapter } from "./tauri";

let cached: StorageAdapter | null = null;

/**
 * Resolve the active storage backend.
 *   - Inside Tauri  → disk (TauriFsAdapter)
 *   - Otherwise     → IndexedDB (BrowserAdapter)
 *
 * Selection is lazy and memoized so callers can import `getStorage()` freely.
 */
export function getStorage(): StorageAdapter {
  if (cached) return cached;
  cached = isTauri() ? new TauriFsAdapter() : new BrowserAdapter();
  return cached;
}

/** Force a specific adapter (used by tests or future web builds). */
export function setStorage(adapter: StorageAdapter): void {
  cached = adapter;
}

export type { StorageAdapter } from "./types";
