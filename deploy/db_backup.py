"""Online SQLite backup helper.

Uses the sqlite3 stdlib `.backup()` method (the SQLite online backup API). Safe to run
while the server is reading/writing the DB — SQLite takes a consistent snapshot without
blocking writers for long. See https://www.sqlite.org/backup.html.

Usage:
    python deploy/db_backup.py <source-db-path> <dest-file>

Invoked by `make db-backup` which resolves paths from .env ($WORKOUTDB_DB_PATH) and
timestamps the destination under ./backups/.
"""

from __future__ import annotations

import sqlite3
import sys
from pathlib import Path


def backup(src: Path, dst: Path) -> None:
    if not src.exists():
        raise SystemExit(f"source DB not found: {src}")
    dst.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(src) as src_conn, sqlite3.connect(dst) as dst_conn:
        src_conn.backup(dst_conn)
    print(f"backed up {src} -> {dst} ({dst.stat().st_size} bytes)")


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    backup(Path(argv[1]), Path(argv[2]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
