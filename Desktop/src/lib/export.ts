import { zipSync } from "fflate";
import { save } from "@tauri-apps/plugin-dialog";
import { writeFile } from "@tauri-apps/plugin-fs";
import type { JournalEntry } from "@/types/journal";
import { rebaseBodyAssetRefs, serializeEntryFile } from "@/lib/markdown";
import { entryFilePath } from "@/lib/vault";
import { byRecency } from "@/lib/journal";
import { formatDateKey, formatHumanDate } from "@/lib/utils";
import { MOOD_MAP, WEATHER_MAP } from "@/lib/constants";
import type { StorageAdapter } from "@/lib/storage/types";
import { isTauri } from "@/lib/storage/types";
import { useAppStore } from "@/store/appStore";

export type ExportFormat = "html" | "zip";

/** Result of an export action, so the UI can show real feedback. */
export type ExportResult =
  | { ok: true; format: ExportFormat; path?: string; name: string }
  | { ok: false; format: ExportFormat; cancelled: boolean; message?: string };

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

const ATTACH_RE = /<attachment\b([^>]*)\/?>([\s\S]*?)<\/attachment>|<attachment\b([^>]*)\/?>/gi;

type AttachmentInfo = {
  src: string;
  name: string;
  kind: string;
  size: number;
};

/** Pull `<attachment …/>` cards out of a body so markdown passes them untouched. */
function extractAttachments(md: string): { prepped: string; attachments: AttachmentInfo[] } {
  const attachments: AttachmentInfo[] = [];
  const prepped = md.replace(ATTACH_RE, (_m, attrs, _inner, attrs2) => {
    const a = attrs || attrs2 || "";
    const attr = (name: string) => {
      const m = a.match(new RegExp(`${name}=["']?([^"'>\\s]*)`, "i"));
      return m ? m[1] ?? "" : "";
    };
    const src = attr("data-src");
    attachments.push({
      src,
      name: attr("data-name") || src.split("/").pop() || "文件",
      kind: attr("data-kind") || "attachment",
      size: Number(attr("data-size") || 0),
    });
    return `\u0000ATTACH${attachments.length - 1}\u0000`;
  });
  return { prepped, attachments };
}

function restoreAttachments(html: string, attachments: AttachmentInfo[]): string {
  return html.replace(/\u0000ATTACH(\d+)\u0000/g, (_m, i) => {
    const a = attachments[Number(i)];
    return a ? renderAttachment(a) : "";
  });
}

/** Notebook-card render of a video / audio / generic attachment. */
function renderAttachment(a: AttachmentInfo): string {
  const name = escapeHtml(a.name || "文件");
  const sizeNote = a.size ? ` · ${(a.size / 1024).toFixed(1)} KB` : "";
  const icon =
    a.kind === "video" ? "🎬" : a.kind === "audio" ? "🎵" : name.match(/\.pdf$/i) ? "📄" : "📎";
  const media =
    a.kind === "video"
      ? `<video src="${escapeHtml(a.src)}" controls></video>`
      : a.kind === "audio"
        ? `<audio src="${escapeHtml(a.src)}" controls></audio>`
        : `<a class="att-link" href="${escapeHtml(a.src)}" download>下载</a>`;
  return `<div class="attachment"><span class="att-icon">${icon}</span><div class="att-info"><p class="att-name">${name}</p><p class="att-meta">${escapeHtml(a.kind)}${sizeNote}</p></div>${media}</div>`;
}

/** Markdown -> HTML for readable exports: headings, lists, quotes, code, media. */
function mdToHtml(md: string): string {
  const lines = md.replace(/\r\n/g, "\n").split("\n");
  const out: string[] = [];
  const stack: { tag: "ul" | "ol"; level: number }[] = [];
  let para: string[] = [];

  const inline = (t: string) =>
    escapeHtml(t)
      .replace(/!\[([^\]]*)\]\(([^)\s]+)(?:\s+"([^"]*)")?\)/g, (_m, alt, p, title) => {
        const t = title ? ` title="${escapeHtml(title)}"` : "";
        const a = alt ? ` alt="${escapeHtml(alt)}"` : "";
        return `<img src="${p}"${a}${t} loading="lazy">`;
      })
      .replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, '<a href="$2">$1</a>')
      .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
      .replace(/~~([^~]+)~~/g, "<del>$1</del>")
      .replace(/(^|[^*_])\*([^*]+)\*(?![*])/g, "$1<em>$2</em>")
      .replace(/`([^`]+)`/g, "<code>$1</code>");

  const flushPara = () => {
    if (para.length) {
      out.push(`<p>${inline(para.join(" "))}</p>`);
      para = [];
    }
  };
  const closeTo = (level: number) => {
    while (stack.length && stack[stack.length - 1]!.level >= level) {
      out.push(`</${stack.pop()!.tag}>`);
    }
  };

  let fence = false;
  let fenceBuf: string[] = [];

  for (const raw of lines) {
    const line = raw.replace(/\s+$/, "");
    if (fence) {
      if (/^```[\w-]*\s*$/.test(line.trim())) {
        out.push(`<pre><code>${escapeHtml(fenceBuf.join("\n"))}</code></pre>`);
        fence = false;
        fenceBuf = [];
      } else {
        fenceBuf.push(line);
      }
      continue;
    }
    const fenceOpen = line.match(/^```([\w-]*)\s*$/);
    if (fenceOpen) {
      flushPara();
      closeTo(0);
      fence = true;
      fenceBuf = [];
      continue;
    }
    const trimmed = line.trim();
    if (!trimmed) {
      flushPara();
      continue;
    }
    const item = line.match(/^(\s*)([-*+]|\d+\.)\s+(.*)$/);
    if (item && !/^[-*_]{3,}$/.test(trimmed)) {
      flushPara();
      const level = Math.floor(item[1]!.length / 2);
      const tag: "ul" | "ol" = /\d/.test(item[2]!) ? "ol" : "ul";
      const top = stack[stack.length - 1];
      if (!top || top.level > level || top.tag !== tag) {
        closeTo(top ? Math.max(top.level, level) : 0);
        if (!top || top.tag !== tag) {
          out.push(`<${tag}>`);
          stack.push({ tag, level });
        }
      }
      out.push(`<li>${inline(item[3]!)}</li>`);
      continue;
    }
    const h = line.match(/^(#{1,6})\s+(.*)$/);
    if (h) {
      flushPara();
      closeTo(0);
      out.push(`<h${h[1]!.length}>${inline(h[2]!)}</h${h[1]!.length}>`);
      continue;
    }
    if (/^>/.test(trimmed)) {
      flushPara();
      closeTo(0);
      out.push(`<blockquote>${inline(trimmed.replace(/^>\s?/, ""))}</blockquote>`);
      continue;
    }
    if (/^[-*_]{3,}$/.test(trimmed)) {
      flushPara();
      closeTo(0);
      out.push("<hr>");
      continue;
    }
    para.push(trimmed);
  }
  flushPara();
  closeTo(0);
  if (fence && fenceBuf.length) {
    out.push(`<pre><code>${escapeHtml(fenceBuf.join("\n"))}</code></pre>`);
  }
  return out.join("\n");
}

function entryContent(md: string): string {
  const { prepped, attachments } = extractAttachments(md);
  return restoreAttachments(mdToHtml(prepped), attachments);
}

/** MIME guess by extension so embedded assets decode correctly. */
function mimeFromPath(path: string): string {
  const ext = path.split(".").pop()?.toLowerCase() ?? "";
  const table: Record<string, string> = {
    png: "image/png",
    jpg: "image/jpeg",
    jpeg: "image/jpeg",
    gif: "image/gif",
    webp: "image/webp",
    svg: "image/svg+xml",
    avif: "image/avif",
    mp3: "audio/mpeg",
    wav: "audio/wav",
    ogg: "audio/ogg",
    m4a: "audio/mp4",
    mp4: "video/mp4",
    webm: "video/webm",
    mov: "video/quicktime",
    pdf: "application/pdf",
    md: "text/markdown",
    txt: "text/plain",
  };
  return table[ext] ?? "application/octet-stream";
}

/** Inline a referenced asset (from the archive's assets/ folder) as a data URI. */
function bytesToDataUri(bytes: Uint8Array, mime: string): string {
  let bin = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    bin += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return `data:${mime};base64,${btoa(bin)}`;
}

/**
 * Build the self-contained "diary book" page shared by the single-file HTML and
 * the .zip's index.html.
 *
 * When `storage` is provided the browser export inlines every referenced asset
 * (images / audio / video / downloads) as data URIs, so the standalone HTML is
 * truly portable. Without storage (the .zip), references stay relative and
 * resolve against the archive's assets/ folder.
 */
export async function buildHtml(
  entries: JournalEntry[],
  storage?: StorageAdapter,
  author = "",
): Promise<string> {
  // Newest first, and stable within a day — a day may hold several entries.
  const sorted = [...entries].sort(byRecency);
  const years: Record<string, JournalEntry[]> = {};
  for (const e of sorted) {
    const y = e.date.slice(0, 4);
    const bucket = (years[y] ??= []);
    bucket.push(e);
  }

  const toc = Object.keys(years)
    .sort()
    .reverse()
    .map((y) => {
      const items = (years[y] ?? [])
        // Anchored on the entry id, not the date: ids are unique per entry, so
        // every one of a day's entries gets its own link target.
        .map(
          (e) => `<a href="#e-${e.id}"><span class="d">${e.date}</span>${escapeHtml(e.title || "(无标题)")}</a>`,
        )
        .join("");
      return `<div class="yr">${y}</div>${items}`;
    })
    .join("");

  const allTags = new Set<string>();
  let images = 0;
  for (const e of entries) {
    for (const t of e.tags) allTags.add(t);
    images += (e.assets ?? []).filter((a) => a.kind === "image").length;
  }

  const body = sorted
    .map((e) => {
      const mood = MOOD_MAP[e.mood];
      const weather = WEATHER_MAP[e.weather];
      const chips = [
        mood ? `<span class="chip">${mood.emoji} ${mood.label}</span>` : "",
        weather && weather.key !== "unknown"
          ? `<span class="chip">${weather.emoji} ${weather.label}</span>`
          : "",
      ]
        .filter(Boolean)
        .join(" ");
      const tags = e.tags.length
        ? e.tags
            .map((t) => `<span class="chip tag">#${escapeHtml(t)}</span>`)
            .join(" ")
        : "";
      return `<article class="entry" id="e-${e.id}">
  <h1>${escapeHtml(e.title || "(无标题)")}</h1>
  <div class="meta"><span class="dat">${formatHumanDate(new Date(e.date + "T00:00:00"))}</span>${chips}${tags}</div>
  <div class="content">${entryContent(e.body)}</div>
</article>`;
    })
    .join("\n");

  const from = sorted.length ? sorted[sorted.length - 1]!.date : "";
  const to = sorted.length ? sorted[0]!.date : "";
  const range = from
    ? `${formatHumanDate(new Date(from + "T00:00:00"))} — ${formatHumanDate(new Date(to + "T00:00:00"))}`
    : "";

  let html = `<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>我的日记 · MyDiary 导出</title>
<style>
  :root { color-scheme: light dark; --bg:#f6f7f9; --card:#ffffff; --ink:#101828; --muted:#667085; --line:#e6e8eb; --accent:#0284c7; --soft:#e0f2fe; }
  @media (prefers-color-scheme:dark){ :root { --bg:#0e0f12; --card:#17191e; --ink:#f2f4f7; --muted:#98a2b3; --line:#272a31; --accent:#38bdf8; --soft:#17283a; } }
  * { box-sizing: border-box; }
  html { scroll-behavior: smooth; }
  body { margin:0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Helvetica Neue", Arial, sans-serif; background:var(--bg); color:var(--ink); line-height:1.8; }
  .page { max-width: 1080px; margin: 0 auto; padding: 30px 20px 90px; }
  .cover { background: linear-gradient(135deg,#0369a1,#0284c7 55%,#38bdf8); color:#fff; border-radius:22px; padding:52px 26px 44px; text-align:center; box-shadow:0 14px 34px rgba(2,132,199,.22); margin-bottom:30px; }
  .cover h1 { margin:0; font-size:2.5rem; letter-spacing:6px; text-shadow:0 2px 8px rgba(0,0,0,.25); }
  .cover .byline { margin:10px 0 0; font-size:1.1rem; font-weight:600; opacity:.98; }
  .cover .sub { margin:14px 0 0; opacity:.95; font-size:.96rem; }
  .cover .stats { margin:20px auto 0; display:flex; justify-content:center; gap:26px; font-size:.9rem; opacity:.95; flex-wrap:wrap; }
  .lockup { display:grid; grid-template-columns: 250px 1fr; gap: 28px; align-items:start; }
  .toc { position:sticky; top:18px; background:var(--card); border:1px solid var(--line); border-radius:16px; padding:16px 14px; max-height:calc(100vh - 40px); overflow:auto; }
  .toc h3 { margin:0 0 8px; font-size:.78rem; letter-spacing:1.5px; color:var(--muted); text-transform:uppercase; }
  .toc .yr { margin:12px 0 5px; font-weight:700; color:var(--accent); }
  .toc a { display:block; text-decoration:none; color:var(--ink); padding:3px 8px; border-radius:8px; font-size:.88rem; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .toc a:hover { background:var(--soft); }
  .toc .d { color:var(--muted); font-size:.72rem; margin-right:7px; }
  .mobile-toc { display:none; margin-bottom:16px; }
  article.entry { background:var(--card); border:1px solid var(--line); border-radius:18px; padding:34px 38px 26px; margin-bottom:28px; box-shadow:0 4px 16px rgba(0,0,0,.05); }
  article.entry h1 { font-size:1.55rem; margin:0 0 6px; line-height:1.4; }
  .meta { color:var(--muted); font-size:.86rem; display:flex; flex-wrap:wrap; gap:8px; align-items:center; margin-bottom:18px; }
  .meta .dat { font-weight:600; color:var(--ink); margin-right:4px; }
  .chip { display:inline-flex; align-items:center; gap:4px; background:var(--soft); color:var(--accent); border-radius:999px; padding:2px 10px; font-size:.78rem; }
  .chip.tag { background:#f1f3f5; color:#667085; }
  @media (prefers-color-scheme:dark){ .chip.tag { background:#1f222a; color:#98a2b3; } }
  .content p { margin:.65em 0; }
  .content img { max-width:100%; height:auto; border-radius:14px; margin:16px 0; box-shadow:0 3px 12px rgba(0,0,0,.1); }
  .content h2 { font-size:1.28rem; margin:30px 0 8px; border-left:4px solid var(--accent); padding-left:10px; }
  .content h3 { font-size:1.1rem; margin:22px 0 6px; }
  .content ul, .content ol { padding-left:1.4em; }
  .content li { margin:.25em 0; }
  .content a { color:var(--accent); }
  .content blockquote { border-left:3px solid var(--accent); background:var(--soft); margin:14px 0; padding:8px 16px; border-radius:10px; }
  .content code { background:rgba(0,0,0,.07); padding:1px 7px; border-radius:6px; font-size:.88em; font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; }
  @media (prefers-color-scheme:dark){ .content code { background:rgba(255,255,255,.12); } }
  .content pre { background:#17191e; color:#f2f4f7; border-radius:12px; padding:14px 16px; overflow:auto; font-size:.85rem; }
  @media (prefers-color-scheme:dark){ .content pre { background:#0e0f12; } }
  .content pre code { background:none; padding:0; }
  .content hr { border:none; border-top:1px dashed var(--line); margin:24px 0; }
  .attachment { display:flex; align-items:center; gap:12px; background:var(--soft); border:1px solid var(--line); border-radius:12px; padding:12px 14px; margin:14px 0; }
  .att-icon { font-size:1.5rem; }
  .att-info { flex:1; min-width:0; }
  .att-name { margin:0; font-weight:600; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  .att-meta { margin:2px 0 0; font-size:.78rem; color:var(--muted); }
  .att-link { color:var(--accent); font-weight:600; text-decoration:none; white-space:nowrap; }
  .content .attachment video, .content .attachment audio { max-width:100%; border-radius:10px; }
  .to-top { position:fixed; right:22px; bottom:22px; background:var(--accent); color:#fff; border-radius:999px; padding:10px 15px; font-size:.85rem; text-decoration:none; box-shadow:0 6px 18px rgba(0,0,0,.25); z-index:9; }
  .foot { margin-top:34px; padding-top:18px; border-top:1px solid var(--line); text-align:center; color:var(--muted); font-size:.82rem; }
  @media (max-width:780px){
    .lockup { grid-template-columns:1fr; }
    .toc { display:none; }
    .mobile-toc { display:block; background:var(--card); border:1px solid var(--line); border-radius:14px; padding:12px 14px; }
    .mobile-toc summary { cursor:pointer; font-weight:700; color:var(--accent); }
    .mobile-toc a { display:block; color:var(--ink); text-decoration:none; padding:4px 0; }
    .cover h1 { font-size:1.9rem; letter-spacing:3px; }
    article.entry { padding:24px 20px 18px; }
  }
</style></head>
<body>
<div class="page">
  <header class="cover">
    <h1>我的日记</h1>
    ${author ? `<p class="byline">${escapeHtml(author)} 的日记</p>` : ""}
    <p class="sub">${range} · 共 ${entries.length} 篇 · 生成于 ${formatHumanDate(new Date())}</p>
    <div class="stats"><span>📝 ${entries.length} 篇</span><span>🏷 ${allTags.size} 个标签</span>${images ? `<span>🖼 ${images} 张图片</span>` : ""}</div>
  </header>
  <details class="mobile-toc"><summary>目录</summary>${toc}</details>
  <div class="lockup">
    <nav class="toc"><h3>目录</h3>${toc}</nav>
    <main>${body}</main>
  </div>
  <p class="foot">${author ? `${escapeHtml(author)} · ` : ""}由 MyDiary 导出 · Markdown 始终可读，数据永远属于你</p>
</div>
<a class="to-top" href="#top">↑ 回到顶部</a>
</body></html>`;

  if (storage) html = await inlineAssets(html, storage);
  return html;
}

/** Replace relative assets/ references in the built page with embedded data URIs. */
async function inlineAssets(html: string, storage: StorageAdapter): Promise<string> {
  const cache = new Map<string, string>();
  let out = html;
  for (const m of html.matchAll(/(?:src|href)="(assets\/[^"]+)"/g)) {
    const path = m[1]!;
    if (cache.has(path)) continue;
    try {
      const bytes = await storage.readBytes(path);
      cache.set(path, bytesToDataUri(bytes, mimeFromPath(path)));
    } catch {
      // A referenced asset missing from disk is left as its relative link.
    }
  }
  for (const [path, uri] of cache) {
    out = out.split(`"${path}"`).join(`"${uri}"`);
  }
  return out;
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

/**
 * Persist generated bytes in the desktop app via a native save dialog, or fall
 * back to a normal browser download in the web preview. Returns a result the
 * UI can turn into visible feedback (the biggest gap in the old export flow).
 */
async function saveExportFile(
  format: ExportFormat,
  name: string,
  data: Uint8Array,
  mime: string,
): Promise<ExportResult> {
  if (isTauri()) {
    try {
      const path = await save({
        title: format === "html" ? "导出为单个 HTML" : "导出为 Markdown 压缩包",
        defaultPath: name,
        filters: [
          {
            name: format === "html" ? "HTML 文件" : "ZIP 压缩包",
            extensions: [format],
          },
        ],
      });
      if (!path) return { ok: false, format, cancelled: true };
      await writeFile(path, data);
      return { ok: true, format, path, name };
    } catch (err) {
      return {
        ok: false,
        format,
        cancelled: false,
        message: err instanceof Error ? err.message : String(err),
      };
    }
  }
  downloadBlob(name, new Blob([data as unknown as BlobPart], { type: mime }));
  return { ok: true, format, name };
}

export async function exportHtml(
  entries: JournalEntry[],
  storage?: StorageAdapter,
  onProgress?: (percent: number) => void,
): Promise<ExportResult> {
  onProgress?.(10);
  const html = await buildHtml(
    entries,
    storage,
    useAppStore.getState().settings.displayName,
  );
  onProgress?.(60);
  const res = await saveExportFile(
    "html",
    `my-diary-${formatDateKey()}.html`,
    new TextEncoder().encode(html),
    "text/html;charset=utf-8",
  );
  onProgress?.(100);
  return res;
}

/**
 * Bundle entries (+ their referenced assets) as a single self-contained .zip.
 *
 * Layout mirrors the vault on disk, so the archive can be unzipped anywhere and
 * read with any Markdown editor:
 *   entries/YYYY/MM/YYYY-MM-DD.md      — one file per entry (open format)
 *   assets/<kind>/<file>               — every image / audio / video / attachment
 *                                        the entries reference, at the same
 *                                        relative path the Markdown points to
 *   index.html / README.txt            — human-readable extras
 *
 * `storage` is optional: pass the active StorageAdapter to bundle asset bytes.
 */
export async function exportZip(
  entries: JournalEntry[],
  storage?: StorageAdapter,
  onProgress?: (percent: number) => void,
): Promise<ExportResult> {
  onProgress?.(5);
  const indexHtml = await buildHtml(
    entries,
    undefined,
    useAppStore.getState().settings.displayName,
  );
  const files: Record<string, Uint8Array> = {
    "index.html": new TextEncoder().encode(indexHtml),
    "README.txt": new TextEncoder().encode(
      [
        "MyDiary 导出包",
        "",
        "每篇日记是独立 Markdown 文件，路径 entries/YYYY/MM/YYYY-MM-DD.md。",
        "正文以开放格式保存，可随时用任何文本编辑器打开。",
        "",
        "图片 / 音频 / 视频 / 附件存放在 assets/ 下，Markdown 中以相对路径引用。",
        "整个压缩包是自包含的，解压后即可完整离线阅读。",
        "",
      ].join("\n"),
    ),
  };
  const total = entries.length + (entries.flatMap((e) => e.assets ?? []).length ?? 0);
  let advanced = 0;
  const tick = (n: number) => {
    advanced += n;
    onProgress?.(Math.min(100, Math.round((advanced / Math.max(total, 1)) * 100)));
  };
  for (const e of entries) {
    // entryFilePath returns e.g. "entries/2026/08/2026-08-12-9f1c2e0a.md" — the
    // id suffix keeps several entries of one day apart in the archive. Body
    // asset references are rebased from vault-root-relative (assets/…) to
    // relative to the file (../../assets/…) so they resolve when the .md is
    // opened directly from the unzipped archive; frontmatter stays
    // root-relative for re-import.
    const p = entryFilePath(e);
    files[p] = new TextEncoder().encode(
      rebaseBodyAssetRefs(serializeEntryFile(e), relativePrefix(p)),
    );
    tick(1);
  }
  await bundleReferencedAssets(storage, entries, files, tick);

  try {
    const zipped = zipSync(files, { level: 6 });
    onProgress?.(90);
    return await saveExportFile(
      "zip",
      `my-diary-${formatDateKey()}.zip`,
      zipped,
      "application/zip",
    );
  } catch (err) {
    return {
      ok: false,
      format: "zip",
      cancelled: false,
      message: err instanceof Error ? err.message : String(err),
    };
  }
}

/** Directory depth of a vault-relative file path → "../" prefix to the root. */
function relativePrefix(filePath: string): string {
  const depth = filePath.split("/").length - 1;
  return "../".repeat(depth);
}

/** Add every asset referenced by the exported entries at its vault-relative path. */
async function bundleReferencedAssets(
  storage: StorageAdapter | undefined,
  entries: JournalEntry[],
  files: Record<string, Uint8Array>,
  onAsset?: (count: number) => void,
): Promise<void> {
  if (!storage) return;
  const seen = new Set<string>();
  for (const e of entries) {
    for (const a of e.assets ?? []) {
      if (!a.path || seen.has(a.path)) continue;
      seen.add(a.path);
      try {
        files[a.path] = await storage.readBytes(a.path);
      } catch {
        // A referenced asset missing from disk shouldn't sink the whole export.
      }
      onAsset?.(1);
    }
  }
}
