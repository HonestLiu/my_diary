import { signRequest } from "@/lib/sync/sigv4";
import type { StorageProvider, SyncManifest } from "@/types/journal";

export interface S3Config {
  /** Origin host incl. scheme, e.g. "https://s3.us-east-1.amazonaws.com". */
  endpoint: string;
  bucket: string;
  region: string;
  accessKey: string;
  secretKey: string;
  /** Path-style addressing (MinIO / R2 / OSS). Virtual-hosted for AWS S3. */
  pathStyle: boolean;
}

function stripScheme(host: string): string {
  return host.replace(/^https?:\/\//, "");
}

/**
 * S3-compatible object storage client built on fetch + AWS SigV4.
 * Covers AWS S3, Cloudflare R2, MinIO and Aliyun OSS by varying endpoint /
 * region / pathStyle — satisfying the "StorageProvider abstraction" requirement
 * without pulling in a heavy SDK.
 */
export class S3StorageProvider implements StorageProvider {
  readonly name = "s3";

  constructor(private cfg: S3Config) {}

  private buildUrl(key: string): { url: string; host: string; path: string } {
    const base = this.cfg.endpoint.replace(/\/+$/, "");
    if (this.cfg.pathStyle) {
      const path = `/${this.cfg.bucket}/${key}`;
      return { url: `${base}${path}`, host: stripScheme(base), path };
    }
    const host = `${this.cfg.bucket}.${stripScheme(base)}`;
    const path = `/${key}`;
    return { url: `https://${host}${path}`, host, path };
  }

  private async do(
    method: string,
    key: string,
    opts: { body?: Uint8Array | string; query?: string; contentType?: string } = {},
  ): Promise<Response> {
    const { url, host, path } = this.buildUrl(key);
    const headers: Record<string, string> = {};
    if (opts.contentType) headers["content-type"] = opts.contentType;
    const signed = await signRequest({
      method,
      path,
      query: opts.query,
      headers: { host, ...headers },
      body: opts.body,
      region: this.cfg.region,
      accessKey: this.cfg.accessKey,
      secretKey: this.cfg.secretKey,
    });
    return fetch(url + (opts.query ? `?${opts.query}` : ""), {
      method,
      headers: signed,
      body: opts.body as BodyInit | undefined,
    });
  }

  async upload(remotePath: string, data: Uint8Array | ArrayBuffer): Promise<void> {
    const bytes =
      data instanceof ArrayBuffer ? new Uint8Array(data) : data;
    const res = await this.do("PUT", remotePath, {
      body: bytes,
      contentType: "application/octet-stream",
    });
    if (!res.ok) {
      throw new Error(`S3 upload failed (${remotePath}): ${res.status}`);
    }
  }

  async download(remotePath: string): Promise<Uint8Array> {
    const res = await this.do("GET", remotePath);
    if (!res.ok) {
      throw new Error(`S3 download failed (${remotePath}): ${res.status}`);
    }
    return new Uint8Array(await res.arrayBuffer());
  }

  async delete(remotePath: string): Promise<void> {
    const res = await this.do("DELETE", remotePath);
    if (!res.ok && res.status !== 404) {
      throw new Error(`S3 delete failed (${remotePath}): ${res.status}`);
    }
  }

  async list(prefix = ""): Promise<string[]> {
    const query = `list-type=2&prefix=${encodeURIComponent(prefix)}`;
    const res = await this.do("GET", "", { query });
    if (!res.ok) throw new Error(`S3 list failed: ${res.status}`);
    const xml = await res.text();
    const keys: string[] = [];
    const re = /<Key>([^<]+)<\/Key>/g;
    let m: RegExpExecArray | null;
    while ((m = re.exec(xml))) keys.push(decodeURIComponent(m[1] ?? ""));
    return keys.sort();
  }

  async fetchManifest(): Promise<SyncManifest | null> {
    try {
      const data = await this.download("metadata/sync.json");
      return JSON.parse(new TextDecoder().decode(data)) as SyncManifest;
    } catch {
      return null;
    }
  }

  async pushManifest(manifest: SyncManifest): Promise<void> {
    await this.upload(
      "metadata/sync.json",
      new TextEncoder().encode(JSON.stringify(manifest, null, 2)),
    );
  }
}
