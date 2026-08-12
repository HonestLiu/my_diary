/**
 * Small Web Crypto helpers used by the sync engine (file hashing) and the
 * S3-compatible client (AWS SigV4 signing). No native dependencies, so they
 * run identically in the browser and the Tauri webview.
 */

function toBytes(data: string | Uint8Array): Uint8Array {
  if (typeof data === "string") return new TextEncoder().encode(data);
  return data;
}

export async function sha256Hex(message: string | Uint8Array): Promise<string> {
  const bytes = toBytes(message);
  const ab = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(ab).set(bytes);
  const digest = await crypto.subtle.digest("SHA-256", ab);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export async function hmacSha256(
  key: Uint8Array,
  message: string,
): Promise<Uint8Array> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    key as BufferSource,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    cryptoKey,
    new TextEncoder().encode(message) as BufferSource,
  );
  return new Uint8Array(sig);
}

export async function hmacSha256Hex(
  key: Uint8Array,
  message: string,
): Promise<string> {
  const sig = await hmacSha256(key, message);
  return Array.from(sig)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
