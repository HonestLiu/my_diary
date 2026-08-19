import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import { isTauri } from "@/lib/storage/types";
import { setMediaProgress, type MediaProgress } from "@/lib/editor/mediaProgress";

/**
 * 监听 Rust 侧 `media-progress` 事件并写入 mediaProgress store。
 * 在应用启动时调用一次（main.tsx）。浏览器预览环境（无 Tauri）直接跳过。
 */

export async function listenMediaProgress(): Promise<void> {
  if (!isTauri()) return;
  try {
    await listen<MediaProgress>("media-progress", (e) => {
      const p = e.payload;
      setMediaProgress(p.jobId, p);
      // done / error 是终态：短暂保留后清除，避免 map 无限增长。
      if (p.stage === "done" || p.stage === "error") {
        const id = p.jobId;
        setTimeout(() => setMediaProgress(id, null), 30_000);
      }
    });
  } catch (err) {
    console.error("监听媒体压缩进度失败:", err);
  }
}

// Re-export for callers that need the unlisten handle (e.g. tests).
export type { UnlistenFn };
