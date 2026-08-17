"""SQLAlchemy models.

Deliberate scope: authentication, sync devices, and sync metadata ONLY.
No journal text, no asset bytes — those live in object storage, referenced by key.
"""
from __future__ import annotations

import uuid
from datetime import datetime, timezone

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    is_active: Mapped[bool] = mapped_column(default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow, nullable=False)

    devices: Mapped[list["SyncDevice"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )


class SyncDevice(Base):
    """A registered client device. Holds a SHA-256 hash of its sync token."""

    __tablename__ = "sync_devices"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    # Raw token shown once; only its hash is persisted.
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True, nullable=False)
    last_seen: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_utcnow, nullable=False)

    user: Mapped["User"] = relationship(back_populates="devices")


class SyncLog(Base):
    """Metadata-only record of a sync run. Never references body content."""

    __tablename__ = "sync_logs"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    device_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("sync_devices.id", ondelete="SET NULL"), index=True, nullable=True
    )
    action: Mapped[str] = mapped_column(String(32), nullable=False)  # "sync" | "conflict" | ...
    files_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    bytes_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    conflicts_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    # Free-form summary (counts, not content), capped to keep rows small.
    detail: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), default=_utcnow, nullable=False
    )
