import type { JournalRepository } from "./journal";
import { normalizeAssetRefsToRoot, parseEntryFile } from "./markdown";
import type { JournalEntry } from "@/types/journal";

/**
 * Batch import of Markdown files into the active vault.
 *
 * Every imported file is parsed with the SAME frontmatter+body logic the app
 * uses to read its own entries, so anything exported by MyDiary round-trips
 * losslessly. Files without frontmatter are also accepted: the date falls back
 * to the filename (`YYYY-MM-DD`), and the title to the first heading or filename.
 *
 * Because a day may hold any number of entries, "already there?" is decided by
 * entry identity, not by date:
 *   1. the frontmatter `id` matches an existing entry, or
 *   2. (for files that carry no id) same date AND same title.
 * Anything else is a new entry, so importing two different files dated the same
 * day keeps both.
 *
 * This is the inbound half of the "your data is never locked" promise — you can
 * pull writing in from anywhere, not just push it out.
 */
export type ImportConflictPolicy = "skip" | "overwrite";

export interface ImportResult {
  imported: number;
  skipped: number;
  errors: number;
  /** Dates that were actually written, for post-import refresh. */
  dates: string[];
}

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const FILENAME_DATE_RE = /(\d{4}-\d{2}-\d{2})/;

export async function importMarkdownFiles(
  repo: JournalRepository,
  files: File[],
  policy: ImportConflictPolicy,
): Promise<ImportResult> {
  const res: ImportResult = { imported: 0, skipped: 0, errors: 0, dates: [] };

  // Snapshot the vault once: scanning per file would be O(files × entries).
  const existing = await repo.listEntries();
  const byId = new Map<string, JournalEntry>();
  const byDateTitle = new Map<string, JournalEntry>();
  for (const e of existing) {
    byId.set(e.id, e);
    byDateTitle.set(dateTitleKey(e.date, e.title), e);
  }

  for (const file of files) {
    try {
      const text = await file.text();
      const { meta, body: rawBody } = parseEntryFile(text);
      // Exports rebase body asset refs to "../../assets/…" so images survive a
      // direct open; normalize them back to vault-root-relative on re-import so
      // in-app resolution (root-relative) keeps working.
      const body = normalizeAssetRefsToRoot(rawBody);

      // Resolve the canonical date key.
      let date = meta.date;
      if (!DATE_RE.test(date)) {
        const m = FILENAME_DATE_RE.exec(file.name);
        date = m?.[1] ?? fallbackToday();
      }

      // Title fallback: first heading in body, else the filename (sans ext).
      let title = meta.title;
      if (!title || title === "未命名") {
        const h = /^#\s+(.+)$/m.exec(body);
        title = h?.[1]?.trim() || file.name.replace(/\.[^.]+$/, "") || "未命名";
      }

      const entry: JournalEntry = { ...meta, date, title, body };

      // A file with no `id` gets a random one from the parser, which cannot
      // collide — so an id hit always means "the same entry, seen before".
      const prior =
        byId.get(entry.id) ?? byDateTitle.get(dateTitleKey(date, title));

      if (prior && policy === "skip") {
        res.skipped += 1;
        continue;
      }
      // Overwriting: keep the existing identity so the entry is updated in
      // place instead of being duplicated next to itself.
      if (prior) entry.id = prior.id;

      await repo.saveEntry(entry);
      byId.set(entry.id, entry);
      byDateTitle.set(dateTitleKey(date, title), entry);
      res.imported += 1;
      res.dates.push(date);
    } catch {
      res.errors += 1;
    }
  }

  return res;
}

/** Identity fallback for id-less files: one title per day is treated as one entry. */
function dateTitleKey(date: string, title: string): string {
  return `${date}\u0000${title.trim()}`;
}

function fallbackToday(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(
    d.getDate(),
  ).padStart(2, "0")}`;
}
