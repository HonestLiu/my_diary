/**
 * End-to-end smoke test for the journal data layer (runs in Node).
 *
 * Uses the REAL JournalRepository + MemoryIndex (the upgraded full-text
 * engine) against an in-memory StorageAdapter, proving the core loop —
 * save → list → search (ranked, CJK-aware) → version → restore — works on
 * the actual shipped code, not a mock.
 *
 * Bundle + run:
 *   npx esbuild scripts/smoke_repo.ts --bundle --platform=node --format=esm \
 *        --tsconfig=tsconfig.json --outfile=/tmp/smoke.mjs && node /tmp/smoke.mjs
 */
import { JournalRepository } from "@/lib/journal";
import { MemoryIndex } from "@/lib/db/memory";
import type { StorageAdapter } from "@/lib/storage/types";
import type { JournalEntry } from "@/types/journal";

/** Minimal in-memory StorageAdapter so the test needs no disk / IndexedDB. */
class MemStorage implements StorageAdapter {
  readonly kind = "browser" as const;
  private files = new Map<string, string | Uint8Array>();

  async init(): Promise<void> {}
  async readText(path: string): Promise<string> {
    const f = this.files.get(path);
    if (typeof f === "string") return f;
    if (f) return new TextDecoder().decode(f);
    throw new Error(`not found: ${path}`);
  }
  async writeText(path: string, content: string): Promise<void> {
    this.files.set(path, content);
  }
  async readBytes(path: string): Promise<Uint8Array> {
    const f = this.files.get(path);
    if (f instanceof Uint8Array) return f;
    if (typeof f === "string") return new TextEncoder().encode(f);
    throw new Error(`not found: ${path}`);
  }
  async writeBytes(path: string, data: Uint8Array): Promise<void> {
    this.files.set(path, data);
  }
  async exists(path: string): Promise<boolean> {
    return this.files.has(path);
  }
  async delete(path: string): Promise<void> {
    this.files.delete(path);
  }
  async list(prefix: string): Promise<string[]> {
    return [...this.files.keys()].filter((p) => p.startsWith(prefix)).sort();
  }
  async resolveUrl(): Promise<string> {
    return "";
  }
}

let failures = 0;
function ok(cond: boolean, label: string) {
  if (cond) {
    console.log(`  ✓ ${label}`);
  } else {
    failures++;
    console.log(`  ✗ ${label}`);
  }
}

async function main() {
  const repo = new JournalRepository(new MemStorage(), new MemoryIndex());
  await repo.init("vault");

  const mk = (
    date: string,
    title: string,
    body: string,
    tags: string[],
  ): JournalEntry => ({
    id: `id-${date}`,
    date,
    title,
    mood: "neutral",
    weather: "unknown",
    tags,
    assets: [],
    body,
    created_at: "2026-08-12T00:00:00.000Z",
    updated_at: "2026-08-12T00:00:00.000Z",
  });

  const e1 = mk("2026-08-10", "东京旅行", "今天去了东京，天气晴朗，吃了寿司。", ["旅行", "日本"]);
  const e2 = mk("2026-08-11", "工作笔记", "Today I finished the report about Tokyo trip planning. 这是一次旅行。", ["work"]);
  const e3 = mk("2026-08-12", "随感", "天气阴，心情平静。没有特别的计划。", ["日记"]);

  await repo.saveEntry(e1);
  await repo.saveEntry(e2);
  await repo.saveEntry(e3);

  console.log("[1] save + list");
  const all = await repo.listEntries();
  ok(all.length === 3, `列出 3 篇 (实际 ${all.length})`);
  ok(all[0].date === "2026-08-12", `按日期倒序 (首篇 ${all[0]?.date})`);

  console.log("[2] getEntry");
  const got = await repo.getEntry("id-2026-08-11");
  ok(got?.title === "工作笔记", `按日期读取 (${got?.title})`);

  console.log("[3] search — 中文子串 + 排序");
  const r1 = await repo.search("东京");
  ok(r1.some((e) => e.date === "2026-08-10"), "搜「东京」命中东京旅行");
  ok(!r1.some((e) => e.date === "2026-08-11"), "搜「东京」不误命中英文 Tokyo");

  const r2 = await repo.search("天气");
  ok(r2.length === 2, `搜「天气」命中 2 篇 (实际 ${r2.length})`);
  ok(r2[0].date === "2026-08-12", "「天气」平分时按日期倒序(e3 在前)");

  const rTravel = await repo.search("旅行");
  const iE1 = rTravel.findIndex((e) => e.date === "2026-08-10");
  const iE2 = rTravel.findIndex((e) => e.date === "2026-08-11");
  ok(iE1 >= 0 && iE2 >= 0 && iE1 < iE2, "「旅行」标题命中(e1)排在正文命中(e2)前(加权排序)");

  console.log("[4] search — 英文词大小写不敏感");
  const r3 = await repo.search("tokyo");
  ok(r3.some((e) => e.date === "2026-08-11"), "搜「tokyo」命中工作笔记(大小写不敏感)");
  const r3b = await repo.search("REPORT");
  ok(r3b.some((e) => e.date === "2026-08-11"), "搜「REPORT」大写也命中(大小写不敏感)");

  console.log("[5] version snapshot + restore");
  const before = (await repo.getEntry("id-2026-08-10"))!.body;
  await repo.saveEntry({
    ...e1,
    body: "今天去了东京，天气晴朗，吃了寿司，还看了东京塔。",
  });
  const versions = await repo.listVersions({ id: "id-2026-08-10", date: "2026-08-10" });
  ok(versions.length >= 1, `保存变更后产生版本 (${versions.length})`);
  const restored = await repo.restoreVersion({ id: "id-2026-08-10", date: "2026-08-10" }, versions[0].version);
  ok(restored.body === before, "恢复到上一版本正文");

  console.log("[6] delete");
  await repo.deleteEntry("id-2026-08-12");
  const afterDel = await repo.listEntries();
  ok(afterDel.length === 2, `删除后剩 2 篇 (实际 ${afterDel.length})`);

  console.log("");
  if (failures === 0) {
    console.log("ALL PASS ✓ 数据层（含真实全文检索）端到端可用");
    process.exit(0);
  } else {
    console.log(`${failures} 项失败 ✗`);
    process.exit(1);
  }
}

main().catch((e) => {
  console.error("smoke test crashed:", e);
  process.exit(1);
});
