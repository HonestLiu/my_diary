import yaml from "js-yaml";
import type {
  AssetRef,
  JournalEntry,
  JournalMeta,
  Mood,
  Weather,
} from "@/types/journal";

const MOODS: Mood[] = [
  "happy",
  "excited",
  "calm",
  "neutral",
  "tired",
  "sad",
  "angry",
];
const WEATHERS: Weather[] = [
  "sunny",
  "cloudy",
  "rainy",
  "snowy",
  "foggy",
  "windy",
  "unknown",
];

const FRONTMATTER_RE = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?/;
const LEADING_H1_RE = /^\s*#\s+[^\n]*\r?\n?/;

/**
 * Parse a raw Markdown file (with YAML frontmatter) into structured meta + body.
 * The leading `# Title` line (if present) is stripped — the canonical title
 * lives in frontmatter; the H1 is only written for human readability.
 */
export function parseEntryFile(raw: string): {
  meta: JournalMeta;
  body: string;
} {
  let metaObj: Record<string, unknown> = {};
  let body = raw;

  const fm = FRONTMATTER_RE.exec(raw);
  if (fm && fm[1]) {
    try {
      metaObj = (yaml.load(fm[1]) as Record<string, unknown>) ?? {};
    } catch {
      metaObj = {};
    }
    body = raw.slice(fm[0].length);
  }

  body = body.replace(LEADING_H1_RE, "");
  return { meta: normalizeMeta(metaObj), body };
}

/**
 * Serialize a journal entry back to the on-disk Markdown representation.
 * Frontmatter carries metadata; the body begins with `# <title>` for readability.
 * Local file is the source of truth — this output is fully human-readable.
 */
export function serializeEntryFile(entry: JournalEntry): string {
  const fm = buildFrontmatter(entry);
  const yamlStr = yaml.dump(fm, { lineWidth: -1, noRefs: true }).trimEnd();
  const body = (entry.body ?? "").trim();
  return `---\n${yamlStr}\n---\n\n# ${entry.title}\n\n${body}\n`;
}

/**
 * Rewrite vault-root-relative asset references in an entry's BODY — Markdown
 * images `![..](assets/..)` and attachment HTML `data-src="assets/.."` — while
 * leaving the YAML frontmatter untouched.
 *
 * `prefix` is prepended to each reference. The .zip export passes "../../" (an
 * entry file lives two folders under the archive root), so every image still
 * resolves when the archive is unzipped and read by any Markdown editor.
 * Frontmatter `assets:` paths deliberately stay vault-root-relative, which is
 * what `normalizeAssetRefsToRoot` expects on re-import — the round-trip is
 * lossless in both directions.
 */
export function rebaseBodyAssetRefs(serializedFile: string, prefix: string): string {
  const i = serializedFile.indexOf("\n---\n");
  if (i < 0) return serializedFile;
  const header = serializedFile.slice(0, i + 5); // through the closing `---\n`
  const body = serializedFile.slice(i + 5);
  const rebase = (p: string) => (p.startsWith("assets/") ? prefix + p : p);
  return (
    header +
    body
      .replace(/\[([^\]]*)\]\(([^)\s]+)\)/g, (_m, alt: string, p: string) =>
        `[${alt}](${rebase(p)})`,
      )
      .replace(/((?:data-)?src=")([^"]+)/g, (_m, pre: string, p: string) =>
        pre + rebase(p),
      )
  );
}

/**
 * Inverse of `rebaseBodyAssetRefs` for the import path: strip leading "../"
 * from vault-rooted asset references so a file exported as a .zip (whose body
 * points at `../../assets/...`) resolves correctly once imported back into a
 * vault, where references are root-relative. Non-asset relative links are left
 * untouched.
 */
export function normalizeAssetRefsToRoot(md: string): string {
  const rebase = (p: string) => {
    let r = p;
    while (r.startsWith("../")) r = r.slice(3);
    return r.startsWith("assets/") ? r : p;
  };
  return md
    .replace(/\[([^\]]*)\]\(([^)\s]+)\)/g, (_m, alt: string, p: string) =>
      `[${alt}](${rebase(p)})`,
    )
    .replace(/((?:data-)?src=")([^"]+)/g, (_m, pre: string, p: string) =>
      pre + rebase(p),
    );
}

function normalizeMeta(obj: Record<string, unknown>): JournalMeta {
  const id = typeof obj.id === "string" && obj.id ? obj.id : crypto.randomUUID();
  const date = normalizeDateKey(obj.date);
  const title = typeof obj.title === "string" ? obj.title : "未命名";
  const mood = MOODS.includes(obj.mood as Mood) ? (obj.mood as Mood) : "neutral";
  const weather = WEATHERS.includes(obj.weather as Weather)
    ? (obj.weather as Weather)
    : "unknown";
  const location = typeof obj.location === "string" ? obj.location : undefined;
  const tags = Array.isArray(obj.tags)
    ? obj.tags.filter((t): t is string => typeof t === "string")
    : [];
  const assets = Array.isArray(obj.assets)
    ? (obj.assets as unknown[]).filter(isAssetRef)
    : [];
  const nowIso = new Date().toISOString();
  const created_at = normalizeIso(obj.created_at, nowIso);
  const updated_at = normalizeIso(obj.updated_at, nowIso);

  return {
    id,
    date,
    title,
    mood,
    weather,
    location,
    tags,
    assets,
    created_at,
    updated_at,
  };
}

/**
 * YAML auto-converts an unquoted `date: 2024-12-31` into a JS Date. Accept
 * both the string and the Date form so imported Markdown (and our own files,
 * if ever dumped unquoted) always resolve to a local YYYY-MM-DD key.
 */
function normalizeDateKey(v: unknown): string {
  if (v instanceof Date && !Number.isNaN(v.getTime())) return formatYmd(v);
  if (typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v)) return v;
  return formatKeyFallback();
}

function normalizeIso(v: unknown, fallback: string): string {
  if (v instanceof Date && !Number.isNaN(v.getTime())) return v.toISOString();
  if (typeof v === "string" && v.length > 0) return v;
  return fallback;
}

function formatYmd(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(
    d.getDate(),
  ).padStart(2, "0")}`;
}

function isAssetRef(v: unknown): v is AssetRef {
  if (typeof v !== "object" || v === null) return false;
  const o = v as Record<string, unknown>;
  return (
    typeof o.path === "string" &&
    (o.kind === "image" ||
      o.kind === "audio" ||
      o.kind === "video" ||
      o.kind === "attachment")
  );
}

function buildFrontmatter(entry: JournalEntry): Record<string, unknown> {
  return {
    id: entry.id,
    date: entry.date,
    title: entry.title,
    mood: entry.mood,
    weather: entry.weather,
    location: entry.location ?? "",
    tags: entry.tags ?? [],
    assets: entry.assets ?? [],
    created_at: entry.created_at,
    updated_at: entry.updated_at,
  };
}

function formatKeyFallback(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(
    d.getDate(),
  ).padStart(2, "0")}`;
}
