import type { JournalEntry } from "@/types/journal";
import { serializeEntryFile } from "@/lib/markdown";
import { entryFilePath } from "@/lib/vault";
import { formatDateKey, formatHumanDate } from "@/lib/utils";

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** Minimal Markdown -> HTML for readable exports (headings, lists, bold, links, code). */
function mdToHtml(md: string): string {
  const lines = md.replace(/\r\n/g, "\n").split("\n");
  const out: string[] = [];
  let inList = false;
  const inline = (t: string) =>
    escapeHtml(t)
      .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
      .replace(/\*(.+?)\*/g, "<em>$1</em>")
      .replace(/`(.+?)`/g, "<code>$1</code>")
      .replace(/\[(.+?)\]\((.+?)\)/g, '<a href="$2">$1</a>');
  for (const line of lines) {
    const h = line.match(/^(#{1,6})\s+(.*)$/);
    const li = line.match(/^\s*[-*]\s+(.*)$/);
    if (h) {
      if (inList) { out.push("</ul>"); inList = false; }
      const lvl = h[1]!.length;
      out.push(`<h${lvl}>${inline(h[2]!)}</h${lvl}>`);
    } else if (li) {
      if (!inList) { out.push("<ul>"); inList = true; }
      out.push(`<li>${inline(li[1]!)}</li>`);
    } else if (line.trim() === "") {
      if (inList) { out.push("</ul>"); inList = false; }
    } else {
      if (inList) { out.push("</ul>"); inList = false; }
      out.push(`<p>${inline(line)}</p>`);
    }
  }
  if (inList) out.push("</ul>");
  return out.join("\n");
}

export function buildHtml(entries: JournalEntry[]): string {
  const sorted = [...entries].sort((a, b) => (a.date < b.date ? 1 : -1));
  const years: Record<string, JournalEntry[]> = {};
  for (const e of sorted) {
    const y = e.date.slice(0, 4);
    const bucket = (years[y] ??= []);
    bucket.push(e);
  }
  const toc = Object.keys(years).sort().reverse().map((y) => {
    const items = (years[y] ?? [])
      .map(
        (e) =>
          `<li><a href="#${e.date}">${escapeHtml(e.title || "(无标题)")} · ${e.date}</a></li>`,
      )
      .join("");
    return `<section><h2>${y}</h2><ul>${items}</ul></section>`;
  }).join("");

  const body = sorted
    .map((e) => {
      const tags = e.tags.length
        ? `<div class="tags">${e.tags
            .map((t) => `<span>#${escapeHtml(t)}</span>`)
            .join("")}</div>`
        : "";
      return `<article id="${e.date}">
  <h1>${escapeHtml(e.title || "(无标题)")}</h1>
  <div class="meta">${formatHumanDate(new Date(e.date + "T00:00:00"))}${tags}</div>
  <div class="content">${mdToHtml(e.body)}</div>
</article>`;
    })
    .join("\n");

  return `<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MyDiary 导出</title>
<style>
  :root { color-scheme: light dark; }
  body { font-family: -apple-system, "PingFang SC", "Microsoft YaHei", system-ui, sans-serif; max-width: 760px; margin: 0 auto; padding: 32px 20px 80px; line-height: 1.7; color: #1a1a1a; background: #fff; }
  @media (prefers-color-scheme: dark) { body { color: #e8e8e8; background: #16181d; } a { color: #f0b429; } }
  h1 { font-size: 1.6rem; } h2 { font-size: 1.3rem; margin-top: 2rem; } h3,h4,h5,h6 { margin: 1rem 0 .4rem; }
  .meta { color: #888; font-size: .85rem; margin: .2rem 0 1rem; }
  .tags span { display: inline-block; background: #f0f0f0; border-radius: 999px; padding: 1px 8px; margin-right: 6px; font-size: .75rem; color: #666; }
  @media (prefers-color-scheme: dark) { .tags span { background: #2a2d34; color: #bbb; } }
  code { background: #f4f4f4; padding: 1px 5px; border-radius: 4px; font-size: .9em; }
  @media (prefers-color-scheme: dark) { code { background: #2a2d34; } }
  a { color: #c8841b; text-decoration: none; }
  article { border-top: 1px solid #eee; padding-top: 1.5rem; margin-top: 1.5rem; }
  nav.toc { background: #fafafa; border-radius: 12px; padding: 16px 20px; margin-bottom: 2rem; }
  nav.toc ul { margin: .3rem 0; padding-left: 1.1rem; }
  @media (prefers-color-scheme: dark) { nav.toc { background: #1d2026; } }
</style></head>
<body>
<h1>MyDiary 日记导出</h1>
<p>共 ${entries.length} 篇 · 生成于 ${formatHumanDate(new Date())}</p>
<nav class="toc"><h2>目录</h2>${toc}</nav>
${body}
</body></html>`;
}

function downloadBlob(filename: string, blob: Blob): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function exportHtml(entries: JournalEntry[]): void {
  const html = buildHtml(entries);
  downloadBlob(
    `my-diary-${formatDateKey()}.html`,
    new Blob([html], { type: "text/html;charset=utf-8" }),
  );
}

/**
 * Bundle entries + index as a .zip via fflate (optional dependency).
 * Returns false if fflate isn't installed, so callers can fall back to HTML.
 * Uses a runtime spec string + @vite-ignore so the build never fails when
 * fflate is absent.
 */
export async function exportZip(entries: JournalEntry[]): Promise<boolean> {
  try {
    const spec = "fflate";
    const mod: any = await import(/* @vite-ignore */ spec);
    const zipSync = mod.zipSync as (
      files: Record<string, Uint8Array>,
      opts?: unknown,
    ) => Uint8Array;
    const files: Record<string, Uint8Array> = {
      "index.html": new TextEncoder().encode(buildHtml(entries)),
      "README.txt": new TextEncoder().encode(
        "MyDiary 导出包\n\n每篇日记是独立 Markdown 文件，路径 entries/YYYY/MM/YYYY-MM-DD.md。\n正文以开放格式保存，可随时用任何文本编辑器打开。\n",
      ),
    };
    for (const e of entries) {
      // entryFilePath returns e.g. "entries/2026/08/2026-08-12.md"
      files[entryFilePath(e.date)] = new TextEncoder().encode(
        serializeEntryFile(e),
      );
    }
    const zipped = zipSync(files, { level: 6 });
    downloadBlob(
      `my-diary-${formatDateKey()}.zip`,
      new Blob([zipped as unknown as BlobPart], { type: "application/zip" }),
    );
    return true;
  } catch {
    return false;
  }
}
