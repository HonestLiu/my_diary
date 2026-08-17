"""Authentication & device/sync-token management."""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..database import get_db
from ..deps import get_current_user
from ..models import SyncDevice, User
from ..schemas import (
    DevicePublic,
    DeviceRegister,
    DeviceResponse,
    RefreshRequest,
    TokenResponse,
    UserCreate,
    UserLogin,
    UserMe,
)
from ..security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    generate_sync_token,
    hash_password,
    hash_sync_token,
    verify_password,
)

router = APIRouter(prefix="/auth", tags=["auth"])


def _tokens(user: User) -> TokenResponse:
    return TokenResponse(
        access_token=create_access_token(str(user.id)),
        refresh_token=create_refresh_token(str(user.id)),
    )


def _register_device(db: Session, user: User, name: str) -> DeviceResponse:
    raw = generate_sync_token()
    device = SyncDevice(user_id=user.id, name=name, token_hash=hash_sync_token(raw))
    db.add(device)
    db.commit()
    db.refresh(device)
    return DeviceResponse(
        id=device.id, name=device.name, sync_token=raw, created_at=device.created_at
    )


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
def register(body: UserCreate, db: Session = Depends(get_db)) -> TokenResponse:
    existing = db.scalar(select(User).where(User.email == body.email))
    if existing is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "Email already registered")
    user = User(email=body.email, password_hash=hash_password(body.password))
    db.add(user)
    db.commit()
    db.refresh(user)
    # Auto-provision a first device so the client can sync immediately.
    _register_device(db, user, "default")
    return _tokens(user)


@router.post("/login", response_model=TokenResponse)
def login(body: UserLogin, db: Session = Depends(get_db)) -> TokenResponse:
    user = db.scalar(select(User).where(User.email == body.email))
    if user is None or not verify_password(body.password, user.password_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid email or password")
    if not user.is_active:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Account disabled")
    return _tokens(user)


@router.post("/refresh", response_model=TokenResponse)
def refresh(body: RefreshRequest, db: Session = Depends(get_db)) -> TokenResponse:
    subject = decode_token(body.refresh_token, "refresh")
    if subject is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid refresh token")
    user = db.get(User, uuid.UUID(subject))
    if user is None or not user.is_active:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Account disabled")
    # Rotate the refresh token on use.
    return _tokens(user)


@router.get("/me", response_model=UserMe)
def me(user: User = Depends(get_current_user)) -> UserMe:
    return UserMe(
        id=user.id, email=user.email, is_active=user.is_active, created_at=user.created_at
    )


@router.post("/devices", response_model=DeviceResponse, status_code=status.HTTP_201_CREATED)
def create_device(
    body: DeviceRegister,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> DeviceResponse:
    return _register_device(db, user, body.name)


@router.get("/devices", response_model=list[DevicePublic])
def list_devices(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[DevicePublic]:
    devices = db.scalars(select(SyncDevice).where(SyncDevice.user_id == user.id)).all()
    return [
        DevicePublic(
            id=d.id, name=d.name, last_seen=d.last_seen, created_at=d.created_at
        )
        for d in devices
    ]
