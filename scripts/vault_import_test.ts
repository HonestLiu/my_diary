/**
 * Vault isolation + Markdown import test (runs in Node).
 *
 * Proves two things the new code changed:
 *   1. Switching vaults rebuilds the index from the NEW disk state — the
 *      previous vault's entries must NOT leak into search/list.
 *   2. importMarkdownFiles parses frontmatter+body and saves into the active
 *      vault, honouring the skip/overwrite conflict policy (overwrite reuses
 *      the existing id so the index stays 1:1 with the on-disk file).
 *
 *   npx esbuild scripts/vault_import_test.ts --bundle --platform=node --format=esm \
 *        --tsconfig=tsconfig.json --outfile=scripts/.vault_test.mjs && node scripts/.vault_test.mjs
 */
import { JournalRepository } from "@/lib/journal";
import { MemoryIndex } from "@/lib/db/memory";
import type { StorageAdapter } from "@/lib/storage/types";
import { importMarkdownFiles } from "@/lib/import";

class MemStorage implements StorageAdapter {
  readonly kind = "browser" as const;
  /** Each vault root maps to its own isolated file map (simulates Tauri dirs / browser DBs). */
  private vaults = new Map<string, Map<string, string | Uint8Array>>();
  private current = "vault";
  async init(root: string): Promise<void> {
    this.current = root;
    if (!this.vaults.has(root)) this.vaults.set(root, new Map());
  }
  private active(): Map<string, string | Uint8Array> {
    let m = this.vaults.get(this.current);
    if (!m) {
      m = new Map();
      this.vaults.set(this.current, m);
    }
    return m;
  }
  async readText(path: string): Promise<string> {
    const f = this.active().get(path);
    if (typeof f === "string") return f;
    if (f) return new TextDecoder().decode(f);
    throw new Error(`not found: ${path}`);
  }
  async writeText(path: string, content: string): Promise<void> {
    this.active().set(path, content);
  }
  async readBytes(path: string): Promise<Uint8Array> {
    const f = this.active().get(path);
    if (f instanceof Uint8Array) return f;
    if (typeof f === "string") return new TextEncoder().encode(f);
    throw new Error(`not found: ${path}`);
  }
  async writeBytes(path: string, data: Uint8Array): Promise<void> {
    this.active().set(path, data);
  }
  async exists(path: string): Promise<boolean> {
    return this.active().has(path);
  }
  async delete(path: string): Promise<void> {
    this.active().delete(path);
  }
  async list(prefix: string): Promise<string[]> {
    return [...this.active().keys()].filter((p) => p.startsWith(prefix)).sort();
  }
  async resolveUrl(): Promise<string> {
    return "";
  }
}

/** Minimal stand-in for the browser File API used by importMarkdownFiles. */
function fakeFile(name: string, content: string): File {
  return {
    name,
    text: async () => content,
  } as unknown as File;
}

let failures = 0;
function ok(cond: boolean, label: string) {
  if (cond) console.log(`  ✓ ${label}`);
  else {
    failures++;
    console.log(`  ✗ ${label}`);
  }
}

async function main() {
  const repo = new JournalRepository(new MemStorage(), new MemoryIndex());
  await repo.init("vault-1");

  const mk = (date: string, title: string, body: string) => ({
    id: `id-${date}`,
    date,
    title,
    mood: "neutral" as const,
    weather: "unknown" as const,
    tags: [] as string[],
    assets: [] as never[],
    body,
    created_at: "2026-08-12T00:00:00.000Z",
    updated_at: "2026-08-12T00:00:00.000Z",
  });

  await repo.saveEntry(mk("2026-08-10", "东京旅行", "去了东京。"));
  await repo.saveEntry(mk("2026-08-11", "工作笔记", "写报告。"));

  console.log("[1] vault-1 有 2 篇且可搜到");
  ok((await repo.listEntries()).length === 2, "vault-1 列出 2 篇");
  ok((await repo.search("东京")).length === 1, "vault-1 搜「东京」命中 1 篇");

  console.log("[2] 切换到空 vault-2 后索引不应泄露旧数据");
  await repo.init("vault-2");
  ok((await repo.listEntries()).length === 0, "vault-2 列出 0 篇");
  ok((await repo.search("东京")).length === 0, "vault-2 搜「东京」命中 0 篇(无泄露)");

  console.log("[3] 切回 vault-1 数据仍在");
  await repo.init("vault-1");
  ok((await repo.listEntries()).length === 2, "切回 vault-1 仍有 2 篇");

  console.log("[4] 导入 Markdown（新日期）");
  const res1 = await importMarkdownFiles(
    repo,
    [
      fakeFile(
        "2024-12-31.md",
        "---\nid: x1\ndate: 2024-12-31\ntitle: 跨年\nmood: happy\n---\n\n# 跨年\n\n新年快乐。",
      ),
    ],
    "skip",
  );
  ok(res1.imported === 1 && res1.skipped === 0, `导入 1 篇新日记 (imported=${res1.imported})`);
  ok((await repo.listEntries()).length === 3, "导入后共 3 篇");
  ok((await repo.search("跨年")).length === 1, "导入内容可被搜索到");

  console.log("[5] 冲突策略 — 跳过");
  const res2 = await importMarkdownFiles(
    repo,
    [
      fakeFile(
        "2024-12-31.md",
        "---\nid: x1\ndate: 2024-12-31\ntitle: 跨年(重复)\n---\n\n# 跨年\n\n被跳过。",
      ),
    ],
    "skip",
  );
  ok(res2.skipped === 1 && res2.imported === 0, `跳过重复 1 篇 (skipped=${res2.skipped})`);
  const dup = await repo.getEntry("x1");
  ok(dup?.title === "跨年", "跳过策略保留原内容(未被覆盖)");

  console.log("[6] 冲突策略 — 覆盖(复用原 id，索引不重复)");
  const res3 = await importMarkdownFiles(
    repo,
    [
      fakeFile(
        "2024-12-31.md",
        "---\nid: x1\ndate: 2024-12-31\ntitle: 跨年(覆盖)\n---\n\n# 跨年\n\n被覆盖。",
      ),
    ],
    "overwrite",
  );
  ok(res3.imported === 1, `覆盖导入 1 篇 (imported=${res3.imported})`);
  ok((await repo.listEntries()).length === 3, "覆盖后总数仍为 3(未新增重复文件)");
  const ov = await repo.search("跨年");
  ok(ov.length === 1, "搜索「跨年」仍只命中 1 条(索引未重复)");
  ok((await repo.getEntry("x1"))?.title === "跨年(覆盖)", "覆盖后内容已更新");

  console.log("");
  if (failures === 0) {
    console.log("ALL PASS ✓ 多 Vault 隔离 + Markdown 导入 端到端可用");
    process.exit(0);
  } else {
    console.log(`${failures} 项失败 ✗`);
    process.exit(1);
  }
}

main().catch((e) => {
  console.error("test crashed:", e);
  process.exit(1);
});
