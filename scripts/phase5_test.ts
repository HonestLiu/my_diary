import { SyncEngine } from "../src/lib/sync/engine";
import type { StorageAdapter } from "../src/lib/storage/types";
import type { StorageProvider, SyncManifest } from "../src/types/journal";

let failures = 0;
function assert(cond: boolean, msg: string) {
  if (cond) console.log("  ✓ " + msg);
  else {
    console.error("  ✗ " + msg);
    failures++;
  }
}

/** In-memory StorageAdapter fake. */
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

/** In-memory StorageProvider fake. */
class MemRemote implements StorageProvider {
  readonly name = "mem";
  files = new Map<string, Uint8Array>();
  async upload(p: string, d: Uint8Array | ArrayBuffer) {
    this.files.set(p, d instanceof Uint8Array ? d : new Uint8Array(d));
  }
  async download(p: string) {
    const f = this.files.get(p);
    if (!f) throw new Error("missing remote " + p);
    return f;
  }
  async delete(p: string) {
    this.files.delete(p);
  }
  async list(prefix = "") {
    return [...this.files.keys()].filter((k) => k.startsWith(prefix)).sort();
  }
  async fetchManifest() {
    const f = this.files.get("metadata/sync.json");
    if (!f) return null;
    return JSON.parse(new TextDecoder().decode(f)) as SyncManifest;
  }
  async pushManifest(m: SyncManifest) {
    this.files.set(
      "metadata/sync.json",
      new TextEncoder().encode(JSON.stringify(m)),
    );
  }
}

function enc(s: string): Uint8Array {
  return new TextEncoder().encode(s);
}

async function main() {
  // ---- Scenario 1: local-only → upload all + push manifest ----
  console.log("== Scenario 1: upload new ==");
  {
    const local = new MemStorage();
    local.files.set("entries/2026/08/2026-08-11.md", { text: "# 11\nhello" });
    local.files.set("assets/images/a.webp", { bytes: enc("IMG") });
    const remote = new MemRemote();
    const eng = new SyncEngine(local, remote, "dev1");
    const r = await eng.sync();
    assert(r.uploaded.length === 2, "上传了 2 个本地文件");
    assert(remote.files.has("entries/2026/08/2026-08-11.md"), "远端存在条目文件");
    assert(remote.files.has("assets/images/a.webp"), "远端存在图片");
    assert((await remote.fetchManifest())?.files.length === 2, "推送了清单");
    assert(local.files.has("metadata/sync.json"), "本地写入基线清单");
  }

  // ---- Scenario 2: remote-only → download ----
  console.log("== Scenario 2: download new ==");
  {
    const local = new MemStorage();
    const remote = new MemRemote();
    remote.files.set("entries/2026/08/12.md", enc("# 12\nremote only"));
    const eng = new SyncEngine(local, remote, "dev1");
    const r = await eng.sync();
    assert(r.downloaded.length === 1, "下载了 1 个远端文件");
    assert((await local.readText("entries/2026/08/12.md")).includes("remote only"), "本地收到远端内容");
  }

  // ---- Scenario 3: both changed differently → conflict (no auto-overwrite) ----
  console.log("== Scenario 3: conflict detection ==");
  {
    const local = new MemStorage();
    local.files.set("entries/2026/08/2026-08-11.md", { text: "LOCAL VERSION" });
    const remote = new MemRemote();
    remote.files.set("entries/2026/08/2026-08-11.md", enc("REMOTE VERSION"));
    const eng = new SyncEngine(local, remote, "dev1");
    const r = await eng.sync();
    assert(r.conflicts.length === 1, "检测到 1 个冲突");
    assert(
      local.files.has("conflicts/2026-08-11.local.md"),
      "生成 local 冲突副本",
    );
    assert(
      local.files.has("conflicts/2026-08-11.remote.md"),
      "生成 remote 冲突副本",
    );
    // Local remains intact (no auto-overwrite).
    assert((await local.readText("entries/2026/08/2026-08-11.md")) === "LOCAL VERSION", "本地未被覆盖");
  }

  // ---- Scenario 4: resolve conflict → use remote ----
  console.log("== Scenario 4: resolve conflict ==");
  {
    const local = new MemStorage();
    local.files.set("entries/2026/08/2026-08-11.md", { text: "LOCAL VERSION" });
    local.files.set("conflicts/2026-08-11.local.md", { text: "LOCAL VERSION" });
    local.files.set("conflicts/2026-08-11.remote.md", { text: "REMOTE VERSION" });
    const remote = new MemRemote();
    remote.files.set("entries/2026/08/2026-08-11.md", enc("REMOTE VERSION"));
    const eng = new SyncEngine(local, remote, "dev1");
    await eng.resolveConflict("entries/2026/08/2026-08-11.md", "remote");
    assert((await local.readText("entries/2026/08/2026-08-11.md")) === "REMOTE VERSION", "采用远端版本覆盖本地");
    assert(!local.files.has("conflicts/2026-08-11.local.md"), "冲突副本已清除");
  }

  console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
}

void main();
