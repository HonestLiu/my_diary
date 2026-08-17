import type { JournalEntry, Mood } from "@/types/journal";
import { formatDateKey, uuid } from "@/lib/utils";

/**
 * Sample entries used ONLY to bootstrap an empty vault in the browser dev
 * preview, so the UI has realistic content to show. Never seeded in the
 * desktop (Tauri) build — there the vault belongs entirely to the user.
 */
export function buildSampleEntries(): JournalEntry[] {
  const today = new Date();
  /**
   * `hour` shifts created_at within the day so several entries of the same date
   * keep a sensible order (the newest one shows first).
   */
  const mk = (
    offsetDays: number,
    title: string,
    mood: Mood,
    body: string,
    tags: string[],
    hour = 21,
  ): JournalEntry => {
    const d = new Date(today);
    d.setDate(d.getDate() - offsetDays);
    const key = formatDateKey(d);
    d.setHours(hour, 0, 0, 0);
    const iso = d.toISOString();
    return {
      id: uuid(),
      date: key,
      title,
      mood,
      weather: "sunny",
      tags,
      assets: [],
      created_at: iso,
      updated_at: iso,
      body,
    };
  };

  // Note the two entries dated today: a day is a container, not a slot.
  return [
    mk(0, "项目启动", "happy", "项目正式启动，搭建了整体架构与本地优先的数据格式。", [
      "life",
      "dev",
    ], 10),
    mk(0, "深夜随笔", "calm", "同一天可以写好几篇 —— 早上记事，晚上记心情。", ["life"], 23),
    mk(1, "周末散步", "calm", "沿着河边走了一圈，风很舒服，心也静了下来。", ["life"]),
    mk(2, "读书笔记", "neutral", "重读了《设计师的自我修养》，关于克制的那章很有启发。", [
      "study",
    ]),
    mk(4, "线上会议", "tired", "连续三场会议，有点疲惫，但方向更清晰了。", ["work"]),
    mk(6, "一个新想法", "excited", "关于本地优先架构的一些灵感，记录一下。", ["idea"]),
  ];
}
