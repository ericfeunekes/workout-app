from __future__ import annotations

from pathlib import Path

import pytest

from workoutdb.migrations import apply_migrations


@pytest.fixture()
def db_path(tmp_path: Path) -> Path:
    path = tmp_path / "workout.db"
    apply_migrations(path)
    return path
