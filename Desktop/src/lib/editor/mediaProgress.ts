import { useSyncExternalStore } from "react";

/**
 * 媒体压缩进度 store。
 *
 * Rust 侧 `compress_video` 命令压缩全程通过 `media-progress` 事件上报
 * （下载 ffmpeg / 转码 / 封面 / 完成 / 失败），前端在 main.tsx 监听该事件
 * 写入这里；编辑器里的「压缩中」视频卡片按 job_id（= 资产相对路径）订阅。
 */

export interface MediaProgress {
  jobId: string;
  /** "downloading" | "transcoding" | "thumbnail" | "done" | "error" */
  stage: string;
  /** 0-100 */
  percent: number;
  message: string;
}

/** jobId → 最新进度。jobId 用资产相对路径，与 Attachment 节点的 src 一致。 */
const progressMap = new Map<string, MediaProgress>();
const listeners = new Set<() => void>();

function notify() {
  for (const fn of listeners) fn();
}

/** 写入（或清除）一条进度。由 mediaListener 的事件监听调用。 */
export function setMediaProgress(jobId: string, p: MediaProgress | null): void {
  if (p) progressMap.set(jobId, p);
  else progressMap.delete(jobId);
  notify();
}

/** 读取某 job 的当前进度。 */
export function getMediaProgress(jobId: string): MediaProgress | undefined {
  return progressMap.get(jobId);
}

function subscribe(fn: () => void): () => void {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

/** React 订阅：压缩中卡片用它按 jobId 拿实时进度。 */
export function useMediaProgress(jobId: string): MediaProgress | undefined {
  return useSyncExternalStore(
    subscribe,
    () => progressMap.get(jobId),
    () => undefined,
  );
}
