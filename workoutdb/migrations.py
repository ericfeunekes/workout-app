from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from .db import connect, query, transaction


MIGRATIONS_DIR = Path(__file__).resolve().parent.parent / "db" / "migrations"


@dataclass(frozen=True)
class Migration:
    filename: str
    path: Path


def _list_migrations(migrations_dir: Path) -> list[Migration]:
    files = sorted(p for p in migrations_dir.glob("*.sql") if p.is_file())
    return [Migration(filename=p.name, path=p) for p in files]


def _ensure_schema_migrations(conn) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS schema_migrations (
            filename TEXT PRIMARY KEY,
            applied_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        """
    )


def _applied_migrations(conn) -> set[str]:
    rows = query(conn, "SELECT filename FROM schema_migrations")
    return {row["filename"] for row in rows}


def _iter_sql_statements(sql: str) -> list[str]:
    statements: list[str] = []
    buf: list[str] = []
    i = 0
    in_single = False
    in_double = False
    while i < len(sql):
        ch = sql[i]
        nxt = sql[i + 1] if i + 1 < len(sql) else ""

        if not in_single and not in_double:
            if ch == "-" and nxt == "-":
                while i < len(sql) and sql[i] != "\n":
                    i += 1
                continue
            if ch == "/" and nxt == "*":
                i += 2
                while i < len(sql) - 1 and not (sql[i] == "*" and sql[i + 1] == "/"):
                    i += 1
                i += 2
                continue

        if ch == "'" and not in_double:
            if in_single and nxt == "'":
                buf.append(ch)
                buf.append(nxt)
                i += 2
                continue
            in_single = not in_single
        elif ch == '"' and not in_single:
            if in_double and nxt == '"':
                buf.append(ch)
                buf.append(nxt)
                i += 2
                continue
            in_double = not in_double

        if ch == ";" and not in_single and not in_double:
            statement = "".join(buf).strip()
            if statement:
                statements.append(statement)
            buf.clear()
            i += 1
            continue

        buf.append(ch)
        i += 1

    tail = "".join(buf).strip()
    if tail:
        statements.append(tail)
    return statements


def apply_migrations(db_path: str | Path, migrations_dir: Path = MIGRATIONS_DIR) -> list[str]:
    migrations = _list_migrations(migrations_dir)
    applied: list[str] = []
    with connect(db_path) as conn:
        _ensure_schema_migrations(conn)
        already = _applied_migrations(conn)
        for migration in migrations:
            if migration.filename in already:
                continue
            sql = migration.path.read_text()
            with transaction(conn):
                for statement in _iter_sql_statements(sql):
                    conn.execute(statement)
                conn.execute(
                    "INSERT INTO schema_migrations (filename) VALUES (?)",
                    (migration.filename,),
                )
            applied.append(migration.filename)
    return applied


def pending_migrations(db_path: str | Path, migrations_dir: Path = MIGRATIONS_DIR) -> list[str]:
    migrations = _list_migrations(migrations_dir)
    with connect(db_path) as conn:
        _ensure_schema_migrations(conn)
        already = _applied_migrations(conn)
    return [m.filename for m in migrations if m.filename not in already]


def list_migrations(migrations_dir: Path = MIGRATIONS_DIR) -> Iterable[str]:
    return [m.filename for m in _list_migrations(migrations_dir)]
