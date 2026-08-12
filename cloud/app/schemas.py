"""Pydantic schemas (request/response models)."""
from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, EmailStr, Field


# --------------------------------------------------------------------------- #
# Auth
# --------------------------------------------------------------------------- #
class UserCreate(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class RefreshRequest(BaseModel):
    refresh_token: str


class UserMe(BaseModel):
    id: uuid.UUID
    email: str
    is_active: bool
    created_at: datetime


# --------------------------------------------------------------------------- #
# Devices / sync tokens
# --------------------------------------------------------------------------- #
class DeviceRegister(BaseModel):
    name: str = Field(min_length=1, max_length=120)


class DeviceResponse(BaseModel):
    id: uuid.UUID
    name: str
    # Returned exactly once — the client must persist it securely.
    sync_token: str
    created_at: datetime


class DevicePublic(BaseModel):
    id: uuid.UUID
    name: str
    last_seen: datetime | None
    created_at: datetime


# --------------------------------------------------------------------------- #
# Object-storage presigning (no body ever touches this service)
# --------------------------------------------------------------------------- #
class PresignRequest(BaseModel):
    # Relative keys INSIDE the user's namespace, e.g. "entries/2026/08/2026-08-11.md".
    keys: list[str] = Field(min_length=1, max_length=100)
    # "upload" (PUT) or "download" (GET).
    op: str = Field(default="upload", pattern="^(upload|download)$")


class PresignItem(BaseModel):
    key: str
    url: str
    method: str


class PresignResponse(BaseModel):
    items: list[PresignItem]


# --------------------------------------------------------------------------- #
# Sync logs (metadata only)
# --------------------------------------------------------------------------- #
class SyncLogCreate(BaseModel):
    action: str = Field(default="sync", max_length=32)
    files_count: int = Field(default=0, ge=0)
    bytes_count: int = Field(default=0, ge=0)
    conflicts_count: int = Field(default=0, ge=0)
    detail: str | None = Field(default=None, max_length=2000)


class SyncLogResponse(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    device_id: uuid.UUID | None
    action: str
    files_count: int
    bytes_count: int
    conflicts_count: int
    detail: str | None
    created_at: datetime
