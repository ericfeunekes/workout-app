"""/api/sync — pull (server → app) and results (app → server)."""

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


def _seed_completed_workout(engine) -> tuple[str, str, str]:
    """Returns (user_id, exercise_id, workout_item_id)."""
    with Session(engine) as session:
        user = AppUser(name="Eric")
        exercise = Exercise(id="back-squat", name="Back Squat")
        session.add_all([user, exercise])
        session.flush()

        workout = Workout(
            user_id=user.id,
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
                user_id=user.id,
                key="bodyweight_kg",
                value="82",
                updated_at=datetime(2026, 4, 1),
                source="claude",
            )
        )
        session.commit()
        return user.id, exercise.id, item.id


def _create_future_workout(client, user_id: str, exercise_id: str) -> str:
    """A planned workout referencing the same exercise, so last_performed fires."""
    payload = {
        "user_id": user_id,
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


def test_pull_returns_workouts_and_last_performed(client, test_engine) -> None:
    user_id, exercise_id, _ = _seed_completed_workout(test_engine)
    _create_future_workout(client, user_id, exercise_id)

    response = client.get(f"/api/sync/pull?user_id={user_id}")
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


def test_push_set_logs_and_status(client, test_engine) -> None:
    user_id, exercise_id, _ = _seed_completed_workout(test_engine)
    future_id = _create_future_workout(client, user_id, exercise_id)

    # Get the workout_item_id from the future workout
    detail = client.get(f"/api/workouts/{future_id}").json()
    item_id = detail["blocks"][0]["workout_items"][0]["id"]

    response = client.post(
        "/api/sync/results",
        json={
            "set_logs": [
                {
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


def test_push_status_for_missing_workout_404(client, test_engine) -> None:
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
