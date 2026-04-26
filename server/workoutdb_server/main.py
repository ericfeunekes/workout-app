"""FastAPI entry point.

Registers all routers, applies pending migrations on startup, installs structured
logging + request-id middleware. The actual route handlers live under
workoutdb_server.api.*.
"""

import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from sqlalchemy import text
from sqlalchemy.orm import Session

from workoutdb_server import __version__
from workoutdb_server.api import (
    exercises,
    sync,
    telemetry,
    user_parameters,
    version,
    workouts,
)
from workoutdb_server.config import Settings, get_settings
from workoutdb_server.db import make_engine
from workoutdb_server.logging_setup import RequestIdMiddleware, configure_logging
from workoutdb_server.migrations import apply_migrations
from workoutdb_server.models import AppUser
from workoutdb_server.sync.event_log_retention import prune_event_log

_log = logging.getLogger(__name__)

# Periodic sweep interval: a fresh prune once per day is plenty for a
# single-user home server. Module-level so tests can monkey-patch it.
_PERIODIC_SWEEP_INTERVAL_SEC = 86400


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


def _sweep_event_log(engine, settings: Settings) -> None:
    """Prune stale `event_log` rows.

    Called once at startup and then again from `_periodic_sweep` on a timer —
    between the two, the table stays bounded even when the process runs for
    weeks. No cron, no admin endpoint, no external scheduler. See
    `workoutdb_server.sync.event_log_retention`.
    """
    with Session(engine) as session:
        deleted = prune_event_log(session, settings.event_log_retention_days)
    if deleted:
        _log.info(
            "event_log retention sweep: pruned %s rows older than %s days",
            deleted,
            settings.event_log_retention_days,
        )


async def _periodic_sweep(engine, settings: Settings) -> None:
    """Run `_sweep_event_log` on a daily tick.

    Sleeps first so the startup sweep in `lifespan` isn't immediately doubled
    up. Exceptions are logged and swallowed — retention is maintenance, not
    load-bearing, and a transient DB error must not take the task down.
    Cancellation (during shutdown) unwinds cleanly via `CancelledError`.
    """
    while True:
        try:
            await asyncio.sleep(_PERIODIC_SWEEP_INTERVAL_SEC)
        except asyncio.CancelledError:
            raise
        try:
            _sweep_event_log(engine, settings)
        except asyncio.CancelledError:
            raise
        except Exception:
            _log.warning("periodic event_log sweep failed", exc_info=True)


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

    # Retention sweep at startup: log and swallow any error — retention is
    # maintenance, not a startup prerequisite, and a sweep failure must not
    # prevent the server from accepting traffic.
    try:
        _sweep_event_log(engine, settings)
    except Exception:
        _log.warning("startup event_log sweep failed", exc_info=True)

    sweep_task = asyncio.create_task(_periodic_sweep(engine, settings))
    try:
        yield
    finally:
        sweep_task.cancel()
        try:
            await sweep_task
        except asyncio.CancelledError:
            pass


app = FastAPI(title="Setmark Home Server", version=__version__, lifespan=lifespan)
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
app.include_router(telemetry.router)
