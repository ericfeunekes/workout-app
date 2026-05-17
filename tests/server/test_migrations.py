"""Unit tests for the migration runner."""

from pathlib import Path

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session
from workoutdb_server.migrations import apply_migrations


@pytest.fixture
def tmp_engine(tmp_path: Path):
    engine = create_engine(f"sqlite:///{tmp_path / 'test.db'}", future=True)
    yield engine
    engine.dispose()


def test_applies_initial_migration(tmp_engine) -> None:
    applied = apply_migrations(tmp_engine)

    assert "001_initial.sql" in applied

    with Session(tmp_engine) as session:
        tables = {
            row[0]
            for row in session.execute(
                text("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
            )
        }

    expected = {
        "app_user",
        "block",
        "exercise",
        "exercise_alternative",
        "schema_migrations",
        "set_log",
        "user_parameters",
        "workout",
        "workout_item",
    }
    assert expected.issubset(tables)


def test_migrations_idempotent(tmp_engine) -> None:
    first = apply_migrations(tmp_engine)
    second = apply_migrations(tmp_engine)

    # All checked-in migrations should apply on first call, none on second.
    assert "001_initial.sql" in first
    assert second == []


def test_duplicate_column_replay_is_recorded_as_applied(tmp_engine, tmp_path: Path) -> None:
    custom_dir = tmp_path / "mig"
    custom_dir.mkdir()
    (custom_dir / "010_primitive_distance_metric.sql").write_text(
        "ALTER TABLE primitive_set_log ADD COLUMN distance_m REAL;"
    )

    with Session(tmp_engine) as session:
        session.execute(
            text("CREATE TABLE primitive_set_log (id TEXT PRIMARY KEY, distance_m REAL)")
        )
        session.commit()

    applied = apply_migrations(tmp_engine, migrations_dir=custom_dir)

    assert applied == ["010_primitive_distance_metric.sql"]
    with Session(tmp_engine) as session:
        rows = session.execute(text("SELECT name FROM schema_migrations")).fetchall()
    assert rows == [("010_primitive_distance_metric.sql",)]


def test_schema_2026_04_26_columns_have_defaults(tmp_engine) -> None:
    apply_migrations(tmp_engine)

    with Session(tmp_engine) as session:
        set_log_columns = {
            row[1]: row for row in session.execute(text("PRAGMA table_info(set_log)")).fetchall()
        }
        block_columns = {
            row[1]: row for row in session.execute(text("PRAGMA table_info(block)")).fetchall()
        }

    assert set_log_columns["skipped"][3] == 1
    assert set_log_columns["skipped"][4] == "0"
    assert set_log_columns["side"][3] == 1
    assert set_log_columns["side"][4] == "'bilateral'"
    assert "intent" in block_columns
    assert block_columns["intent"][3] == 0


def test_schema_migrations_records_applied(tmp_engine) -> None:
    applied = apply_migrations(tmp_engine)

    with Session(tmp_engine) as session:
        rows = session.execute(text("SELECT name FROM schema_migrations ORDER BY name")).fetchall()

    assert [row[0] for row in rows] == applied


def test_apply_custom_directory(tmp_engine, tmp_path: Path) -> None:
    custom_dir = tmp_path / "mig"
    custom_dir.mkdir()
    (custom_dir / "001_noop.sql").write_text("CREATE TABLE noop (id TEXT PRIMARY KEY);")

    applied = apply_migrations(tmp_engine, migrations_dir=custom_dir)

    assert applied == ["001_noop.sql"]
    with Session(tmp_engine) as session:
        tables = {
            row[0]
            for row in session.execute(text("SELECT name FROM sqlite_master WHERE type='table'"))
        }
    assert "noop" in tables
