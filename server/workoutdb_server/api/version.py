"""GET /api/version — schema version handshake per docs/MIGRATIONS.md."""

from fastapi import APIRouter
from sqlalchemy import text

from workoutdb_server import __version__
from workoutdb_server.api.deps import Auth, DbSession
from workoutdb_server.api.schemas import VersionInfo

router = APIRouter(prefix="/api", tags=["version"])


@router.get("/version", response_model=VersionInfo, dependencies=[Auth])
def get_version(db: DbSession) -> VersionInfo:
    rows = db.execute(text("SELECT name FROM schema_migrations ORDER BY name")).all()
    applied = [row[0] for row in rows]
    return VersionInfo(
        schema_version=applied[-1] if applied else None,
        applied_migrations=applied,
        server_version=__version__,
    )
