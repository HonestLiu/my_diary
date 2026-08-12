import type { IndexDatabase } from "./schema";
import { MemoryIndex } from "./memory";

/**
 * Resolve the index implementation used by the journal repository.
 *
 * The default is `MemoryIndex` — a real in-memory inverted-index full-text
 * engine (ranked, CJK-aware). It satisfies the same `IndexDatabase` contract a
 * native SQLite FTS5 binding would, so a disk-backed implementation can replace
 * it later in `./sqlite.ts` without changing any caller.
 *
 * (See ./sqlite.ts for the planned native-FTS5 upgrade slot.)
 */
export async function createIndex(): Promise<IndexDatabase> {
  return new MemoryIndex();
}

export { MemoryIndex } from "./memory";
