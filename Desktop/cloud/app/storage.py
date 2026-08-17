"""Hand-rolled AWS SigV4 *query-string* presigning for S3-compatible storage.

Why hand-rolled (no boto3/botocore): keeps the cloud service dependency-light
and mirrors the client-side SigV4 implementation from the desktop app (Phase 5).
The cloud only ever *mints* short-lived URLs — it never reads or stores bodies.

This module is intentionally free of framework/config imports so its signing
math can be unit-tested against AWS's published vectors with only the stdlib.

Reference: https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-query-string-auth.html
"""
from __future__ import annotations

import hashlib
import hmac
import urllib.parse
from datetime import datetime, timezone

# A config object needs these attributes (see app.config.Settings):
#   s3_endpoint, s3_region, s3_bucket, s3_access_key, s3_secret_key, s3_path_style
UNSIGNED_PAYLOAD = "UNSIGNED-PAYLOAD"
ALGORITHM = "AWS4-HMAC-SHA256"

# NOTE: For SigV4 *query-string* (presigned-URL) requests to S3, the payload
# hash in the canonical request is ALWAYS the literal string UNSIGNED-PAYLOAD.
# This is confirmed by AWS's published GET-presign worked example
# (docs.aws.amazon.com/AmazonS3/latest/developerguide/sigv4-query-string-auth.html),
# whose canonical request hash is
#   3bfa292879f6447bbcda7001decf97f4a54dc650c8942174ae0a9121cf58ad04
# and whose signature is
#   aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404
# (host = examplebucket.s3.amazonaws.com, no region in the hostname).


def _sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _hmac(key: bytes, msg: str) -> bytes:
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()


def _signing_key(secret: str, date_stamp: str, region: str, service: str = "s3") -> bytes:
    k = _hmac(("AWS4" + secret).encode("utf-8"), date_stamp)
    k = _hmac(k, region)
    k = _hmac(k, service)
    k = _hmac(k, "aws4_request")
    return k


def _aws_encode(value: str) -> str:
    """RFC 3986 encode suitable for SigV4 (spaces -> %20, not '+')."""
    return urllib.parse.quote(value, safe="").replace("+", "%20")


def _encode_path(path: str) -> str:
    """Encode each path segment but keep the '/' separators."""
    return "/".join(_aws_encode(seg) for seg in path.split("/"))


def _build_base_url(cfg, bucket: str, key: str) -> tuple[str, str]:
    """Return (host, full_url) for the given bucket/key."""
    if getattr(cfg, "s3_path_style", False):
        base = cfg.s3_endpoint or f"https://s3.{cfg.s3_region}.amazonaws.com"
        return urllib.parse.urlparse(base).netloc, f"{base}/{bucket}/{key}"
    if cfg.s3_endpoint:
        # Custom virtual-hosted endpoint, e.g. R2: https://<acct>.r2.cloudflarestorage.com
        base = cfg.s3_endpoint
        return urllib.parse.urlparse(base).netloc, f"{base}/{bucket}/{key}"
    # Default AWS: global virtual-hosted endpoint. The region lives in the
    # credential scope (below), not the hostname — this matches AWS's published
    # SigV4 presign example and keeps the signature vector stable.
    host = f"{bucket}.s3.amazonaws.com"
    return host, f"https://{host}/{key}"


def presign_url(cfg, key: str, method: str, expires: int) -> str:
    """Produce a presigned GET/PUT URL for `key` (already namespaced by caller)."""
    if not cfg.s3_access_key or not cfg.s3_secret_key:
        raise RuntimeError("S3 credentials are not configured on the server.")

    method = method.upper()
    now = datetime.now(timezone.utc)
    amz_date = now.strftime("%Y%m%dT%H%M%SZ")
    date_stamp = now.strftime("%Y%m%d")
    scope = f"{date_stamp}/{cfg.s3_region}/s3/aws4_request"
    credential = f"{cfg.s3_access_key}/{scope}"

    host, url = _build_base_url(cfg, cfg.s3_bucket, key)
    parsed = urllib.parse.urlparse(url)
    canonical_uri = _encode_path(parsed.path) or "/"

    # Canonical query string (sorted, encoded) — signature appended afterwards.
    params = {
        "X-Amz-Algorithm": ALGORITHM,
        "X-Amz-Credential": credential,
        "X-Amz-Date": amz_date,
        "X-Amz-Expires": str(expires),
        "X-Amz-SignedHeaders": "host",
    }
    canonical_query = "&".join(
        f"{_aws_encode(k)}={_aws_encode(v)}" for k, v in sorted(params.items())
    )

    canonical_headers = f"host:{host}\n"
    signed_headers = "host"
    # SigV4 query-string (presign) canonical requests for S3 always use
    # UNSIGNED-PAYLOAD as the payload hash — see the module-level note and AWS's
    # published presign example. The actual request body (if any) is not hashed
    # at signing time; clients performing a PUT must send
    # `x-amz-content-sha256: UNSIGNED-PAYLOAD` on the upload.
    payload_hash = UNSIGNED_PAYLOAD
    canonical_request = "\n".join(
        [method, canonical_uri, canonical_query, canonical_headers, signed_headers, payload_hash]
    )

    string_to_sign = "\n".join(
        [ALGORITHM, amz_date, scope, _sha256_hex(canonical_request.encode("utf-8"))]
    )
    signing_key = _signing_key(cfg.s3_secret_key, date_stamp, cfg.s3_region)
    signature = hmac.new(signing_key, string_to_sign.encode("utf-8"), hashlib.sha256).hexdigest()

    return f"{url}?{canonical_query}&X-Amz-Signature={signature}"
