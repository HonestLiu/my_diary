"""SQLAlchemy engine / session wiring.

NOTE: This database holds ONLY authentication, device, and sync-metadata state.
Journal bodies are never written here — they live in object storage and are
addressed by key. See `storage.py` and the sync routers.
"""
from __future__ import annotations

from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from .config import get_settings

settings = get_settings()

# `connect_args` pool pre-ping keeps long-lived workers healthy behind Postgres.
engine = create_engine(
    settings.database_url,
    pool_pre_ping=True,
    future=True,
)

SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False, future=True)


class Base(DeclarativeBase):
    pass


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
