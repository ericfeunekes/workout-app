"""Migration runner. Applies numbered SQL files from server/db/migrations/.

Data layer — may depend on config and db; must not depend on api or sync.

See docs/MIGRATIONS.md for the full cutover philosophy. Migrations are append-only
and idempotent; the runner tracks applied files in a `schema_migrations` table.
"""

import logging
import sqlite3
from pathlib import Path

from sqlalchemy import Engine

logger = logging.getLogger(__name__)

_SERVER_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MIGRATIONS_DIR = _SERVER_ROOT / "db" / "migrations"


def apply_migrations(
    engine: Engine,
    migrations_dir: Path | None = None,
) -> list[str]:
    """Apply any pending migrations in filename order. Returns the names applied this run."""
    directory = migrations_dir or DEFAULT_MIGRATIONS_DIR
    applied: list[str] = []

    raw_conn = engine.raw_connection()
    try:
        cursor = raw_conn.cursor()
        cursor.execute(
            "CREATE TABLE IF NOT EXISTS schema_migrations ("
            "name TEXT PRIMARY KEY, applied_at TEXT NOT NULL)"
        )
        raw_conn.commit()

        cursor.execute("SELECT name FROM schema_migrations")
        already_applied = {row[0] for row in cursor.fetchall()}

        for path in sorted(directory.glob("*.sql")):
            if path.name in already_applied:
                continue
            sql = path.read_text()
            try:
                cursor.executescript(sql)
            except sqlite3.OperationalError as exc:
                message = str(exc).lower()
                if (
                    path.name != "010_primitive_distance_metric.sql"
                    or "duplicate column name: distance_m" not in message
                ):
                    raise
            cursor.execute(
                "INSERT INTO schema_migrations (name, applied_at) VALUES (?, datetime('now'))",
                (path.name,),
            )
            raw_conn.commit()
            applied.append(path.name)
            logger.info("Applied migration %s", path.name)
    finally:
        raw_conn.close()

    return applied
