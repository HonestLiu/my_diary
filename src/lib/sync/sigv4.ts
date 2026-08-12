import { sha256Hex, hmacSha256, hmacSha256Hex } from "@/lib/crypto";

/**
 * Minimal AWS Signature Version 4 implementation for S3-compatible services
 * (AWS S3, Cloudflare R2, MinIO, Aliyun OSS). Dependency-free — uses Web
 * Crypto — so it works in the browser and the Tauri webview alike.
 */

export interface SignOptions {
  method: string;
  /** Path portion of the URL, e.g. "/my-bucket/entries/2026/08/11.md". */
  path: string;
  /** Canonical query string (already URI-encoded, without leading '?'). */
  query?: string;
  /** Additional headers to sign (host is added automatically). */
  headers?: Record<string, string>;
  /** Request payload (used for the content sha256). */
  body?: Uint8Array | string;
  region: string;
  accessKey: string;
  secretKey: string;
  /** Service name, default "s3". */
  service?: string;
  /** ISO datetime; generated if omitted. */
  datetime?: string;
}

function amzDate(d: Date): string {
  // 20210818T140503Z
  return d.toISOString().replace(/[:-]|\.\d{3}/g, "").replace(/\.\d{3}/, "");
}

function uriEncode(s: string): string {
  return encodeURIComponent(s).replace(/%2F/g, "/");
}

/** Build the Authorization header + required x-amz-* headers. */
export async function signRequest(opts: SignOptions): Promise<Record<string, string>> {
  const service = opts.service ?? "s3";
  const datetime = opts.datetime ?? amzDate(new Date());
  const dateStamp = datetime.slice(0, 8);

  const payloadBytes =
    typeof opts.body === "string"
      ? new TextEncoder().encode(opts.body)
      : opts.body ?? new Uint8Array(0);
  const payloadHash = await sha256Hex(payloadBytes);

  const extra = opts.headers ?? {};
  const host = extra.host;
  if (!host) throw new Error("signRequest requires a 'host' header");

  const signedHeaderNames = ["host", "x-amz-content-sha256", "x-amz-date"];
  const headersToSign: Record<string, string> = {
    host,
    "x-amz-content-sha256": payloadHash,
    "x-amz-date": datetime,
    ...extra,
  };

  const canonicalHeaders = signedHeaderNames
    .map((n) => `${n}:${(headersToSign[n] ?? "").trim()}\n`)
    .join("");
  const signedHeaders = signedHeaderNames.join(";");

  const canonicalUri = uriEncode(opts.path).replace(/%2F/g, "/");
  const canonicalQuery = opts.query ?? "";
  const canonicalRequest = [
    opts.method.toUpperCase(),
    canonicalUri,
    canonicalQuery,
    canonicalHeaders,
    signedHeaders,
    payloadHash,
  ].join("\n");

  const scope = `${dateStamp}/${opts.region}/${service}/aws4_request`;
  const stringToSign = [
    "AWS4-HMAC-SHA256",
    datetime,
    scope,
    await sha256Hex(canonicalRequest),
  ].join("\n");

  let key: Uint8Array = new TextEncoder().encode("AWS4" + opts.secretKey);
  key = await hmacSha256(key, dateStamp);
  key = await hmacSha256(key, opts.region);
  key = await hmacSha256(key, service);
  key = await hmacSha256(key, "aws4_request");
  const signature = await hmacSha256Hex(key, stringToSign);

  const authorization =
    `AWS4-HMAC-SHA256 Credential=${opts.accessKey}/${scope}, ` +
    `SignedHeaders=${signedHeaders}, Signature=${signature}`;

  return {
    ...extra,
    "x-amz-content-sha256": payloadHash,
    "x-amz-date": datetime,
    Authorization: authorization,
  };
}
