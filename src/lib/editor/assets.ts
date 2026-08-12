import { getStorage } from "@/lib/storage";
import { assetPath } from "@/lib/vault";
import type { AssetRef, AssetKind } from "@/types/journal";

/**
 * Editor-side asset pipeline.
 *
 * Images dropped/pasted into the editor are re-encoded to WebP (per the data
 * spec: "图片自动压缩为 WebP") and stored under `assets/images/<hash>.webp`.
 * Other media (audio/video) and generic files are stored verbatim under their
 * respective folders. Every reference is a VAULT-RELATIVE path so the Markdown
 * file stays portable and the "data belongs to the user" principle holds.
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

/** Decode an image File/Blob and re-encode to WebP at the given quality. */
export async function convertToWebp(
  blob: Blob,
  quality = 0.85,
): Promise<Uint8Array> {
  const url = URL.createObjectURL(blob);
  try {
    const img = await loadImage(url);
    const canvas = document.createElement("canvas");
    canvas.width = img.naturalWidth;
    canvas.height = img.naturalHeight;
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("Canvas 2D context unavailable");
    ctx.drawImage(img, 0, 0);
    const out = await canvasToWebp(canvas, quality);
    return new Uint8Array(out);
  } finally {
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

function canvasToWebp(canvas: HTMLCanvasElement, quality: number): Promise<ArrayBuffer> {
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (blob) => {
        if (!blob) return reject(new Error("WebP encode failed"));
        blob.arrayBuffer().then(resolve, reject);
      },
      "image/webp",
      quality,
    );
  });
}

async function fileToBytes(file: File): Promise<Uint8Array> {
  return new Uint8Array(await file.arrayBuffer());
}

/**
 * Persist dropped/pasted files and return their vault-relative references.
 * Images are re-encoded to WebP; other media/files are stored as-is.
 */
export async function saveDroppedAssets(
  files: Iterable<File>,
): Promise<AssetRef[]> {
  const storage = getStorage();
  const refs: AssetRef[] = [];
  for (const file of files) {
    const kind = kindFromFile(file);
    let bytes: Uint8Array;
    let ext: string;
    if (kind === "image") {
      try {
        bytes = await convertToWebp(file);
        ext = "webp";
      } catch {
        // Fallback: keep the original bytes if WebP conversion fails.
        bytes = await fileToBytes(file);
        ext = extOf(file.name) || "bin";
      }
    } else {
      bytes = await fileToBytes(file);
      ext = extOf(file.name) || "bin";
    }
    const hash = await sha256Hex(bytes);
    const filename = `${hash.slice(0, 16)}.${ext}`;
    const path = assetPath(kind, filename);
    await storage.writeBytes(path, bytes);
    refs.push({ kind, path, name: file.name || filename, size: bytes.length });
  }
  return refs;
}
