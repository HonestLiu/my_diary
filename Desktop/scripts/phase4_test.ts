import { MemoryIndex } from "../src/lib/db/memory";
import type { IndexedEntry } from "../src/lib/db/schema";

let failures = 0;
function assert(cond: boolean, msg: string) {
  if (cond) console.log("  ✓ " + msg);
  else {
    console.error("  ✗ " + msg);
    failures++;
  }
}

function mk(
  id: string,
  date: string,
  title: string,
  body: string,
  tags: string,
): IndexedEntry {
  return {
    id,
    date,
    title,
    body,
    tags,
    mood: "neutral",
    weather: "unknown",
    location: "",
    created_at: "",
    updated_at: "",
    word_count: 0,
    image_count: 0,
  };
}

async function main() {
  const idx = new MemoryIndex();
  await idx.init();
  await idx.upsert(
    mk("1", "2026-08-11", "今天去爬山", "早晨出发，山顶风景很好，空气清新。", "life outdoor"),
  );
  await idx.upsert(
    mk("2", "2026-08-10", "读书笔记", "重读了关于克制的章节，很有启发。", "study"),
  );
  await idx.upsert(
    mk("3", "2026-07-01", "工作会议", "讨论了本地优先架构的设计方案。", "work"),
  );

  console.log("== Search ==");
  const all = await idx.search("");
  assert(all.length === 3, "空查询返回全部 3 条");

  const r1 = await idx.search("爬山");
  assert(r1.length === 1 && r1[0].id === "1", "单关键词命中标题");

  const r2 = await idx.search("本地 架构");
  assert(r2.length === 1 && r2[0].id === "3", "多关键词 AND 命中正文");

  const r3 = await idx.search("study");
  assert(r3.length === 1 && r3[0].id === "2", "命中标签");

  const r4 = await idx.search("不存在的词");
  assert(r4.length === 0, "无命中返回空");

  const ordered = await idx.search("");
  assert(
    ordered[0].date >= ordered[ordered.length - 1].date,
    "结果按日期降序",
  );

  console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
}

void main();
