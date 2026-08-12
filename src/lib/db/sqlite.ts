/**
 * Native SQLite FTS5 slot (future upgrade).
 *
 * The default index today is `MemoryIndex` (`../memory.ts`), which implements a
 * real in-memory inverted-index full-text engine (term-frequency ranking + CJK
 * bigram tokenization) behind the shared `IndexDatabase` interface — no native
 * module or WASM required, so it runs identically in the browser and the Tauri
 * webview.
 *
 * When a native SQLite binding is available (e.g. `better-sqlite3` in Tauri, or
 * `sql.js` compiled in), a `SqliteIndex` implementing the SAME interface can be
 * dropped in here and wired up in `./index.ts` `createIndex()` WITHOUT touching
 * any caller. That would add a disk-backed FTS5 table and persist the index
 * across sessions.
 */

export {};
