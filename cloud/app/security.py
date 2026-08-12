"""Security primitives: password hashing, JWT, and sync tokens.

Sync tokens are device-scoped, long-lived, and revocable. We store only a
SHA-256 hash of the token (the raw token is shown to the client exactly once,
like an API key). This keeps credentials safe even if the database leaks.
"""
from __future__ import annotations

import hashlib
import secrets
import uuid
from datetime import datetime, timedelta, timezone

from jose import JWTError, jwt
from passlib.context import CryptContext

from .config import get_settings

settings = get_settings()

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

ACCESS_AUD = "access"
REFRESH_AUD = "refresh"
SYNC_AUD = "sync"


# --------------------------------------------------------------------------- #
# Passwords
# --------------------------------------------------------------------------- #
def hash_password(plain: str) -> str:
    return pwd_context.hash(plain)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


# --------------------------------------------------------------------------- #
# JWT
# --------------------------------------------------------------------------- #
def _now() -> datetime:
    return datetime.now(timezone.utc)


def create_access_token(subject: str) -> str:
    expire = _now() + timedelta(minutes=settings.access_token_ttl_minutes)
    payload = {"sub": subject, "aud": ACCESS_AUD, "exp": expire, "iat": _now()}
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def create_refresh_token(subject: str) -> str:
    expire = _now() + timedelta(days=settings.refresh_token_ttl_days)
    payload = {"sub": subject, "aud": REFRESH_AUD, "exp": expire, "iat": _now()}
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_token(token: str, expected_aud: str) -> str | None:
    """Return the subject (`sub`) if the token is valid for `expected_aud`."""
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret,
            algorithms=[settings.jwt_algorithm],
            audience=expected_aud,
        )
    except JWTError:
        return None
    sub = payload.get("sub")
    return str(sub) if isinstance(sub, str) else None


# --------------------------------------------------------------------------- #
# Sync tokens (device-scoped API credentials)
# --------------------------------------------------------------------------- #
def generate_sync_token() -> str:
    """Raw token revealed to the client exactly once."""
    return f"sync_{uuid.uuid4().hex}{secrets.token_urlsafe(32)}"


def hash_sync_token(raw: str) -> str:
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def verify_sync_token(raw: str, stored_hash: str) -> bool:
    return secrets.compare_digest(hash_sync_token(raw), stored_hash)
