"""Shared FastAPI dependencies: current user (JWT) and current device (sync token)."""
from __future__ import annotations

import hashlib
import uuid
from datetime import datetime, timezone

from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from .database import get_db
from .models import SyncDevice, User
from .security import decode_token

bearer_scheme = HTTPBearer(auto_error=False)


def get_current_user(
    creds: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    if creds is None or not creds.credentials:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Missing bearer token")
    subject = decode_token(creds.credentials, "access")
    if subject is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid or expired token")
    user = db.get(User, uuid.UUID(subject))
    if user is None or not user.is_active:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "User not found or inactive")
    return user


def get_current_device(
    x_sync_token: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> SyncDevice:
    """Authenticate a sync request using a device sync token (header `X-Sync-Token`)."""
    if not x_sync_token:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Missing X-Sync-Token header")
    token_hash = hashlib.sha256(x_sync_token.encode("utf-8")).hexdigest()
    device = db.query(SyncDevice).filter(SyncDevice.token_hash == token_hash).first()
    if device is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid sync token")
    user = db.get(User, device.user_id)
    if user is None or not user.is_active:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Device owner inactive")
    device.last_seen = datetime.now(timezone.utc)
    db.add(device)
    db.commit()
    return device
