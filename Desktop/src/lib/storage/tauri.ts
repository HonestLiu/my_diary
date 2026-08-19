import {
  readTextFile,
  writeTextFile,
  readFile,
  writeFile,
  exists,
  mkdir,
  remove,
  readDir,
} from "@tauri-apps/plugin-fs";
import type { StorageAdapter } from "./types";
import { requiredDirectories } from "@/lib/vault";

/**
 * TauriFsAdapter — persists the vault to the real filesystem via the
 * official Tauri v2 filesystem plugin. Paths are absolute; the adapter joins
 * the vault root with the vault-relative path it is given.
 */
export class TauriFsAdapter implements StorageAdapter {
  readonly kind = "tauri" as const;
  private root = "";

  constructor(vaultRoot?: string) {
    this.root = vaultRoot ?? "";
  }

  private abs(rel: string): string {
    const clean = rel.replace(/\\/g, "/").replace(/^\/+/, "");
    return `${this.root}/${clean}`.replace(/\/+/g, "/");
  }

  async init(vaultRoot: string): Promise<void> {
    this.root = vaultRoot.replace(/\\/g, "/").replace(/\/+$/, "");
    await mkdir(this.root, { recursive: true });
    for (const dir of requiredDirectories()) {
      await mkdir(this.abs(dir), { recursive: true });
    }
  }

  /**
   * Resolve a vault-relative path to an absolute disk path.
   * Used to hand a real file to a Rust command (e.g. in-place media
   * compression) that reads/writes the file directly via std::fs.
   */
  resolveAbs(rel: string): string {
    return this.abs(rel);
  }

  async readText(path: string): Promise<string> {
    return readTextFile(this.abs(path));
  }

  async writeText(path: string, content: string): Promise<void> {
    await mkdir(this.abs(path).replace(/\/[^/]+$/, ""), { recursive: true });
    await writeTextFile(this.abs(path), content);
  }

  async readBytes(path: string): Promise<Uint8Array> {
    return readFile(this.abs(path));
  }

  async writeBytes(path: string, data: Uint8Array): Promise<void> {
    await mkdir(this.abs(path).replace(/\/[^/]+$/, ""), { recursive: true });
    await writeFile(this.abs(path), data);
  }

  async exists(path: string): Promise<boolean> {
    return exists(this.abs(path));
  }

  async delete(path: string): Promise<void> {
    await remove(this.abs(path));
  }

  async list(prefix: string): Promise<string[]> {
    const results: string[] = [];
    const walk = async (absDir: string, relDir: string): Promise<void> => {
      let entries: Array<{ name: string; isDirectory?: boolean }> = [];
      try {
        entries = (await readDir(absDir)) as Array<{
          name: string;
          isDirectory?: boolean;
        }>;
      } catch {
        return;
      }
      for (const e of entries) {
        const rel = relDir ? `${relDir}/${e.name}` : e.name;
        if (e.isDirectory) {
          await walk(`${absDir}/${e.name}`, rel);
        } else {
          results.push(rel);
        }
      }
    };
    const start = this.abs(prefix);
    await walk(start, prefix.replace(/\/+$/, ""));
    return results.sort();
  }

  async resolveUrl(relPath: string): Promise<string> {
    const bytes = await this.readBytes(relPath).catch(() => null);
    if (!bytes) return "";
    const mime = mimeFromPath(relPath);
    return bytesToDataUrl(bytes, mime);
  }
}

/** Best-effort MIME type from a file extension. */
function mimeFromPath(path: string): string {
  const ext = path.split(".").pop()?.toLowerCase() ?? "";
  switch (ext) {
    case "webp":
      return "image/webp";
    case "png":
      return "image/png";
    case "jpg":
    case "jpeg":
      return "image/jpeg";
    case "gif":
      return "image/gif";
    case "svg":
      return "image/svg+xml";
    case "mp3":
      return "audio/mpeg";
    case "wav":
      return "audio/wav";
    case "ogg":
      return "audio/ogg";
    case "mp4":
      return "video/mp4";
    case "webm":
      return "video/webm";
    case "mov":
      return "video/quicktime";
    case "pdf":
      return "application/pdf";
    default:
      return "application/octet-stream";
  }
}

/** Encode raw bytes as a `data:` URL (works in any webview / browser). */
function bytesToDataUrl(bytes: Uint8Array, mime: string): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode.apply(
      null,
      Array.from(bytes.subarray(i, i + chunk)),
    );
  }
  return `data:${mime};base64,${btoa(binary)}`;
}
