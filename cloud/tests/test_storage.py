"""Unit test for the hand-rolled SigV4 presigner.

Verifies against AWS's published "GET Object" presigned-URL example:
https://docs.aws.amazon.com/AmazonS3/latest/developerguide/sigv4-query-string-auth.html
Canonical request hash : 3bfa292879f6447bbcda7001decf97f4a54dc650c8942174ae0a9121cf58ad04
Expected signature      : aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404

Run:  python -m pytest tests/   (or just: python tests/test_storage.py)
"""
from __future__ import annotations

import sys
import types
import unittest.mock
import urllib.parse
from datetime import datetime, timezone
from pathlib import Path

# Allow running as a plain script: import the storage module without the package.
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import app.storage as st
from app.storage import presign_url  # noqa: E402

# AWS's example pins the timestamp to Fri, 24 May 2013 00:00:00 GMT so its
# published signature is reproducible. We pin the same instant for the test.
_FIXED_NOW = datetime(2013, 5, 24, 0, 0, 0, tzinfo=timezone.utc)


class _FixedDateTime:
    @staticmethod
    def now(_=None):
        return _FIXED_NOW


def _fake_cfg() -> types.SimpleNamespace:
    return types.SimpleNamespace(
        s3_endpoint="",
        s3_region="us-east-1",
        s3_bucket="examplebucket",
        s3_access_key="AKIAIOSFODNN7EXAMPLE",
        s3_secret_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        s3_path_style=False,
    )


def _expected_canonical_request() -> str:
    # From the AWS documentation example (GET, expires 86400). The payload hash
    # for an S3 presigned URL is always the literal UNSIGNED-PAYLOAD.
    return "\n".join(
        [
            "GET",
            "/test.txt",
            "X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20130524%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20130524T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host",
            "host:examplebucket.s3.amazonaws.com",
            "host",
            "UNSIGNED-PAYLOAD",
        ]
    )


def test_aws_published_vector():
    with unittest.mock.patch.object(st, "datetime", _FixedDateTime):
        url = presign_url(_fake_cfg(), "test.txt", "GET", expires=86400)
    qs = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(url).query))
    assert qs["X-Amz-Signature"] == (
        "aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404"
    ), f"signature mismatch: {qs.get('X-Amz-Signature')}"
    assert qs["X-Amz-Credential"].startswith(
        "AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request"
    )
    assert qs["X-Amz-Expires"] == "86400"
    assert urllib.parse.urlparse(url).netloc == "examplebucket.s3.amazonaws.com"
    print("  ✓ AWS published SigV4 presign vector matches")


def test_credential_slashes_are_encoded():
    with unittest.mock.patch.object(st, "datetime", _FixedDateTime):
        raw = presign_url(_fake_cfg(), "a/b/c.md", "PUT", 900)
    query = urllib.parse.urlparse(raw).query
    # In the *transmitted* URL the credential scope slashes must be encoded as
    # %2F (SigV4 requires this). After parse_qsl decodes them, the credential
    # must round-trip back to its canonical unencoded form.
    assert "%2F" in query
    qs = dict(urllib.parse.parse_qsl(query))
    assert qs["X-Amz-Credential"] == "AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request"
    print("  ✓ credential scope slashes are percent-encoded")


if __name__ == "__main__":
    test_aws_published_vector()
    test_credential_slashes_are_encoded()
    print("\nALL PASS")
