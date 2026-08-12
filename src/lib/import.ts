import type { JournalRepository } from "./journal";
import { parseEntryFile } from "./markdown";
import type { JournalEntry } from "@/types/journal";

/**
 * Batch import of Markdown files into the active vault.
 *
 * Every imported file is parsed with the SAME frontmatter+body logic the app
 * uses to read its own entries, so anything exported by MyDiary (or any tool
 * that writes `entries/YYYY/MM/YYYY-MM-DD.md` with YAML frontmatter) round-trips
 * losslessly. Files without frontmatter are also accepted: the date falls back
 * to the filename (`YYYY-MM-DD`), and the title to the first heading or filename.
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

  for (const file of files) {
    try {
      const text = await file.text();
      const { meta, body } = parseEntryFile(text);

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

      const existing = await repo.getEntry(date);
      if (existing && policy === "skip") {
        res.skipped += 1;
        continue;
      }
      // Overwrite (or new): reuse the existing id so the index stays 1:1 with
      // the on-disk file (the file is keyed by date, the index by id).
      if (existing) entry.id = existing.id;

      await repo.saveEntry(entry);
      res.imported += 1;
      res.dates.push(date);
    } catch {
      res.errors += 1;
    }
  }

  return res;
}

function fallbackToday(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(
    d.getDate(),
  ).padStart(2, "0")}`;
}
