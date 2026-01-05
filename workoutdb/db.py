from __future__ import annotations

import contextlib
import uuid
import sqlite3
from pathlib import Path
from typing import Iterable, Iterator, Sequence


Connection = sqlite3.Connection


def connect(db_path: str | Path) -> Connection:
    path = Path(db_path)
    conn = sqlite3.connect(path)
    conn.isolation_level = None  # Disable implicit transactions
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def execute(conn: Connection, sql: str, params: Sequence | None = None) -> None:
    if params is None:
        conn.execute(sql)
    else:
        conn.execute(sql, params)


def executemany(conn: Connection, sql: str, params: Iterable[Sequence]) -> None:
    conn.executemany(sql, params)


def query(conn: Connection, sql: str, params: Sequence | None = None) -> list[sqlite3.Row]:
    if params is None:
        cursor = conn.execute(sql)
    else:
        cursor = conn.execute(sql, params)
    return list(cursor.fetchall())


@contextlib.contextmanager
def transaction(conn: Connection) -> Iterator[None]:
    if conn.in_transaction:
        savepoint = f"sp_{uuid.uuid4().hex}"
        conn.execute(f"SAVEPOINT {savepoint}")
        try:
            yield
        except Exception:
            conn.execute(f"ROLLBACK TO SAVEPOINT {savepoint}")
            conn.execute(f"RELEASE SAVEPOINT {savepoint}")
            raise
        else:
            conn.execute(f"RELEASE SAVEPOINT {savepoint}")
        return
    try:
        conn.execute("BEGIN")
        yield
    except Exception:
        conn.execute("ROLLBACK")
        raise
    else:
        conn.execute("COMMIT")
