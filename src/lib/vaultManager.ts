import { isTauri } from "./storage/types";
import { uuid } from "./utils";

/**
 * Multi-vault registry.
 *
 * The journal vault is "where your diary lives". A user may keep several —
 * e.g. one for personal writing, one for work notes. This module owns the
 * list of vaults and which one is active, persisted in `localStorage` so the
 * choice survives reloads (it is metadata ABOUT the vaults, not journal
 * content, so it does not belong inside any single vault).
 *
 * Resolution rules:
 *   - Tauri (desktop): each vault maps to an absolute directory on disk.
 *     A blank root is resolved lazily to `<appDataDir>/my-diary/<slug>`.
 *   - Browser (web preview): each vault maps to its own IndexedDB database,
 *     named after the vault id, so data is fully isolated per vault.
 */
export interface VaultDescriptor {
  id: string;
  name: string;
  /** Tauri: absolute directory path. Browser: IndexedDB db name (namespace). */
  root: string;
  createdAt: number;
}

interface VaultRegistry {
  vaults: VaultDescriptor[];
  activeId: string;
}

const KEY = "my-diary-vaults";

export function loadRegistry(): VaultRegistry {
  if (typeof localStorage !== "undefined") {
    const raw = localStorage.getItem(KEY);
    if (raw) {
      try {
        const r = JSON.parse(raw) as VaultRegistry;
        if (r && Array.isArray(r.vaults) && r.vaults.length && r.activeId) {
          return r;
        }
      } catch {
        /* corrupt — fall through to default */
      }
    }
  }
  return { vaults: [], activeId: "" };
}

export function saveRegistry(r: VaultRegistry): void {
  if (typeof localStorage !== "undefined") {
    localStorage.setItem(KEY, JSON.stringify(r));
  }
}

/** Ensure at least one vault exists; create a default one on first run. */
export function ensureRegistry(): VaultRegistry {
  const reg = loadRegistry();
  if (reg.vaults.length) return reg;
  const id = uuid();
  const vault: VaultDescriptor = {
    id,
    name: "我的日记",
    // Tauri root is resolved lazily from appDataDir; browser uses a db namespace.
    root: isTauri() ? "" : `my-diary-${id}`,
    createdAt: Date.now(),
  };
  const fresh: VaultRegistry = { vaults: [vault], activeId: id };
  saveRegistry(fresh);
  return fresh;
}

/** Compute the concrete on-disk / db root for a vault (async for Tauri). */
export async function resolveRootForVault(v: VaultDescriptor): Promise<string> {
  if (isTauri()) {
    if (v.root && v.root.trim()) return v.root.replace(/\\/g, "/").replace(/\/+$/, "");
    const { appDataDir } = await import("@tauri-apps/api/path");
    const dir = (await appDataDir()).replace(/\\/g, "/");
    return `${dir}/my-diary/${slug(v.name)}`;
  }
  // browser: the vault root doubles as the IndexedDB database name.
  return v.root || `my-diary-${v.id}`;
}

/** Build a new vault descriptor (root is left for resolveRootForVault). */
export function makeVault(name: string, path?: string): VaultDescriptor {
  const id = uuid();
  const trimmed = name.trim() || "新日记";
  return {
    id,
    name: trimmed,
    root: isTauri()
      ? path && path.trim()
        ? path.trim().replace(/\\/g, "/").replace(/\/+$/, "")
        : ""
      : `my-diary-${id}`,
    createdAt: Date.now(),
  };
}

/** URL/path-safe slug for a vault name. */
export function slug(name: string): string {
  const s = name
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9一-龥]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return s || "vault";
}
