"""FastAPI entry point.

Registers all routers, applies pending migrations on startup, installs structured
logging + request-id middleware. The actual route handlers live under
workoutdb_server.api.*.
"""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from sqlalchemy import text

from workoutdb_server import __version__
from workoutdb_server.api import exercises, sync, user_parameters, version, workouts
from workoutdb_server.config import get_settings
from workoutdb_server.db import make_engine
from workoutdb_server.logging_setup import RequestIdMiddleware, configure_logging
from workoutdb_server.migrations import apply_migrations

_log = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    """Configure logging, apply migrations before serving the first request."""
    settings = get_settings()
    configure_logging(debug=settings.debug)

    engine = make_engine(settings)
    applied = apply_migrations(engine)
    if applied:
        _log.info("applied migrations: %s", applied)
    else:
        _log.info("no pending migrations")
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
