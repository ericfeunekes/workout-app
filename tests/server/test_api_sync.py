"""/api/sync — pull (server → app) and results (app → server).

The authenticated user_id is the conftest's test_user_id; tests seed workouts
owned by that user and call endpoints without passing user_id in the request.
"""

from datetime import datetime

from sqlalchemy.orm import Session

from workoutdb_server.models import (
    AppUser,
    Block,
    Exercise,
    SetLog,
    UserParameter,
    Workout,
    WorkoutItem,
)


def _seed_completed_workout(engine, user_id: str) -> tuple[str, str]:
    """Returns (exercise_id, workout_item_id). `user_id` is the auth'd user."""
    with Session(engine) as session:
        exercise = Exercise(id="back-squat", name="Back Squat")
        session.add(exercise)
        session.flush()

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

        item = WorkoutItem(
            block_id=block.id,
            position=0,
            exercise_id=exercise.id,
            prescription_json='{"sets": 5, "reps": 5, "load_kg": 100}',
        )
        session.add(item)
        session.flush()

        session.add(
            SetLog(
                workout_item_id=item.id,
                set_index=1,
                reps=5,
                weight=100.0,
                weight_unit="kg",
                completed_at=datetime(2026, 4, 10, 7, 15),
            )
        )
        session.add(
            UserParameter(
                user_id=user_id,
                key="bodyweight_kg",
                value="82",
                updated_at=datetime(2026, 4, 1),
                source="claude",
            )
        )
        session.commit()
        return exercise.id, item.id


def _create_future_workout(client, exercise_id: str) -> str:
    """A planned workout referencing the same exercise, so last_performed fires."""
    payload = {
        "name": "Future",
        "scheduled_date": "2026-04-20",
        "status": "planned",
        "source": "claude",
        "blocks": [
            {
                "position": 0,
                "timing_mode": "straight_sets",
                "timing_config_json": "{}",
                "workout_items": [
                    {
                        "position": 0,
                        "exercise_id": exercise_id,
                        "prescription_json": '{"sets": 5, "reps": 5, "load_kg": 105}',
                    }
                ],
            }
        ],
    }
    response = client.post("/api/workouts", json=payload)
    assert response.status_code == 200
    return response.json()["id"]


def test_pull_returns_workouts_and_last_performed(client, test_engine, test_user_id) -> None:
    exercise_id, _ = _seed_completed_workout(test_engine, test_user_id)
    _create_future_workout(client, exercise_id)

    response = client.get("/api/sync/pull")
    assert response.status_code == 200
    body = response.json()

    assert len(body["workouts"]) == 2  # completed + future
    assert len(body["exercises"]) == 1
    assert body["exercises"][0]["id"] == "back-squat"
    assert len(body["user_parameters"]) == 1
    assert body["user_parameters"][0]["key"] == "bodyweight_kg"

    # last_performed contains the completed session's logs
    assert len(body["last_performed"]) == 1
    last = body["last_performed"][0]
    assert last["exercise_id"] == "back-squat"
    assert len(last["last_set_logs"]) == 1
    assert last["last_set_logs"][0]["weight"] == 100.0


def test_push_set_logs_and_status(client, test_engine, test_user_id) -> None:
    exercise_id, _ = _seed_completed_workout(test_engine, test_user_id)
    future_id = _create_future_workout(client, exercise_id)

    # Get the workout_item_id from the future workout
    detail = client.get(f"/api/workouts/{future_id}").json()
    item_id = detail["blocks"][0]["workout_items"][0]["id"]

    response = client.post(
        "/api/sync/results",
        json={
            "set_logs": [
                {
                    "id": "88888888-8888-8888-8888-888888888888",
                    "workout_item_id": item_id,
                    "set_index": 1,
                    "reps": 5,
                    "weight": 105.0,
                    "weight_unit": "kg",
                    "rpe": 7.0,
                    "completed_at": "2026-04-20T07:30:00Z",
                }
            ],
            "status_updates": [
                {
                    "workout_id": future_id,
                    "status": "completed",
                    "completed_at": "2026-04-20T08:00:00Z",
                }
            ],
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body == {"set_logs_received": 1, "status_updates_received": 1}

    # Verify
    detail = client.get(f"/api/workouts/{future_id}").json()
    assert detail["status"] == "completed"


def test_pull_since_skips_user_parameters_already_seen(client, test_engine, test_user_id) -> None:
    """user_parameters sync must respect `since` — the app already has older rows."""
    with Session(test_engine) as session:
        session.add(
            UserParameter(
                user_id=test_user_id,
                key="bodyweight_kg",
                value="82",
                updated_at=datetime(2026, 4, 1),
                source="claude",
            )
        )
        session.commit()

    # Initial pull returns the bodyweight row.
    baseline = client.get("/api/sync/pull").json()["server_time"]

    # Subsequent pull with since=baseline returns nothing new.
    body = client.get(f"/api/sync/pull?since={baseline}").json()
    assert body["user_parameters"] == []

    # Claude pushes a new row for the same key — app pulls it next time.
    client.post(
        "/api/user-parameters",
        json=[{"key": "bodyweight_kg", "value": "81", "source": "claude"}],
    )
    body = client.get(f"/api/sync/pull?since={baseline}").json()
    assert len(body["user_parameters"]) == 1
    assert body["user_parameters"][0]["value"] == "81"


def test_pull_since_returns_workouts_edited_after_creation(client, test_engine) -> None:
    """Regression: PUT /api/workouts/:id must bump updated_at so the app sees edits.

    Before the updated_at column was added, sync filtered on created_at, which meant
    Claude could edit a planned workout (e.g. change a load target) and the app would
    never pull the change.
    """
    with Session(test_engine) as session:
        session.add(Exercise(id="back-squat", name="Back Squat"))
        session.commit()

    payload = {
        "name": "Draft",
        "scheduled_date": "2026-04-20",
        "status": "planned",
        "source": "claude",
        "blocks": [
            {
                "position": 0,
                "timing_mode": "straight_sets",
                "timing_config_json": "{}",
                "workout_items": [
                    {
                        "position": 0,
                        "exercise_id": "back-squat",
                        "prescription_json": '{"sets": 5, "reps": 5, "load_kg": 100}',
                    }
                ],
            }
        ],
    }
    created = client.post("/api/workouts", json=payload).json()
    workout_id = created["id"]
    created_at = created["created_at"]

    # App pulls up through creation time, then the baseline moves to server_time.
    baseline = client.get("/api/sync/pull").json()["server_time"]
    assert client.get(f"/api/sync/pull?since={baseline}").json()["workouts"] == []

    # Claude edits the workout — bumps load from 100 to 110.
    put_payload = {
        "blocks": [
            {
                "position": 0,
                "timing_mode": "straight_sets",
                "timing_config_json": "{}",
                "workout_items": [
                    {
                        "position": 0,
                        "exercise_id": "back-squat",
                        "prescription_json": '{"sets": 5, "reps": 5, "load_kg": 110}',
                    }
                ],
            }
        ]
    }
    edited = client.put(f"/api/workouts/{workout_id}", json=put_payload).json()
    assert edited["updated_at"] > created_at

    # App re-pulls with the same baseline and must see the edit.
    body = client.get(f"/api/sync/pull?since={baseline}").json()
    assert len(body["workouts"]) == 1
    assert body["workouts"][0]["id"] == workout_id
    pj = body["workouts"][0]["blocks"][0]["workout_items"][0]["prescription_json"]
    assert '"load_kg": 110' in pj


def test_push_set_logs_is_idempotent_by_id(client, test_engine, test_user_id) -> None:
    """Pushing the same set_log UUID twice must update in place — no duplicate rows.

    The app can retry failed pushes freely; the server trusts the UUID the app assigned.
    """
    exercise_id, _ = _seed_completed_workout(test_engine, test_user_id)
    future_id = _create_future_workout(client, exercise_id)
    item_id = client.get(f"/api/workouts/{future_id}").json()["blocks"][0]["workout_items"][0]["id"]

    log_id = "99999999-9999-9999-9999-999999999999"
    payload = {
        "set_logs": [
            {
                "id": log_id,
                "workout_item_id": item_id,
                "set_index": 1,
                "reps": 5,
                "weight": 100.0,
                "weight_unit": "kg",
                "completed_at": "2026-04-20T07:30:00Z",
            }
        ],
        "status_updates": [],
    }
    assert client.post("/api/sync/results", json=payload).status_code == 200

    # Retry with a different weight — should update, not insert.
    payload["set_logs"][0]["weight"] = 102.5
    assert client.post("/api/sync/results", json=payload).status_code == 200

    with Session(test_engine) as session:
        rows = session.query(SetLog).filter_by(workout_item_id=item_id).all()
        assert len(rows) == 1
        assert rows[0].id == log_id
        assert rows[0].weight == 102.5


def test_pull_last_performed_covers_alternatives(client, test_engine, test_user_id) -> None:
    """A user can swap to an alternative mid-workout; the app needs its history too."""
    # Seed: a completed front-squat session (this will be the alternative).
    with Session(test_engine) as session:
        back_squat = Exercise(id="back-squat", name="Back Squat")
        front_squat = Exercise(id="front-squat", name="Front Squat")
        session.add_all([back_squat, front_squat])
        session.flush()

        workout = Workout(
            user_id=test_user_id,
            name="Past front-squat day",
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

        item = WorkoutItem(
            block_id=block.id,
            position=0,
            exercise_id=front_squat.id,
            prescription_json="{}",
        )
        session.add(item)
        session.flush()

        session.add(
            SetLog(
                workout_item_id=item.id,
                set_index=1,
                reps=5,
                weight=90.0,
                weight_unit="kg",
                completed_at=datetime(2026, 4, 10, 7, 15),
            )
        )
        session.commit()

    # New planned workout: back-squat with front-squat as an alternative.
    client.post(
        "/api/workouts",
        json={
            "name": "Upcoming",
            "scheduled_date": "2026-04-20",
            "status": "planned",
            "source": "claude",
            "blocks": [
                {
                    "position": 0,
                    "timing_mode": "straight_sets",
                    "timing_config_json": "{}",
                    "workout_items": [
                        {
                            "position": 0,
                            "exercise_id": "back-squat",
                            "prescription_json": "{}",
                            "alternatives": [
                                {
                                    "exercise_id": "front-squat",
                                    "reason": "bar taken",
                                }
                            ],
                        }
                    ],
                }
            ],
        },
    )

    body = client.get("/api/sync/pull").json()
    exercise_ids = {lp["exercise_id"] for lp in body["last_performed"]}
    assert "front-squat" in exercise_ids, (
        "sync/pull must include last_performed for exercises referenced only as alternatives"
    )


def test_push_status_for_missing_workout_404(client) -> None:
    response = client.post(
        "/api/sync/results",
        json={
            "set_logs": [],
            "status_updates": [
                {"workout_id": "nonexistent", "status": "completed"},
            ],
        },
    )
    assert response.status_code == 404


def test_push_rejects_cross_tenant_set_log(client, test_engine) -> None:
    """A set_log for another user's workout_item must 404 — tenant isolation."""
    with Session(test_engine) as session:
        other = AppUser(id="other-user", name="Other")
        exercise = Exercise(id="ohp", name="OHP")
        session.add_all([other, exercise])
        session.flush()
        workout = Workout(
            user_id="other-user",
            name="Other's workout",
            status="planned",
            source="claude",
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
        item = WorkoutItem(
            block_id=block.id,
            position=0,
            exercise_id=exercise.id,
            prescription_json="{}",
        )
        session.add(item)
        session.commit()
        other_item_id = item.id

    response = client.post(
        "/api/sync/results",
        json={
            "set_logs": [
                {
                    "id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
                    "workout_item_id": other_item_id,
                    "set_index": 1,
                    "completed_at": "2026-04-20T07:30:00Z",
                }
            ],
            "status_updates": [],
        },
    )
    assert response.status_code == 404
