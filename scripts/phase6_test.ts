import {
  archiveCurrent,
  listVersions,
  nextVersionNumber,
  readVersion,
} from "../src/lib/version";
import { serializeEntryFile, parseEntryFile } from "../src/lib/markdown";
import { JournalRepository } from "@/lib/journal";
import { MemoryIndex } from "@/lib/db/memory";
import type { StorageAdapter } from "../src/lib/storage/types";
import type { JournalEntry } from "../src/types/journal";

let failures = 0;
function assert(cond: boolean, msg: string) {
  if (cond) console.log("  ✓ " + msg);
  else {
    console.error("  ✗ " + msg);
    failures++;
  }
}

/** Minimal in-memory StorageAdapter fake for testing version logic. */
class MemStorage implements StorageAdapter {
  readonly kind = "browser" as const;
  files = new Map<string, { text?: string; bytes?: Uint8Array }>();
  async init() {}
  async readText(p: string) {
    const f = this.files.get(p);
    if (!f) throw new Error("missing " + p);
    if (f.text !== undefined) return f.text;
    if (f.bytes) return new TextDecoder().decode(f.bytes);
    throw new Error("missing " + p);
  }
  async writeText(p: string, c: string) {
    this.files.set(p, { text: c });
  }
  async readBytes(p: string) {
    const f = this.files.get(p);
    if (f?.bytes) return f.bytes;
    if (f?.text !== undefined) return new TextEncoder().encode(f.text);
    throw new Error("missing bytes " + p);
  }
  async writeBytes(p: string, d: Uint8Array) {
    this.files.set(p, { bytes: d });
  }
  async exists(p: string) {
    return this.files.has(p);
  }
  async delete(p: string) {
    this.files.delete(p);
  }
  async list(prefix: string) {
    return [...this.files.keys()].filter((k) => k.startsWith(prefix)).sort();
  }
  async resolveUrl() {
    return "";
  }
}

function makeEntry(date: string, title: string, body: string): JournalEntry {
  const now = new Date().toISOString();
  return {
    id: "id-" + date,
    date,
    title,
    mood: "neutral",
    weather: "unknown",
    location: undefined,
    tags: ["t"],
    assets: [],
    body,
    created_at: now,
    updated_at: now,
  };
}

async function main() {
  console.log("== Phase 6: version history ==");

  // ---- 0. markdown round-trip sanity ----
  const e0 = makeEntry("2026-08-11", "Day one", "Hello **world**\n\n- a\n- b");
  const round = parseEntryFile(serializeEntryFile(e0));
  assert(round.meta.date === "2026-08-11", "frontmatter date 往返一致");
  assert(round.meta.title === "Day one", "frontmatter title 往返一致");
  assert(round.body.includes("Hello"), "正文往返一致");

  const store = new MemStorage();
  const date = "2026-08-11";

  // ---- 1. archiveCurrent + nextVersionNumber ----
  console.log("== 1. archive + numbering ==");
  const v1 = await archiveCurrent(store, date, serializeEntryFile(makeEntry(date, "v1", "first")));
  const v2 = await archiveCurrent(store, date, serializeEntryFile(makeEntry(date, "v2", "second")));
  assert(v1 === 1, "第一版编号为 1");
  assert(v2 === 2, "第二版编号为 2");
  assert(store.files.has("versions/2026-08-11/v1.md"), "v1.md 已写入");
  assert(store.files.has("versions/2026-08-11/v2.md"), "v2.md 已写入");
  assert((await nextVersionNumber(store, date)) === 3, "下一版编号为 3");

  // ---- 2. listVersions newest-first with preview ----
  console.log("== 2. listVersions ==");
  const versions = await listVersions(store, date);
  assert(versions.length === 2, "列出 2 个版本");
  assert(versions[0].version === 2, "最新版本排在最前");
  assert(versions[0].title === "v2", "版本标题正确");
  assert(versions[0].preview.includes("second"), "版本预览包含正文片段");

  // ---- 3. readVersion round-trip ----
  console.log("== 3. readVersion ==");
  const read = await readVersion(store, date, 1);
  assert(read.title === "v1" && read.body.includes("first"), "readVersion 还原 v1 内容");

  // ---- 4. restoreVersion (now a JournalRepository method, keyed by id) ----
  console.log("== 4. restoreVersion ==");
  const store2 = new MemStorage();
  const repo = new JournalRepository(store2, new MemoryIndex());
  await repo.init("vault");
  const target = makeEntry("2026-08-11", "v1", "first");
  await repo.saveEntry(target);
  await repo.saveEntry({ ...target, title: "v2", body: "second" }); // 首次保存后再次保存会归档 v1
  const vers = await repo.listVersions({ id: target.id, date: target.date });
  assert(vers.length === 1, "归档出 1 个历史版本");
  const restored = await repo.restoreVersion({ id: target.id, date: target.date }, 1);
  assert(restored.title === "v1", "restore 返回 v1 条目");
  const currentRaw =
    store2.files.get("entries/2026/08/2026-08-11-id202608.md")?.text ?? "";
  const current = parseEntryFile(currentRaw);
  assert(
    current.meta.title === "v1" && current.body.includes("first"),
    "恢复后当前条目为 v1",
  );

  // ---- 5. restore preserves assets & tags ----
  const rich = makeEntry(date, "rich", "has assets");
  rich.assets = [{ kind: "image", path: "assets/images/x.webp", name: "x.webp", size: 10 }];
  rich.tags = ["keep", "me"];
  store.files.set("versions/2026-08-11/v9.md", { text: serializeEntryFile(rich) });
  const r2 = await readVersion(store, date, 9);
  assert(r2.assets.length === 1 && r2.tags.length === 2, "readVersion 保留 assets 与 tags");

  console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
}

void main();
