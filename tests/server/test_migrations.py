"""Unit tests for the migration runner."""

from pathlib import Path
from shutil import copy2

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session
from workoutdb_server.migrations import apply_migrations

MIGRATIONS_DIR = Path(__file__).resolve().parents[2] / "server" / "db" / "migrations"


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


def test_primitive_reset_migration_clears_execution_state_only(tmp_engine, tmp_path: Path) -> None:
    staged_dir = tmp_path / "migrations"
    staged_dir.mkdir()
    for path in sorted(MIGRATIONS_DIR.glob("*.sql")):
        if path.name <= "010_primitive_distance_metric.sql":
            copy2(path, staged_dir / path.name)

    apply_migrations(tmp_engine, migrations_dir=staged_dir)

    timestamp = "2026-05-18T12:00:00Z"
    ids = {
        "user_id": "00000000-0000-4000-8000-000000000001",
        "exercise_id": "00000000-0000-4000-8000-000000000002",
        "workout_id": "00000000-0000-4000-8000-000000000003",
        "block_id": "00000000-0000-4000-8000-000000000004",
        "item_id": "00000000-0000-4000-8000-000000000005",
        "alternative_id": "00000000-0000-4000-8000-000000000006",
        "set_log_id": "00000000-0000-4000-8000-000000000007",
        "primitive_log_id": "00000000-0000-4000-8000-000000000008",
        "parameter_id": "00000000-0000-4000-8000-000000000009",
    }
    with Session(tmp_engine) as session:
        session.execute(
            text("INSERT INTO app_user (id, name, created_at) VALUES (:id, :name, :at)"),
            {"id": ids["user_id"], "name": "Eric", "at": timestamp},
        )
        session.execute(
            text("INSERT INTO exercise (id, name) VALUES (:id, :name)"),
            {"id": ids["exercise_id"], "name": "Bench"},
        )
        session.execute(
            text(
                """
                INSERT INTO workout (
                    id, user_id, name, scheduled_date, status, source, created_at, updated_at
                )
                VALUES (:id, :user_id, :name, :scheduled, 'planned', 'claude', :at, :at)
                """
            ),
            {
                "id": ids["workout_id"],
                "user_id": ids["user_id"],
                "name": "Legacy workout",
                "scheduled": "2026-05-18",
                "at": timestamp,
            },
        )
        session.execute(
            text(
                """
                INSERT INTO block (id, workout_id, position, timing_mode, timing_config_json)
                VALUES (:id, :workout_id, 0, 'straight_sets', '{}')
                """
            ),
            {"id": ids["block_id"], "workout_id": ids["workout_id"]},
        )
        session.execute(
            text(
                """
                INSERT INTO workout_item (id, block_id, position, exercise_id, prescription_json)
                VALUES (:id, :block_id, 0, :exercise_id, '{}')
                """
            ),
            {
                "id": ids["item_id"],
                "block_id": ids["block_id"],
                "exercise_id": ids["exercise_id"],
            },
        )
        session.execute(
            text(
                """
                INSERT INTO exercise_alternative (id, workout_item_id, exercise_id, reason)
                VALUES (:id, :item_id, :exercise_id, 'qa')
                """
            ),
            {
                "id": ids["alternative_id"],
                "item_id": ids["item_id"],
                "exercise_id": ids["exercise_id"],
            },
        )
        session.execute(
            text(
                """
                INSERT INTO set_log (
                    id, workout_item_id, set_index, reps, completed_at, rir
                )
                VALUES (:id, :item_id, 1, 5, :at, 2)
                """
            ),
            {"id": ids["set_log_id"], "item_id": ids["item_id"], "at": timestamp},
        )
        session.execute(
            text(
                """
                INSERT INTO primitive_set_log (
                    id, role, slot_id, workout_id, planned_exercise_id, set_index,
                    set_repeat_index, block_repeat_index, reps, completed_at
                )
                VALUES (
                    :id, 'slot', :slot_id, :workout_id, :exercise_id, 0, 0, 0, 5, :at
                )
                """
            ),
            {
                "id": ids["primitive_log_id"],
                "slot_id": ids["item_id"],
                "workout_id": ids["workout_id"],
                "exercise_id": ids["exercise_id"],
                "at": timestamp,
            },
        )
        session.execute(
            text(
                """
                INSERT INTO user_parameters (id, user_id, key, value, updated_at, source)
                VALUES (:id, :user_id, 'bodyweight_kg', '90', :at, 'manual')
                """
            ),
            {"id": ids["parameter_id"], "user_id": ids["user_id"], "at": timestamp},
        )
        session.commit()

    copy2(
        MIGRATIONS_DIR / "011_primitive_only_reset.sql",
        staged_dir / "011_primitive_only_reset.sql",
    )
    applied = apply_migrations(tmp_engine, migrations_dir=staged_dir)

    assert applied == ["011_primitive_only_reset.sql"]
    with Session(tmp_engine) as session:
        cleared_tables = [
            "set_log",
            "exercise_alternative",
            "workout_item",
            "block",
            "primitive_set_log",
            "workout",
        ]
        for table in cleared_tables:
            count = session.execute(text(f"SELECT COUNT(*) FROM {table}")).scalar_one()
            assert count == 0, table

        preserved_tables = ["app_user", "exercise", "user_parameters"]
        for table in preserved_tables:
            count = session.execute(text(f"SELECT COUNT(*) FROM {table}")).scalar_one()
            assert count == 1, table
