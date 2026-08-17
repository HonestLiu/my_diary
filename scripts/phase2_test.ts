import { parseEntryFile, serializeEntryFile } from "../src/lib/markdown";
import {
  entryFilePath,
  assetPath,
  dateKeyFromEntryPath,
  conflictFilePath,
  versionFilePath,
  assetDir,
} from "../src/lib/vault";

let failures = 0;
function assert(cond: boolean, msg: string) {
  if (cond) {
    console.log("  ✓ " + msg);
  } else {
    console.error("  ✗ " + msg);
    failures++;
  }
}

console.log("== Markdown round-trip ==");
const entry = {
  id: "11111111-2222-3333-4444-555555555555",
  date: "2026-08-11",
  title: "今天",
  mood: "happy" as const,
  weather: "sunny" as const,
  location: "上海",
  tags: ["life", "study"],
  created_at: "2026-08-11T10:00:00.000Z",
  updated_at: "2026-08-11T11:00:00.000Z",
  body: "## 早安\n\n这是一段 **正文**，包含 emoji 🌞 和换行。\n\n- 列表项",
};
const md = serializeEntryFile(entry as any);
console.log(md);
const parsed = parseEntryFile(md);
assert(parsed.meta.id === entry.id, "id 往返一致");
assert(parsed.meta.date === entry.date, "date 往返一致");
assert(parsed.meta.title === entry.title, "title 往返一致");
assert(parsed.meta.mood === entry.mood, "mood 往返一致");
assert(parsed.meta.weather === entry.weather, "weather 往返一致");
assert(parsed.meta.location === entry.location, "location 往返一致");
assert(
  JSON.stringify(parsed.meta.tags) === JSON.stringify(entry.tags),
  "tags 往返一致",
);
assert(parsed.body.includes("早安"), "正文保留标题");
assert(!parsed.body.includes("# 今天"), "正文不含被剥离的 H1");

console.log("== Vault paths ==");
assert(
  entryFilePath({ id: "11111111-2222-3333-4444-555555555555", date: "2026-08-11" }) ===
    "entries/2026/08/2026-08-11-11111111.md",
  "entryFilePath 正确",
);
assert(
  dateKeyFromEntryPath("entries/2026/08/2026-08-11.md") === "2026-08-11",
  "dateKeyFromEntryPath 旧命名反向解析",
);
assert(
  dateKeyFromEntryPath("entries/2026/08/2026-08-11-11111111.md") === "2026-08-11",
  "dateKeyFromEntryPath 新命名(含 shortid)反向解析",
);
assert(dateKeyFromEntryPath("garbage.md") === null, "无效路径返回 null");
assert(
  assetPath("image", "abc.webp") === "assets/images/abc.webp",
  "assetPath(image) 正确",
);
assert(assetDir("video") === "assets/video", "assetDir(video) 正确");
assert(
  conflictFilePath("2026-08-11", "local") ===
    "conflicts/2026-08-11.local.md",
  "conflictFilePath 正确",
);
assert(
  versionFilePath("2026-08-11", 3) === "versions/2026-08-11/v3.md",
  "versionFilePath 正确",
);

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
