"""Sync API: object-storage presigning + sync-log recording.

Guarantees per the data-ownership principle:
  * The cloud NEVER receives or stores journal bodies / asset bytes.
  * It only mints short-lived, user-scoped presigned URLs and records metadata.
  * Every object key is forced under the user's namespace `<user_id>/...`.
"""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..database import get_db
from ..deps import get_current_device
from ..config import get_settings
from ..models import SyncDevice, SyncLog
from ..schemas import (
    PresignItem,
    PresignRequest,
    PresignResponse,
    SyncLogCreate,
    SyncLogResponse,
)
from ..storage import presign_url

router = APIRouter(prefix="/sync", tags=["sync"])
_settings = get_settings()


def _namespace_key(user_id: uuid.UUID, key: str) -> str:
    """Force `key` under the user namespace and reject traversal."""
    cleaned = key.strip().lstrip("/")
    if not cleaned or ".." in cleaned.split("/") or cleaned.startswith("/"):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, f"Invalid key: {key!r}")
    return f"{user_id}/{cleaned}"


@router.post("/presign", response_model=PresignResponse)
def presign(body: PresignRequest, device: SyncDevice = Depends(get_current_device)) -> PresignResponse:
    method = "PUT" if body.op == "upload" else "GET"
    items: list[PresignItem] = []
    for key in body.keys:
        namespaced = _namespace_key(device.user_id, key)
        try:
            url = presign_url(_settings, namespaced, method, expires=900)
        except RuntimeError as exc:
            raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, str(exc))
        items.append(PresignItem(key=namespaced, url=url, method=method))
    return PresignResponse(items=items)


@router.post("/logs", response_model=SyncLogResponse, status_code=status.HTTP_201_CREATED)
def record_log(
    body: SyncLogCreate,
    device: SyncDevice = Depends(get_current_device),
    db: Session = Depends(get_db),
) -> SyncLogResponse:
    log = SyncLog(
        user_id=device.user_id,
        device_id=device.id,
        action=body.action,
        files_count=body.files_count,
        bytes_count=body.bytes_count,
        conflicts_count=body.conflicts_count,
        detail=body.detail,
    )
    db.add(log)
    db.commit()
    db.refresh(log)
    return SyncLogResponse(
        id=log.id,
        user_id=log.user_id,
        device_id=log.device_id,
        action=log.action,
        files_count=log.files_count,
        bytes_count=log.bytes_count,
        conflicts_count=log.conflicts_count,
        detail=log.detail,
        created_at=log.created_at,
    )


@router.get("/logs", response_model=list[SyncLogResponse])
def list_logs(
    limit: int = 50,
    device: SyncDevice = Depends(get_current_device),
    db: Session = Depends(get_db),
) -> list[SyncLogResponse]:
    limit = max(1, min(limit, 200))
    rows = db.scalars(
        select(SyncLog)
        .where(SyncLog.user_id == device.user_id)
        .order_by(SyncLog.created_at.desc())
        .limit(limit)
    ).all()
    return [
        SyncLogResponse(
            id=r.id,
            user_id=r.user_id,
            device_id=r.device_id,
            action=r.action,
            files_count=r.files_count,
            bytes_count=r.bytes_count,
            conflicts_count=r.conflicts_count,
            detail=r.detail,
            created_at=r.created_at,
        )
        for r in rows
    ]
