import type { StorageAdapter } from "./types";

/**
 * BrowserAdapter — backs the vault with IndexedDB.
 *
 * Each file is stored as a record keyed by its vault-relative path.
 * This lets the app run and persist fully in a plain browser (the Vite dev
 * preview), and keeps the exact same Markdown/Assets format as the desktop
 * build, so a vault exported from here is identical to one on disk.
 */

const DB_NAME = "my-diary-vault";
const STORE = "files";
const VERSION = 1;

interface FileRecord {
  path: string;
  text?: string;
  bytes?: Uint8Array;
  updated: number;
}

/**
 * BrowserAdapter — backs the vault with IndexedDB.
 *
 * Each file is stored as a record keyed by its vault-relative path.
 * This lets the app run and persist fully in a plain browser (the Vite dev
 * preview), and keeps the exact same Markdown/Assets format as the desktop
 * build, so a vault exported from here is identical to one on disk.
 *
 * Multi-vault support: the IndexedDB database NAME is the vault namespace.
 * `init(vaultRoot)` re-points this adapter at a different database, so a single
 * BrowserAdapter instance can serve whichever vault is currently active
 * (the desktop TauriFsAdapter re-points its directory the same way).
 */
export class BrowserAdapter implements StorageAdapter {
  readonly kind = "browser" as const;
  /** IndexedDB database name = the active vault's namespace. */
  private dbName: string;

  constructor(dbName?: string) {
    this.dbName = dbName || DB_NAME;
  }

  async init(vaultRoot: string): Promise<void> {
    // In the browser the "root" IS the IndexedDB database name (namespace).
    if (vaultRoot) this.dbName = vaultRoot;
    await openDb(this.dbName).then((db) => db.close());
  }

  async readText(path: string): Promise<string> {
    const rec = await tx<FileRecord | undefined>(this.dbName, "readonly", (s) =>
      s.get(path),
    );
    if (!rec) throw new Error(`File not found: ${path}`);
    if (rec.text !== undefined) return rec.text;
    if (rec.bytes) return new TextDecoder().decode(rec.bytes);
    throw new Error(`File not found: ${path}`);
  }

  async writeText(path: string, content: string): Promise<void> {
    const rec: FileRecord = { path, text: content, updated: Date.now() };
    await tx(this.dbName, "readwrite", (s) => s.put(rec));
  }

  async readBytes(path: string): Promise<Uint8Array> {
    const rec = await tx<FileRecord | undefined>(this.dbName, "readonly", (s) =>
      s.get(path),
    );
    if (!rec || !rec.bytes) throw new Error(`Binary not found: ${path}`);
    return rec.bytes;
  }

  async writeBytes(path: string, data: Uint8Array): Promise<void> {
    const rec: FileRecord = { path, bytes: data, updated: Date.now() };
    await tx(this.dbName, "readwrite", (s) => s.put(rec));
  }

  async exists(path: string): Promise<boolean> {
    const rec = await tx<FileRecord | undefined>(this.dbName, "readonly", (s) =>
      s.get(path),
    );
    return !!rec;
  }

  async delete(path: string): Promise<void> {
    await tx(this.dbName, "readwrite", (s) => s.delete(path));
  }

  async list(prefix: string): Promise<string[]> {
    const all = await tx<FileRecord[]>(this.dbName, "readonly", (s) =>
      s.getAll(),
    );
    return all
      .map((r) => r.path)
      .filter((p) => p.startsWith(prefix))
      .sort();
  }

  async resolveUrl(relPath: string): Promise<string> {
    const bytes = await this.readBytes(relPath).catch(() => null);
    if (!bytes) return "";
    const mime = mimeFromPath(relPath);
    const blob = new Blob([bytes as BlobPart], { type: mime });
    return URL.createObjectURL(blob);
  }
}

function openDb(dbName: string): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(dbName, VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(STORE)) {
        db.createObjectStore(STORE, { keyPath: "path" });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

function tx<T>(
  dbName: string,
  mode: IDBTransactionMode,
  fn: (store: IDBObjectStore) => IDBRequest<T>,
): Promise<T> {
  return openDb(dbName).then(
    (db) =>
      new Promise<T>((resolve, reject) => {
        const t = db.transaction(STORE, mode);
        const req = fn(t.objectStore(STORE));
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
        t.oncomplete = () => db.close();
      }),
  );
}

/** Best-effort MIME type from a file extension. */
export function mimeFromPath(path: string): string {
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
