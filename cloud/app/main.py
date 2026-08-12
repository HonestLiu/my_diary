"""MyDiary Cloud — FastAPI entrypoint.

A thin, stateless authority that:
  * authenticates users (JWT) and provisions device-scoped sync tokens,
  * mints short-lived, user-namespaced presigned URLs for S3-compatible storage,
  * records sync metadata (never journal bodies).

Run locally:  uvicorn app.main:app --reload
With Docker:  docker compose up
"""
from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import get_settings
from .database import Base, engine
from .routers import auth, health, sync

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Dev convenience: create tables on boot. In production use Alembic migrations.
    if settings.environment != "production":
        Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(title=settings.app_name, version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(auth.router)
app.include_router(sync.router)


@app.get("/")
def root() -> dict[str, str]:
    return {"service": settings.app_name, "docs": "/docs"}
