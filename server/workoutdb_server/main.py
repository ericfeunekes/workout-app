"""FastAPI entry point.

Registers all routers, applies pending migrations on startup, installs structured
logging + request-id middleware. The actual route handlers live under
workoutdb_server.api.*.
"""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from sqlalchemy import text
from sqlalchemy.orm import Session

from workoutdb_server import __version__
from workoutdb_server.api import exercises, sync, user_parameters, version, workouts
from workoutdb_server.config import Settings, get_settings
from workoutdb_server.db import make_engine
from workoutdb_server.logging_setup import RequestIdMiddleware, configure_logging
from workoutdb_server.migrations import apply_migrations
from workoutdb_server.models import AppUser

_log = logging.getLogger(__name__)


def _ensure_app_user(engine, settings: Settings) -> None:
    """Bootstrap: the bearer token's user_id must exist as an app_user row.

    Idempotent. Called at startup so a fresh deploy doesn't 500 on the first
    request with "user not found." See ADR-2026-04-17 § "Multi-tenancy".
    """
    with Session(engine) as session:
        if session.get(AppUser, settings.user_id) is None:
            session.add(AppUser(id=settings.user_id, name=settings.user_name))
            session.commit()
            _log.info("created app_user %s (%s)", settings.user_id, settings.user_name)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    """Configure logging, apply migrations, and bootstrap the auth'd user."""
    settings = get_settings()
    configure_logging(debug=settings.debug)

    engine = make_engine(settings)
    applied = apply_migrations(engine)
    if applied:
        _log.info("applied migrations: %s", applied)
    else:
        _log.info("no pending migrations")
    _ensure_app_user(engine, settings)
    yield


app = FastAPI(title="WorkoutDB Home Server", version=__version__, lifespan=lifespan)
app.add_middleware(RequestIdMiddleware)


@app.get("/health", tags=["health"])
def health() -> dict[str, str]:
    """Liveness probe. Never touches the DB; use /health/ready for that."""
    return {"status": "ok"}


@app.get("/health/ready", tags=["health"])
def health_ready() -> dict[str, object]:
    """Deep readiness — actually touches the DB."""
    from sqlalchemy.orm import Session

    settings = get_settings()
    engine = make_engine(settings)
    with Session(engine) as session:
        rows = session.execute(text("SELECT name FROM schema_migrations ORDER BY name")).all()
    return {
        "status": "ok",
        "schema_version": rows[-1][0] if rows else None,
        "applied_migrations": [row[0] for row in rows],
    }


app.include_router(version.router)
app.include_router(exercises.router)
app.include_router(user_parameters.router)
app.include_router(workouts.router)
app.include_router(sync.router)
