"""Application configuration loaded from environment variables.

The cloud service NEVER stores journal bodies. It only brokers authentication,
issues short-lived object-storage credentials/presigned URLs scoped to a user
prefix, registers sync devices, and records sync logs.
"""
from __future__ import annotations

import os
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # --- Service ---
    app_name: str = "MyDiary Cloud"
    environment: str = "development"
    cors_origins: str = "http://localhost:1420,http://localhost:5173"

    # --- PostgreSQL ---
    database_url: str = "postgresql+psycopg://mydiary:mydiary@localhost:5432/mydiary"

    # --- Auth / JWT ---
    jwt_secret: str = "change-me-in-production"
    jwt_algorithm: str = "HS256"
    access_token_ttl_minutes: int = 60
    refresh_token_ttl_days: int = 30
    # Sync token: a long-lived, revocable credential bound to a device.
    sync_token_ttl_days: int = 365

    # --- Object storage (S3-compatible: S3 / R2 / MinIO / Aliyun OSS) ---
    # The cloud mints presigned URLs against THIS bucket using THESE credentials.
    # The client uploads/Downloads bodies directly to object storage; the cloud
    # only sees metadata + logs. Keys are namespaced per user: `<user_id>/...`.
    s3_endpoint: str = ""  # empty → default AWS S3
    s3_region: str = "us-east-1"
    s3_bucket: str = "mydiary"
    s3_access_key: str = ""
    s3_secret_key: str = ""
    # True for MinIO / Aliyun OSS path-style; False for AWS / R2 virtual-hosted.
    s3_path_style: bool = False
    s3_presign_ttl_seconds: int = 900  # 15 minutes for a single upload/download

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
