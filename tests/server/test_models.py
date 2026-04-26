"""Unit tests for the ORM models — round-trip, relationships, cascade deletes, FK enforcement."""

from datetime import datetime
from pathlib import Path

import pytest
from sqlalchemy import create_engine, event
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from workoutdb_server.migrations import apply_migrations
from workoutdb_server.models import (
    AppUser,
    Block,
    Exercise,
    ExerciseAlternative,
    SetLog,
    UserParameter,
    Workout,
    WorkoutItem,
)


@pytest.fixture
def session(tmp_path: Path):
    engine = create_engine(f"sqlite:///{tmp_path / 'test.db'}", future=True)

    # Enable FK enforcement on every connection — matches the real db.py wiring.
    @event.listens_for(engine, "connect")
    def _pragma(dbapi_conn, _record):
        cursor = dbapi_conn.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()

    apply_migrations(engine)
    with Session(engine) as s:
        yield s
    engine.dispose()


# Canonical test UUIDs. Per docs/specs/v2-architecture.md, all entity ids are UUIDs.
_BACK_SQUAT = "e0000001-0000-4000-8000-000000000001"
_FRONT_SQUAT = "e0000002-0000-4000-8000-000000000002"
_NONEXISTENT_WORKOUT = "00000000-0000-4000-8000-000000000000"


def _seed_user_and_exercise(session: Session) -> tuple[AppUser, Exercise]:
    user = AppUser(name="Eric")
    exercise = Exercise(id=_BACK_SQUAT, name="Back Squat")
    session.add_all([user, exercise])
    session.commit()
    return user, exercise


def test_full_round_trip(session: Session) -> None:
    user, exercise = _seed_user_and_exercise(session)

    workout = Workout(
        user_id=user.id,
        name="Tuesday Legs",
        status="planned",
        source="claude",
        tags_json='["hypertrophy_block_2", "week_3"]',
    )
    session.add(workout)
    session.flush()

    block = Block(
        workout_id=workout.id,
        position=0,
        name="Main",
        timing_mode="straight_sets",
        timing_config_json='{"rest_between_sets_sec": 180}',
        intent="Keep bar speed high",
    )
    session.add(block)
    session.flush()

    item = WorkoutItem(
        block_id=block.id,
        position=0,
        exercise_id=exercise.id,
        prescription_json='{"sets": 5, "reps": 5, "load_kg": 100}',
    )
    session.add(item)
    session.flush()

    alt_exercise = Exercise(id=_FRONT_SQUAT, name="Front Squat")
    session.add(alt_exercise)
    session.flush()

    alt = ExerciseAlternative(
        workout_item_id=item.id,
        exercise_id=alt_exercise.id,
        reason="bar taken",
    )
    session.add(alt)

    log = SetLog(
        workout_item_id=item.id,
        set_index=1,
        reps=5,
        weight=100.0,
        weight_unit="kg",
        rir=2,
        is_warmup=False,
        completed_at=datetime(2026, 4, 17, 7, 30),
        hr_avg_bpm=142,
        hr_max_bpm=168,
        skipped=True,
        side="right",
    )
    session.add(log)
    session.commit()

    fetched = session.get(Workout, workout.id)
    assert fetched is not None
    assert fetched.name == "Tuesday Legs"
    assert len(fetched.blocks) == 1
    assert fetched.blocks[0].workout_items[0].exercise.name == "Back Squat"
    assert fetched.blocks[0].intent == "Keep bar speed high"
    assert fetched.blocks[0].workout_items[0].alternatives[0].reason == "bar taken"
    assert fetched.blocks[0].workout_items[0].set_logs[0].weight == 100.0
    assert fetched.blocks[0].workout_items[0].set_logs[0].skipped is True
    assert fetched.blocks[0].workout_items[0].set_logs[0].side == "right"


def test_cascade_delete_workout(session: Session) -> None:
    user, exercise = _seed_user_and_exercise(session)
    workout = Workout(user_id=user.id, name="W", status="planned", source="claude")
    session.add(workout)
    session.flush()
    block = Block(
        workout_id=workout.id,
        position=0,
        timing_mode="straight_sets",
        timing_config_json="{}",
    )
    session.add(block)
    session.flush()
    item = WorkoutItem(
        block_id=block.id, position=0, exercise_id=exercise.id, prescription_json="{}"
    )
    session.add(item)
    session.commit()

    session.delete(workout)
    session.commit()

    assert session.query(Block).count() == 0
    assert session.query(WorkoutItem).count() == 0


def test_nested_blocks(session: Session) -> None:
    user, _ = _seed_user_and_exercise(session)
    workout = Workout(user_id=user.id, name="W", status="planned", source="claude")
    session.add(workout)
    session.flush()

    outer = Block(
        workout_id=workout.id,
        position=0,
        timing_mode="circuit",
        timing_config_json='{"rounds": 3}',
    )
    session.add(outer)
    session.flush()

    inner = Block(
        workout_id=workout.id,
        parent_block_id=outer.id,
        position=0,
        timing_mode="straight_sets",
        timing_config_json="{}",
    )
    session.add(inner)
    session.commit()

    assert len(outer.children) == 1
    assert outer.children[0].parent is outer


def test_user_parameters_append_only(session: Session) -> None:
    user, _ = _seed_user_and_exercise(session)

    session.add(
        UserParameter(
            user_id=user.id,
            key="bodyweight_kg",
            value="82.0",
            updated_at=datetime(2026, 4, 10),
            source="claude",
        )
    )
    session.add(
        UserParameter(
            user_id=user.id,
            key="bodyweight_kg",
            value="81.5",
            updated_at=datetime(2026, 4, 17),
            source="claude",
        )
    )
    session.commit()

    rows = (
        session.query(UserParameter)
        .filter_by(user_id=user.id, key="bodyweight_kg")
        .order_by(UserParameter.updated_at)
        .all()
    )
    assert len(rows) == 2
    assert [r.value for r in rows] == ["82.0", "81.5"]


def test_foreign_key_enforcement(session: Session) -> None:
    # block.workout_id references a nonexistent workout → FK violation.
    bad = Block(
        workout_id=_NONEXISTENT_WORKOUT,
        position=0,
        timing_mode="straight_sets",
        timing_config_json="{}",
    )
    session.add(bad)
    with pytest.raises(IntegrityError):
        session.commit()


def test_status_check_constraint(session: Session) -> None:
    user, _ = _seed_user_and_exercise(session)
    bad = Workout(user_id=user.id, name="W", status="invalid", source="claude")
    session.add(bad)
    with pytest.raises(IntegrityError):
        session.commit()
