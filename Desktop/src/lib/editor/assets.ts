import { getStorage } from "@/lib/storage";
import { assetPath, thumbnailPath } from "@/lib/vault";
import type { AssetRef, AssetKind } from "@/types/journal";

/**
 * Editor-side asset pipeline.
 *
 * Images dropped/pasted into the editor are re-encoded to WebP (per the data
 * spec: "图片自动压缩为 WebP") at the configured quality, downscaled to a
 * 2000px max edge, and stored under `assets/images/<hash>.webp`. Videos are
 * re-encoded to WebM with the MediaRecorder API when compression is enabled;
 * on any failure the original bytes are kept. Every image/video also gets a
 * 256px JPEG list thumbnail under `assets/thumbnails/<hash>.jpg` (matches the
 * mobile app), which the list / media / memory / map views prefer to load.
 * Audio and other files are stored verbatim.
 *
 * Every reference is a VAULT-RELATIVE path so the Markdown file stays portable
 * and the "data belongs to the user" principle holds.
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
 * Images are re-encoded to WebP (quality/long-edge from [opts]); videos are
 * re-encoded to WebM when compression is enabled (fallback to original on
 * failure). Images and videos also get a 256px JPEG thumbnail. Audio and other
 * files are stored as-is.
 */
export async function saveDroppedAssets(
  files: Iterable<File>,
  opts: CompressionOptions = { imageQuality: 80, videoQuality: 60 },
): Promise<AssetRef[]> {
  const storage = getStorage();
  const refs: AssetRef[] = [];
  for (const file of files) {
    const kind = kindFromFile(file);
    let bytes: Uint8Array;
    let ext: string;
    let thumb: Uint8Array | null = null;

    if (kind === "image") {
      try {
        bytes = await convertToWebp(file, imageQuality01(opts.imageQuality), 2000);
        ext = "webp";
      } catch {
        // Fallback: keep the original bytes if WebP conversion fails.
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
    refs.push({ kind, path, name: file.name || filename, size: bytes.length });
  }
  return refs;
}
