/**
 * Core domain types for MyDiary.
 *
 * These types are the contract shared across every phase:
 * storage (P2), editor (P3), timeline/calendar/search (P4),
 * sync (P5), versioning (P6) and the cloud service (P7).
 *
 * Design principle: the on-disk Markdown file is the source of truth.
 * Everything here mirrors what is persisted as frontmatter + body.
 */

export type Mood =
  | "happy"
  | "calm"
  | "sad"
  | "angry"
  | "tired"
  | "excited"
  | "neutral";

export type Weather =
  | "sunny"
  | "cloudy"
  | "rainy"
  | "snowy"
  | "foggy"
  | "windy"
  | "unknown";

/**
 * Appearance / personalization primitives.
 * `Theme` is the light/dark/system selector; `AccentKey` picks the brand color
 * palette; `FontKey` picks the diary typeface.
 */
export type Theme = "light" | "dark" | "system";
export type AccentKey =
  | "amber"
  | "rose"
  | "violet"
  | "emerald"
  | "sky"
  | "slate";
export type FontKey = "sans" | "serif";

export interface JournalMeta {
  /**
   * Stable identity of the entry — this, not the date, is what addresses an
   * entry everywhere (file name, index, versions, UI routing).
   */
  id: string;
  /**
   * The day the entry belongs to, YYYY-MM-DD (local). Ordinary metadata: any
   * number of entries may share a date, and an entry can be moved to another
   * day by editing this field.
   */
  date: string;
  /** Free-form, user-editable title (may be empty → shown as "未命名"). */
  title: string;
  mood: Mood;
  weather: Weather;
  location?: string;
  tags: string[];
  /** Asset references (images / media / files) attached to the entry. */
  assets: AssetRef[];
  created_at: string; // ISO 8601
  updated_at: string; // ISO 8601
}

/**
 * A journal entry as held in memory. `body` is the raw Markdown
 * body (without frontmatter). `content` may be the TipTap JSON in P3+.
 */
export interface JournalEntry extends JournalMeta {
  /** Raw Markdown body (no frontmatter). */
  body: string;
  /** Optional TipTap JSON document (editor internal representation). */
  content?: unknown;
}

export type AssetKind = "image" | "audio" | "video" | "attachment";

export interface AssetRef {
  kind: AssetKind;
  /** Relative path under assets/, e.g. "images/<hash>.webp". */
  path: string;
  /** Original filename (for display / download). */
  name?: string;
  size?: number;
}

/**
 * On-disk settings.json (user preferences, NOT journal content).
 */
export interface AppSettings {
  version: 1;
  theme: Theme;
  /** Brand color palette (recolors the whole app via CSS variables). */
  accent: AccentKey;
  /** Diary typeface: system sans-serif or a serif reading face. */
  font: FontKey;
  /** Author name shown in exports and the app shell (personalization). */
  displayName: string;
  /** First day of the week for the calendar: 0 = Sunday, 1 = Monday. */
  weekStartsOn: 0 | 1;
  /** Root directory of the journal vault (absolute path). */
  vaultPath?: string;
  /** Default new-entry behaviour. */
  defaultMood: Mood;
  /** Sync configuration (provider-agnostic). */
  sync?: SyncConfig;
}

/* ------------------------------------------------------------------ */
/* Sync protocol (P5 / P7)                                            */
/* ------------------------------------------------------------------ */

export interface SyncConfig {
  enabled: boolean;
  provider: "s3" | "r2" | "minio" | "oss" | "none";
  endpoint?: string;
  bucket?: string;
  region?: string;
  /** Access credentials are stored via the OS keychain in P5+. */
  accessKey?: string;
  secretKey?: string;
  /** Path-style addressing (MinIO / R2 / OSS). Virtual-hosted for AWS S3. */
  pathStyle?: boolean;
  /** Cloud service auth token (P7). */
  authToken?: string;
  baseUrl?: string;
}

/**
 * One record in sync.json / the cloud index.
 * Path is always relative to the vault root.
 */
export interface SyncFile {
  path: string;
  /** SHA-256 hex digest of the file content. */
  hash: string;
  size: number;
  /** Last modification timestamp (ms since epoch). */
  updated: number;
}

export interface SyncManifest {
  version: 1;
  /** Device that produced this manifest. */
  deviceId: string;
  files: SyncFile[];
  /** When the manifest was generated. */
  generatedAt: number;
}

/* ------------------------------------------------------------------ */
/* Storage abstraction (P5) — provider independent                    */
/* ------------------------------------------------------------------ */

export interface StorageProvider {
  readonly name: string;
  upload(remotePath: string, data: Uint8Array | ArrayBuffer): Promise<void>;
  download(remotePath: string): Promise<Uint8Array>;
  delete(remotePath: string): Promise<void>;
  /** List objects, optionally under a prefix. */
  list(prefix?: string): Promise<string[]>;
  /** Fetch the remote sync manifest if present. */
  fetchManifest(): Promise<SyncManifest | null>;
  pushManifest(manifest: SyncManifest): Promise<void>;
}

/* ------------------------------------------------------------------ */
/* Encryption abstraction (P12) — end-to-end ready                    */
/* ------------------------------------------------------------------ */

export interface EncryptionProvider {
  readonly name: string;
  encrypt(plain: Uint8Array): Promise<Uint8Array>;
  decrypt(cipher: Uint8Array): Promise<Uint8Array>;
  isEnabled(): boolean;
}

/* ------------------------------------------------------------------ */
/* Conflict handling (P9)                                             */
/* ------------------------------------------------------------------ */

export type ConflictResolution = "local" | "remote" | "merge";

export interface SyncConflict {
  path: string;
  local: SyncFile;
  remote: SyncFile;
}
