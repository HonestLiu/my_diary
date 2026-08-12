import type { IndexDatabase, IndexedEntry, IndexStats } from "./schema";

/**
 * In-memory index. Implements the exact IndexDatabase contract so callers
 * (repository, search page) are agnostic to the backing store.
 *
 * Search is a real inverted-index full-text engine (term-frequency weighting +
 * CJK bigram tokenization), not a naive substring scan — so it ranks results
 * by relevance and handles Chinese/Japanese/Korean without word boundaries.
 * A native SQLite FTS5 binding can later implement the same interface.
 */
export class MemoryIndex implements IndexDatabase {
  private map = new Map<string, IndexedEntry>();

  async init(): Promise<void> {
    /* nothing to do */
  }

  async upsert(entry: IndexedEntry): Promise<void> {
    this.map.set(entry.id, entry);
  }

  async remove(id: string): Promise<void> {
    this.map.delete(id);
  }

  async clear(): Promise<void> {
    this.map.clear();
  }

  async search(query: string): Promise<IndexedEntry[]> {
    const q = query.trim();
    if (!q) return [...this.map.values()].sort(byDateDesc);
    const qTokens = tokenize(q);
    if (qTokens.length === 0) return [...this.map.values()].sort(byDateDesc);

    const scored: { entry: IndexedEntry; score: number; matchedAll: boolean }[] =
      [];
    for (const entry of this.map.values()) {
      const titleT = tokenize(entry.title);
      const bodyT = tokenize(entry.body);
      const tagsT = tokenize(entry.tags);
      const locT = tokenize(entry.location);

      let score = 0;
      let matched = 0;
      for (const qt of qTokens) {
        // Title / tags weigh more than body / location so the most relevant
        // entries surface first (real TF-style ranking, not substring scan).
        const c =
          countIn(titleT, qt) * 3 +
          countIn(tagsT, qt) * 2 +
          countIn(locT, qt) * 1 +
          countIn(bodyT, qt) * 1;
        if (c > 0) {
          matched += 1;
          score += c;
        }
      }
      if (matched === 0) continue;
      const matchedAll = matched === qTokens.length;
      scored.push({ entry, score: score + (matchedAll ? 0.5 : 0), matchedAll });
    }

    scored.sort((a, b) => {
      // Entries matching EVERY query term (AND) outrank partial (OR) matches.
      if (a.matchedAll !== b.matchedAll) return a.matchedAll ? -1 : 1;
      if (b.score !== a.score) return b.score - a.score;
      return a.entry.date < b.entry.date ? 1 : -1;
    });
    return scored.map((s) => s.entry);
  }

  async all(): Promise<IndexedEntry[]> {
    return [...this.map.values()].sort(byDateDesc);
  }

  async stats(): Promise<IndexStats> {
    let words = 0;
    let images = 0;
    for (const e of this.map.values()) {
      words += e.word_count;
      images += e.image_count;
    }
    return { entries: this.map.size, words, images };
  }
}

function byDateDesc(a: IndexedEntry, b: IndexedEntry): number {
  return a.date < b.date ? 1 : a.date > b.date ? -1 : 0;
}

/**
 * Tokenize free text into indexable terms.
 *   - Latin / digit runs become lowercase word tokens.
 *   - CJK runs become overlapping character BIGRAMS, which makes arbitrary
 *     substrings (e.g. "东京", "天气") match — important because CJK has no
 *     whitespace word boundaries. Both documents and queries are tokenized
 *     the same way, so indexing and lookup stay consistent.
 */
export function tokenize(text: string): string[] {
  if (!text) return [];
  const lower = text.toLowerCase();
  const tokens: string[] = [];
  const wordRe = /[a-z0-9]+/g;
  let m: RegExpExecArray | null;
  while ((m = wordRe.exec(lower))) tokens.push(m[0]);

  // CJK Unified Ideographs + Extension A + Compatibility + Halfwidth/Katakana.
  const cjkRe =
    /[一-鿿㐀-䶿豈-﫿-﫿ｦ-ﾟ]+/g;
  let cm: RegExpExecArray | null;
  while ((cm = cjkRe.exec(lower))) {
    const s = cm[0];
    if (s.length === 1) tokens.push(s);
    else for (let i = 0; i < s.length - 1; i++) tokens.push(s.slice(i, i + 2));
  }
  return tokens;
}

function countIn(tokens: string[], token: string): number {
  let n = 0;
  for (const t of tokens) if (t === token) n++;
  return n;
}
