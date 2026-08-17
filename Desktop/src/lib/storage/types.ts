/**
 * StorageAdapter — the single abstraction over "where journal files live".
 *
 * Two implementations exist:
 *   - TauriFsAdapter  : real disk via @tauri-apps/plugin-fs (production)
 *   - BrowserAdapter  : IndexedDB (dev preview + web fallback, fully functional)
 *
 * Paths passed to adapters are RELATIVE to the vault root. This keeps the
 * vault format identical everywhere and makes the Markdown files portable.
 */
export interface StorageAdapter {
  readonly kind: "tauri" | "browser";
  /** Create the vault root and required directories if missing. */
  init(vaultRoot: string): Promise<void>;
  readText(path: string): Promise<string>;
  writeText(path: string, content: string): Promise<void>;
  readBytes(path: string): Promise<Uint8Array>;
  writeBytes(path: string, data: Uint8Array): Promise<void>;
  exists(path: string): Promise<boolean>;
  delete(path: string): Promise<void>;
  /** List all stored paths (files) under a relative prefix. */
  list(prefix: string): Promise<string[]>;
  /**
   * Resolve a vault-relative asset path (e.g. "assets/images/x.webp") to a
   * URL usable as an <img src>. Browser → object URL from IndexedDB blob;
   * Tauri → data URL decoded from disk bytes. Asset references stay relative
   * on disk, satisfying the "relative path reference" design rule.
   */
  resolveUrl(relPath: string): Promise<string>;
}

/** Detect whether we are running inside a Tauri webview. */
export function isTauri(): boolean {
  if (typeof window === "undefined") return false;
  return "__TAURI_INTERNALS__" in window || "__TAURI__" in window;
}
