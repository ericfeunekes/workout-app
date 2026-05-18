"""Performance regression tests — pin expected query counts.

These are not load tests. They count emitted queries on representative paths so a
future change that reintroduces N+1 fails the build.
"""

from __future__ import annotations

import json
from datetime import datetime

from sqlalchemy import event
from sqlalchemy.orm import Session
from workoutdb_server.models import (
    Block,
    Exercise,
    SetLog,
    Workout,
    WorkoutItem,
)


class QueryCounter:
    def __init__(self) -> None:
        self.count = 0

    def __call__(self, *_args, **_kwargs) -> None:
        self.count += 1


def _seed_workout_with_exercises(engine, user_id: str, n_exercises: int = 5) -> list[str]:
    """Seed a completed workout that has N exercises, each with 3 set_logs."""
    with Session(engine) as session:
        exercise_ids: list[str] = []

        def _uuid(suffix: int) -> str:
            return f"00000000-0000-4000-8000-{suffix:012d}"

        def _primitive_blocks(exercise_ids: list[str]) -> str:
            return json.dumps(
                [
                    {
                        "id": _uuid(90_000),
                        "sets": [
                            {
                                "id": _uuid(91_000),
                                "timing": {"mode": "set_bounded"},
                                "traversal": "sequential",
                                "slots": [
                                    {
                                        "id": _uuid(92_000 + i),
                                        "exercise_id": exercise_id,
                                        "work_target": [
                                            {
                                                "metric": "reps",
                                                "value_form": "single",
                                                "value": 5,
                                                "role": "completion",
                                            }
                                        ],
                                    }
                                    for i, exercise_id in enumerate(exercise_ids)
                                ],
                            }
                        ],
                    }
                ]
            )

        workout = Workout(
            user_id=user_id,
            name="Past",
            status="completed",
            source="claude",
            completed_at=datetime(2026, 4, 10, 7),
        )
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

        for i in range(n_exercises):
            exercise = Exercise(id=_uuid(i + 1), name=f"Exercise {i}")
            session.add(exercise)
            exercise_ids.append(exercise.id)
            item = WorkoutItem(
                block_id=block.id,
                position=i,
                exercise_id=exercise.id,
                prescription_json="{}",
            )
            session.add(item)
            session.flush()
            for set_index in range(1, 4):
                session.add(
                    SetLog(
                        workout_item_id=item.id,
                        set_index=set_index,
                        reps=5,
                        weight=100.0,
                        weight_unit="kg",
                        completed_at=datetime(2026, 4, 10, 7, 15),
                    )
                )

        workout.primitive_blocks_json = _primitive_blocks(exercise_ids)

        # Add a future planned workout referencing the same exercises — triggers last_performed.
        future = Workout(
            user_id=user_id,
            name="Future",
            status="planned",
            source="claude",
            scheduled_date="2026-04-20",
        )
        session.add(future)
        session.flush()
        future.primitive_blocks_json = _primitive_blocks(exercise_ids)
        fblock = Block(
            workout_id=future.id,
            position=0,
            timing_mode="straight_sets",
            timing_config_json="{}",
        )
        session.add(fblock)
        session.flush()
        for i, exercise_id in enumerate(exercise_ids):
            session.add(
                WorkoutItem(
                    block_id=fblock.id,
                    position=i,
                    exercise_id=exercise_id,
                    prescription_json="{}",
                )
            )
        session.commit()
        return exercise_ids


def test_sync_pull_uses_bounded_queries(client, test_engine, test_user_id) -> None:
    """sync/pull must scale with O(1) queries in exercise count, not O(N).

    Pre-optimization: ~2N+M queries for N exercises. Post: small fixed count.
    """
    _seed_workout_with_exercises(test_engine, test_user_id, n_exercises=5)

    counter = QueryCounter()
    event.listen(test_engine, "before_cursor_execute", counter)
    try:
        response = client.get("/api/sync/pull")
    finally:
        event.remove(test_engine, "before_cursor_execute", counter)

    assert response.status_code == 200
    # Budget: workouts + exercises + user_parameters + last_performed (2 queries) +
    # eager-load sidecars + overhead. Concretely well under 15. If a future change
    # reintroduces N+1 this blows past the cap.
    assert counter.count < 15, f"sync/pull issued {counter.count} queries (expected <15)"


def test_get_workout_uses_bounded_queries(client, test_engine, test_user_id) -> None:
    """GET /api/workouts/:id must not lazy-load blocks → items → alternatives."""
    _seed_workout_with_exercises(test_engine, test_user_id, n_exercises=6)

    # Grab a workout id.
    workouts = client.get("/api/workouts").json()
    wid = workouts[0]["id"]

    counter = QueryCounter()
    event.listen(test_engine, "before_cursor_execute", counter)
    try:
        response = client.get(f"/api/workouts/{wid}")
    finally:
        event.remove(test_engine, "before_cursor_execute", counter)

    assert response.status_code == 200
    # Workout + blocks + items + alternatives = at most 4 queries (selectinload fan-out).
    assert counter.count <= 5, f"GET /api/workouts/:id issued {counter.count} queries (expected ≤5)"
