import { sha256Hex } from "@/lib/crypto";
import {
  VAULT_LAYOUT,
  conflictFilePath,
  dateKeyFromEntryPath,
} from "@/lib/vault";
import type { StorageAdapter } from "@/lib/storage/types";
import type {
  StorageProvider,
  SyncConflict,
  SyncFile,
  SyncManifest,
} from "@/types/journal";

export interface SyncResult {
  uploaded: string[];
  downloaded: string[];
  conflicts: SyncConflict[];
  errors: string[];
}

export type ConflictResolution = "local" | "remote";

/**
 * Local-First sync engine. Two-way, conflict-aware, NEVER auto-overwrites.
 *
 * Protocol (matches the spec):
 *   1. scan local files, compute SHA-256 + size
 *   2. fetch the remote manifest (metadata/sync.json)
 *   3. compare against the local baseline (last sync) + current local
 *   4. upload / download new files
 *   5. when a file changed on BOTH sides since last sync → conflict
 *      (write conflicts/<date>.{local,remote}.md, surface to UI)
 */
export class SyncEngine {
  constructor(
    private storage: StorageAdapter,
    private remote: StorageProvider,
    private deviceId: string,
  ) {}

  private async hashFile(path: string): Promise<{ hash: string; size: number }> {
    const bytes = await this.storage.readBytes(path);
    return { hash: await sha256Hex(bytes), size: bytes.length };
  }

  /** Scan the whole vault and build the current local manifest. */
  async buildLocalManifest(): Promise<SyncManifest> {
    const files = await this.storage.list("");
    const syncFiles: SyncFile[] = [];
    for (const f of files) {
      const { hash, size } = await this.hashFile(f);
      syncFiles.push({ path: f, hash, size, updated: Date.now() });
    }
    return {
      version: 1,
      deviceId: this.deviceId,
      files: syncFiles,
      generatedAt: Date.now(),
    };
  }

  async readLocalBaseline(): Promise<SyncManifest | null> {
    if (!(await this.storage.exists(VAULT_LAYOUT.sync))) return null;
    try {
      return JSON.parse(await this.storage.readText(VAULT_LAYOUT.sync));
    } catch {
      return null;
    }
  }

  async writeLocalBaseline(m: SyncManifest): Promise<void> {
    await this.storage.writeText(VAULT_LAYOUT.sync, JSON.stringify(m, null, 2));
  }

  async sync(): Promise<SyncResult> {
    const local = await this.buildLocalManifest();
    // Enumerate actual remote objects, and read the last-pushed manifest for
    // remote-side hashes (used to detect remote changes since last sync).
    const remoteObjects = await this.remote.list("");
    const remoteManifest = await this.remote.fetchManifest();
    const remoteHash = new Map(
      (remoteManifest?.files ?? []).map((f) => [f.path, f.hash]),
    );
    const baseline = await this.readLocalBaseline();

    const localMap = new Map(local.files.map((f) => [f.path, f]));
    const baseMap = new Map((baseline?.files ?? []).map((f) => [f.path, f]));

    const result: SyncResult = {
      uploaded: [],
      downloaded: [],
      conflicts: [],
      errors: [],
    };
    const allPaths = new Set([...localMap.keys(), ...remoteObjects]);

    for (const path of allPaths) {
      const l = localMap.get(path);
      const rExists = remoteObjects.includes(path);
      const rHash = remoteHash.get(path);
      const b = baseMap.get(path);
      try {
        if (l && !rExists) {
          // New locally → upload.
          await this.remote.upload(path, await this.storage.readBytes(path));
          result.uploaded.push(path);
        } else if (!l && rExists) {
          // New on remote → download (remote is authoritative here).
          await this.downloadAndStore(path);
          result.downloaded.push(path);
        } else if (l && rExists) {
          if (rHash !== undefined && l.hash === rHash) continue; // identical
          const localChanged = !b || b.hash !== l.hash;
          // Without a remote manifest entry we cannot prove the remote is
          // unchanged, so we conservatively assume it changed — this prevents
          // silent overwrites and surfaces a conflict for the user to resolve.
          const remoteChanged = rHash === undefined || !b || b.hash !== rHash;
          if (localChanged && remoteChanged) {
            // Changed on BOTH sides since last sync → conflict (no overwrite).
            await this.writeConflict(path);
            result.conflicts.push({
              path,
              local: l,
              remote: {
                path,
                hash: rHash ?? "",
                size: 0,
                updated: Date.now(),
              },
            });
          } else if (localChanged) {
            await this.remote.upload(path, await this.storage.readBytes(path));
            result.uploaded.push(path);
          } else {
            await this.downloadAndStore(path);
            result.downloaded.push(path);
          }
        }
      } catch (e) {
        result.errors.push(
          `${path}: ${e instanceof Error ? e.message : String(e)}`,
        );
      }
    }

    // Baseline becomes the current local state; remote gets the manifest.
    await this.writeLocalBaseline(local);
    try {
      await this.remote.pushManifest(local);
    } catch (e) {
      result.errors.push(
        `manifest: ${e instanceof Error ? e.message : String(e)}`,
      );
    }
    return result;
  }

  private async downloadAndStore(path: string): Promise<void> {
    const data = await this.remote.download(path);
    await this.storage.writeBytes(path, data);
  }

  private async writeConflict(path: string): Promise<void> {
    const dateKey = dateKeyFromEntryPath(path) ?? path.replace(/[\/]/g, "_");
    const localData = await this.storage.readBytes(path);
    const remoteData = await this.remote.download(path);
    await this.storage.writeBytes(conflictFilePath(dateKey, "local"), localData);
    await this.storage.writeBytes(
      conflictFilePath(dateKey, "remote"),
      remoteData,
    );
  }

  /**
   * Resolve a detected conflict. "local" pushes the local copy to the remote;
   * "remote" pulls the remote copy over the local one. Conflict copies are
   * removed and the baseline is refreshed for that path.
   */
  async resolveConflict(
    path: string,
    resolution: ConflictResolution,
  ): Promise<void> {
    if (resolution === "local") {
      await this.remote.upload(path, await this.storage.readBytes(path));
    } else {
      await this.downloadAndStore(path);
    }
    const dateKey = dateKeyFromEntryPath(path) ?? path.replace(/[\/]/g, "_");
    for (const side of ["local", "remote"] as const) {
      const cf = conflictFilePath(dateKey, side);
      if (await this.storage.exists(cf)) await this.storage.delete(cf);
    }
    const baseline = (await this.readLocalBaseline()) ?? {
      version: 1,
      deviceId: this.deviceId,
      files: [],
      generatedAt: Date.now(),
    };
    const map = new Map(baseline.files.map((f) => [f.path, f]));
    const { hash, size } = await this.hashFile(path);
    map.set(path, { path, hash, size, updated: Date.now() });
    baseline.files = [...map.values()];
    await this.writeLocalBaseline(baseline);
  }
}
