import { invoke } from "@tauri-apps/api/core";
import { getStorage } from "@/lib/storage";
import { assetPath, thumbnailPath } from "@/lib/vault";
import { isTauri } from "@/lib/storage/types";
import type { TauriFsAdapter } from "@/lib/storage/tauri";
import type { AssetRef, AssetKind } from "@/types/journal";

/**
 * Editor-side asset pipeline.
 *
 * 桌面端（Tauri）：原始文件先按原格式写入 vault，然后调用 Rust 侧
 * `compress_image` / `compress_video` 命令**就地压缩**（保持原格式：
 * jpg→jpg、png→png、webp→webp、mp4→mp4），并生成 256px 列表缩略图。
 * Rust 通过 std::fs 直接读写绝对路径，不受前端 fs scope 限制。
 *
 * 浏览器预览：回退到前端 Canvas/MediaRecorder 方案（图片→WebP、
 * 视频→WebM），仅保证预览可用。
 *
 * 音频和其他文件原样存储。所有引用均为 VAULT-RELATIVE 路径。
 */

/** SHA-256 hex digest (browser/webview Crypto). */
export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  // Copy into a fresh ArrayBuffer-backed view to satisfy BufferSource typing.
  const ab = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(ab).set(bytes);
  const buf = await crypto.subtle.digest("SHA-256", ab);
  const arr = Array.from(new Uint8Array(buf));
  return arr.map((b) => b.toString(16).padStart(2, "0")).join("");
}

function extOf(name: string): string {
  const i = name.lastIndexOf(".");
  return i >= 0 ? name.slice(i + 1).toLowerCase() : "";
}

function kindFromFile(file: File): AssetKind {
  if (file.type.startsWith("image/")) return "image";
  if (file.type.startsWith("audio/")) return "audio";
  if (file.type.startsWith("video/")) return "video";
  return "attachment";
}

/** 压缩/缩略图设置（来自 AppSettings，100 = 不压缩）。 */
export interface CompressionOptions {
  imageQuality: number;
  videoQuality: number;
}

/** 图片压缩质量（1–100）。 */
export function imageQuality01(q: number): number {
  return Math.min(100, Math.max(1, q)) / 100;
}

/** 视频压缩质量 → 目标视频码率（bps），与移动端质量预设对齐。 */
function videoBitrateFor(q: number): number {
  if (q >= 85) return 8_000_000;
  if (q >= 60) return 4_000_000;
  if (q >= 35) return 2_000_000;
  return 1_000_000;
}

/** Decode an image Blob and re-encode to WebP at the given quality (0-1). */
export async function convertToWebp(
  blob: Blob,
  quality = 0.85,
  maxDim = 2000,
): Promise<Uint8Array> {
  const url = URL.createObjectURL(blob);
  try {
    const img = await loadImage(url);
    const { width, height } = downscaleDim(img.naturalWidth, img.naturalHeight, maxDim);
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("Canvas 2D context unavailable");
    ctx.drawImage(img, 0, 0, width, height);
    const out = await canvasToBlob(canvas, "image/webp", quality);
    return new Uint8Array(out);
  } finally {
    URL.revokeObjectURL(url);
  }
}

/** 生成 256px JPEG 列表缩略图（长边 ≤ size）。 */
export async function thumbnailFromImage(
  blob: Blob,
  size = 256,
): Promise<Uint8Array> {
  const url = URL.createObjectURL(blob);
  try {
    const img = await loadImage(url);
    const { width, height } = downscaleDim(img.naturalWidth, img.naturalHeight, size);
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("Canvas 2D context unavailable");
    ctx.drawImage(img, 0, 0, width, height);
    const out = await canvasToBlob(canvas, "image/jpeg", 0.82);
    return new Uint8Array(out);
  } finally {
    URL.revokeObjectURL(url);
  }
}

/**
 * 视频压缩：用 MediaRecorder 将视频重新编码为 WebM。
 * quality ≥ 100 或编码失败时返回 null（调用方回退原文件）。
 */
export async function compressVideo(
  file: File,
  quality: number,
): Promise<Uint8Array | null> {
  if (quality >= 100) return null;
  const url = URL.createObjectURL(file);
  const video = document.createElement("video");
  video.muted = true;
  video.playsInline = true;
  video.preload = "auto";
  video.src = url;
  try {
    await waitForVideoReady(video);
    // captureStream() 不在 TS DOM lib 中，用窄类型断言调用。
    const stream = (video as HTMLVideoElement & { captureStream: () => MediaStream })
      .captureStream();
    const mime = pickVideoMime();
    if (!mime || stream.getVideoTracks().length === 0) return null;
    const rec = new MediaRecorder(stream, {
      mimeType: mime,
      videoBitsPerSecond: videoBitrateFor(quality),
    });
    const chunks: Blob[] = [];
    rec.ondataavailable = (e) => {
      if (e.data.size > 0) chunks.push(e.data);
    };
    const done = new Promise<Uint8Array | null>((resolve) => {
      rec.onstop = () => {
        try {
          const blob = new Blob(chunks, { type: mime });
          blob
            .arrayBuffer()
            .then((ab) => resolve(ab.byteLength > 0 ? new Uint8Array(ab) : null))
            .catch(() => resolve(null));
        } catch {
          resolve(null);
        }
      };
      rec.onerror = () => resolve(null);
    });
    await video.play();
    rec.start(500);
    await new Promise<void>((resolve) => {
      video.onended = () => resolve();
      setTimeout(resolve, video.duration * 1000 + 5000);
    });
    // 防止未播放完就停止导致输出为空：确保至少走完一次。
    if (video.currentTime < video.duration - 0.05) {
      video.currentTime = video.duration;
      await new Promise<void>((resolve) => {
        video.onended = () => resolve();
        setTimeout(resolve, 3000);
      });
    }
    rec.stop();
    const result = await done;
    return result;
  } catch {
    return null;
  } finally {
    video.src = "";
    URL.revokeObjectURL(url);
  }
}

/** 抽取视频封面帧 → 256px JPEG；失败返回 null。 */
export async function posterFromVideo(
  file: File,
  size = 256,
): Promise<Uint8Array | null> {
  const url = URL.createObjectURL(file);
  const video = document.createElement("video");
  video.muted = true;
  video.playsInline = true;
  video.preload = "auto";
  video.src = url;
  try {
    await waitForVideoReady(video);
    const target = Math.min(1, (video.duration || 1) / 2);
    video.currentTime = target;
    await new Promise<void>((resolve, reject) => {
      video.onseeked = () => resolve();
      video.onerror = () => reject(new Error("seek failed"));
      setTimeout(() => resolve(), 3000);
    });
    const { width, height } = downscaleDim(
      video.videoWidth || 640,
      video.videoHeight || 480,
      size,
    );
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext("2d");
    if (!ctx) return null;
    ctx.drawImage(video, 0, 0, width, height);
    const out = await canvasToBlob(canvas, "image/jpeg", 0.5);
    return new Uint8Array(out);
  } catch {
    return null;
  } finally {
    video.src = "";
    URL.revokeObjectURL(url);
  }
}

function loadImage(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error("Failed to decode image"));
    img.src = src;
  });
}

function waitForVideoReady(video: HTMLVideoElement): Promise<void> {
  if (video.readyState >= 1) return Promise.resolve();
  return new Promise((resolve, reject) => {
    const onLoaded = () => {
      video.removeEventListener("loadedmetadata", onLoaded);
      video.removeEventListener("error", onError);
      resolve();
    };
    const onError = () => {
      video.removeEventListener("loadedmetadata", onLoaded);
      video.removeEventListener("error", onError);
      reject(new Error("Failed to load video"));
    };
    video.addEventListener("loadedmetadata", onLoaded);
    video.addEventListener("error", onError);
  });
}

function canvasToBlob(
  canvas: HTMLCanvasElement,
  type: string,
  quality: number,
): Promise<ArrayBuffer> {
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (blob) => {
        if (!blob) return reject(new Error(`Encode failed: ${type}`));
        blob.arrayBuffer().then(resolve, reject);
      },
      type,
      quality,
    );
  });
}

/** 等比缩放尺寸，使长边 ≤ maxDim（保持纵横比）。 */
function downscaleDim(
  w: number,
  h: number,
  maxDim: number,
): { width: number; height: number } {
  if (w <= 0 || h <= 0) return { width: w, height: h };
  const scale = Math.min(1, maxDim / Math.max(w, h));
  return {
    width: Math.max(1, Math.round(w * scale)),
    height: Math.max(1, Math.round(h * scale)),
  };
}

/** 选择 WebView 支持的最高优先级视频 MIME。 */
function pickVideoMime(): string | null {
  const candidates = [
    "video/webm;codecs=vp9,opus",
    "video/webm;codecs=vp8,opus",
    "video/webm",
  ];
  for (const m of candidates) {
    if (typeof MediaRecorder !== "undefined" && MediaRecorder.isTypeSupported(m)) {
      return m;
    }
  }
  return null;
}

async function fileToBytes(file: File): Promise<Uint8Array> {
  return new Uint8Array(await file.arrayBuffer());
}

/**
 * Persist dropped/pasted files and return their vault-relative references.
 *
 * Tauri（桌面端）：
 *   - 原始字节按原格式写入 `assets/<kind>/<hash>.<ext>`
 *   - 调 Rust `compress_image` / `compress_video` 就地压缩（保持格式）+ 生成缩略图
 *   - Rust 失败时保留原文件（不转格式）
 * 浏览器：前端 Canvas/MediaRecorder 方案（图片→WebP、视频→WebM）。
 */
export async function saveDroppedAssets(
  files: Iterable<File>,
  opts: CompressionOptions = { imageQuality: 80, videoQuality: 60 },
): Promise<AssetRef[]> {
  const storage = getStorage();
  const refs: AssetRef[] = [];
  for (const file of files) {
    const kind = kindFromFile(file);
    const ref = isTauri()
      ? await saveViaRust(file, kind, opts, storage)
      : await saveViaBrowser(file, kind, opts);
    if (ref) refs.push(ref);
  }
  return refs;
}

/** 桌面端：原格式写入 + Rust 就地压缩。
 *  图片等待压缩完成返回；视频**立即返回**（先插入占位卡片），随后后台
 *  发起 compress_video（jobId = 资产相对路径），进度经 media-progress 事件
 *  驱动 AttachmentNodeView 的「压缩中」卡片。 */
async function saveViaRust(
  file: File,
  kind: AssetKind,
  opts: CompressionOptions,
  storage: ReturnType<typeof getStorage>,
): Promise<AssetRef | null> {
  const original = await fileToBytes(file);
  const ext = extOf(file.name) || fallbackExt(kind);
  const hash = await sha256Hex(original);
  const filename = `${hash.slice(0, 16)}.${ext}`;
  const path = assetPath(kind, filename);
  await storage.writeBytes(path, original);

  // 视频：立即返回，压缩在后台进行（进度卡片见 AttachmentNodeView）。
  if (kind === "video" && opts.videoQuality < 100) {
    const adapter = storage as TauriFsAdapter;
    const absPath = adapter.resolveAbs(path);
    void invoke<{ size: number; thumb_written: boolean }>("compress_video", {
      jobId: path, // 与 Attachment 节点 src 一致，前端按它匹配进度
      absPath,
      quality: opts.videoQuality,
    }).catch((e) => console.error("视频压缩失败，保留原文件:", e));
    return { kind, path, name: file.name || filename, size: original.length };
  }

  // 图片（或其他）：等待 Rust 压缩完成后返回。
  let size = original.length;
  try {
    if (kind === "image" && opts.imageQuality < 100) {
      const adapter = storage as TauriFsAdapter;
      const absPath = adapter.resolveAbs(path);
      const r = await invoke<{ size: number; thumb_written: boolean }>(
        "compress_image",
        { absPath, quality: opts.imageQuality },
      );
      size = r.size;
    }
  } catch (e) {
    // Rust 压缩失败：保留原文件字节，不转格式。
    console.error("压缩失败，保留原文件:", e);
  }
  return { kind, path, name: file.name || filename, size };
}

/** 浏览器：前端 Canvas/MediaRecorder 压缩（仅预览）。 */
async function saveViaBrowser(
  file: File,
  kind: AssetKind,
  opts: CompressionOptions,
): Promise<AssetRef | null> {
  const storage = getStorage();
  let bytes: Uint8Array;
  let ext: string;
  let thumb: Uint8Array | null = null;

  if (kind === "image") {
    try {
      bytes = await convertToWebp(file, imageQuality01(opts.imageQuality), 2000);
      ext = "webp";
    } catch {
      bytes = await fileToBytes(file);
      ext = extOf(file.name) || "bin";
    }
    try {
      thumb = await thumbnailFromImage(file);
    } catch {
      thumb = null;
    }
  } else if (kind === "video") {
    const compressed =
      opts.videoQuality < 100 ? await compressVideo(file, opts.videoQuality) : null;
    if (compressed) {
      bytes = compressed;
      ext = "webm";
    } else {
      bytes = await fileToBytes(file);
      ext = extOf(file.name) || "bin";
    }
    try {
      thumb = await posterFromVideo(file);
    } catch {
      thumb = null;
    }
  } else {
    bytes = await fileToBytes(file);
    ext = extOf(file.name) || "bin";
  }

  const hash = await sha256Hex(bytes);
  const filename = `${hash.slice(0, 16)}.${ext}`;
  const path = assetPath(kind, filename);
  await storage.writeBytes(path, bytes);
  if (thumb) {
    await storage.writeBytes(thumbnailPath(path), thumb).catch(() => undefined);
  }
  return { kind, path, name: file.name || filename, size: bytes.length };
}

/** 无扩展名时的兜底扩展名。 */
function fallbackExt(kind: AssetKind): string {
  switch (kind) {
    case "image":
      return "png";
    case "video":
      return "mp4";
    case "audio":
      return "m4a";
    default:
      return "bin";
  }
}
