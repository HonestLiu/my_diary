/**
 * Index database contract.
 *
 * Per the architecture, the local SQLite database NEVER stores journal body
 * text as the source of truth — it only indexes metadata + a plain-text
 * extract for search, caches sync state, and answers stats queries.
 *
 * The canonical SQL (used by the real SQLite binding in Phase 4) is FTS5:
 *
 *   CREATE VIRTUAL TABLE IF NOT EXISTS entry_fts USING fts5(
 *     id UNINDEXED,
 *     date UNINDEXED,
 *     title,
 *     body,
 *     tags,
 *     mood UNINDEXED,
 *     weather UNINDEXED,
 *     location,
 *     created_at UNINDEXED,
 *     updated_at UNINDEXED,
 *     word_count UNINDEXED,
 *     image_count UNINDEXED,
 *     tokenize = 'unicode61 remove_diacritics 2'
 *   );
 *
 * For Phase 2 we ship an in-memory implementation of this contract so the
 * app runs in a browser today; Phase 4 swaps in the FTS5-backed store
 * without touching any caller.
 */

export interface IndexedEntry {
  id: string;
  date: string;
  title: string;
  /** Plain-text extract of the body, for full-text search only. */
  body: string;
  tags: string;
  mood: string;
  weather: string;
  location: string;
  created_at: string;
  updated_at: string;
  word_count: number;
  image_count: number;
}

export interface IndexStats {
  entries: number;
  words: number;
  images: number;
}

export interface IndexDatabase {
  init(): Promise<void>;
  upsert(entry: IndexedEntry): Promise<void>;
  remove(id: string): Promise<void>;
  /** Drop all entries (used when switching vaults so stale entries don't linger). */
  clear(): Promise<void>;
  /** Full-text search across title / body / tags. */
  search(query: string): Promise<IndexedEntry[]>;
  all(): Promise<IndexedEntry[]>;
  stats(): Promise<IndexStats>;
}
