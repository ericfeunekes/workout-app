"""/api/sync primitive-only pull/results tests."""

from datetime import datetime

import pytest
from fastapi.exceptions import ResponseValidationError
from pydantic import ValidationError
from sqlalchemy.orm import Session
from workoutdb_server.models import AppUser, Exercise, PrimitiveSetLog, UserParameter, Workout

_BACK_SQUAT = "e0000001-0000-4000-8000-000000000001"
_PULLUP = "e0000002-0000-4000-8000-000000000002"
_OTHER_USER = "e0000009-0000-4000-8000-000000000009"


def _seed_exercise(engine, exercise_id: str = _BACK_SQUAT, name: str = "Back Squat") -> str:
    with Session(engine) as session:
        session.add(Exercise(id=exercise_id, name=name))
        session.commit()
    return exercise_id


def _primitive_workout_payload(
    exercise_id: str,
    *,
    workout_id: str = "10000000-0000-4000-8000-000000000001",
    block_id: str = "20000000-0000-4000-8000-000000000001",
    set_id: str = "30000000-0000-4000-8000-000000000001",
    slot_id: str = "40000000-0000-4000-8000-000000000001",
    status: str = "planned",
) -> dict:
    return {
        "id": workout_id,
        "name": "Future primitive",
        "scheduled_date": "2026-04-20",
        "status": status,
        "source": "claude",
        "primitive_blocks": [
            {
                "id": block_id,
                "sets": [
                    {
                        "id": set_id,
                        "timing": {"mode": "set_bounded"},
                        "slots": [
                            {
                                "id": slot_id,
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
                        ],
                    }
                ],
            }
        ],
    }


def _create_primitive_workout(client, exercise_id: str, **kwargs) -> dict:
    response = client.post(
        "/api/workouts",
        json=_primitive_workout_payload(exercise_id, **kwargs),
    )
    assert response.status_code == 200, response.text
    return response.json()


def _primitive_slot_log(
    *,
    workout_id: str = "10000000-0000-4000-8000-000000000001",
    log_id: str = "88888888-8888-4888-8888-888888888888",
    exercise_id: str = _BACK_SQUAT,
    block_id: str = "20000000-0000-4000-8000-000000000001",
    set_id: str = "30000000-0000-4000-8000-000000000001",
    slot_id: str = "40000000-0000-4000-8000-000000000001",
    reps: int | None = 5,
    weight: float | None = 100,
    completed_at: str = "2026-04-20T07:30:00Z",
) -> dict:
    return {
        "id": log_id,
        "role": "slot",
        "slot_id": slot_id,
        "set_id": set_id,
        "block_id": block_id,
        "workout_id": workout_id,
        "planned_exercise_id": exercise_id,
        "set_index": 0,
        "reps": reps,
        "weight": weight,
        "weight_unit": "kg" if weight is not None else None,
        "completed_at": completed_at,
    }


def test_pull_returns_primitive_workouts_user_parameters_and_last_performed(
    client, test_engine, test_user_id
) -> None:
    exercise_id = _seed_exercise(test_engine)
    workout = _create_primitive_workout(client, exercise_id)
    client.post(
        "/api/sync/results",
        json={
            "primitive_set_logs": [_primitive_slot_log()],
            "status_updates": [
                {
                    "workout_id": workout["id"],
                    "status": "completed",
                    "completed_at": "2026-04-20T08:00:00Z",
                }
            ],
        },
    )
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

    response = client.get("/api/sync/pull")
    assert response.status_code == 200, response.text
    body = response.json()

    assert (
        body["workouts"][0]["primitive_blocks"][0]["sets"][0]["slots"][0]["exercise_id"]
        == exercise_id
    )
    assert body["exercises"][0]["id"] == exercise_id
    assert {p["key"]: p["value"] for p in body["user_parameters"]}["bodyweight_kg"] == "82"
    assert body["last_performed"][0]["exercise_id"] == exercise_id
    assert body["last_performed"][0]["last_set_logs"][0]["weight"] == 100.0
    assert "prescription_json" not in body["last_performed"][0]


def test_pull_rejects_invalid_persisted_primitive_block(client, test_engine, test_user_id) -> None:
    with Session(test_engine) as session:
        session.add(
            Workout(
                id="10000000-0000-4000-8000-000000000010",
                user_id=test_user_id,
                name="Future primitive",
                status="planned",
                source="claude",
                primitive_blocks_json=(
                    '[{"id":"20000000-0000-4000-8000-000000000010",'
                    '"sets":[{"id":"30000000-0000-4000-8000-000000000010",'
                    '"timing":{"mode":"future_mode"},"slots":"not-a-list"}]}]'
                ),
            )
        )
        session.commit()

    with pytest.raises((ResponseValidationError, ValidationError)):
        client.get("/api/sync/pull")


def test_pull_rejects_empty_persisted_primitive_json(client, test_engine, test_user_id) -> None:
    with Session(test_engine) as session:
        session.add(
            Workout(
                id="10000000-0000-4000-8000-000000000012",
                user_id=test_user_id,
                name="Empty primitive",
                status="planned",
                source="claude",
                primitive_blocks_json="",
            )
        )
        session.commit()

    with pytest.raises((ResponseValidationError, ValidationError)):
        client.get("/api/sync/pull")


def test_pull_rejects_empty_persisted_primitive_array(client, test_engine, test_user_id) -> None:
    with Session(test_engine) as session:
        session.add(
            Workout(
                id="10000000-0000-4000-8000-000000000013",
                user_id=test_user_id,
                name="Empty primitive array",
                status="planned",
                source="claude",
                primitive_blocks_json="[]",
            )
        )
        session.commit()

    with pytest.raises((ResponseValidationError, ValidationError)):
        client.get("/api/sync/pull")


def test_pull_last_performed_uses_latest_completed_workout_only(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    older = _create_primitive_workout(
        client,
        exercise_id,
        workout_id="10000000-0000-4000-8000-000000000011",
        slot_id="40000000-0000-4000-8000-000000000011",
    )
    newer = _create_primitive_workout(
        client,
        exercise_id,
        workout_id="10000000-0000-4000-8000-000000000012",
        slot_id="40000000-0000-4000-8000-000000000012",
    )
    response = client.post(
        "/api/sync/results",
        json={
            "primitive_set_logs": [
                _primitive_slot_log(
                    workout_id=older["id"],
                    log_id="88888888-8888-4888-8888-888888888881",
                    slot_id="40000000-0000-4000-8000-000000000011",
                    weight=95,
                    completed_at="2026-04-19T07:30:00Z",
                ),
                _primitive_slot_log(
                    workout_id=newer["id"],
                    log_id="88888888-8888-4888-8888-888888888882",
                    slot_id="40000000-0000-4000-8000-000000000012",
                    weight=105,
                    completed_at="2026-04-20T07:30:00Z",
                ),
            ],
            "status_updates": [
                {
                    "workout_id": older["id"],
                    "status": "completed",
                    "completed_at": "2026-04-19T08:00:00Z",
                },
                {
                    "workout_id": newer["id"],
                    "status": "completed",
                    "completed_at": "2026-04-20T08:00:00Z",
                },
            ],
        },
    )
    assert response.status_code == 200, response.text

    pull = client.get("/api/sync/pull")
    assert pull.status_code == 200, pull.text
    logs = pull.json()["last_performed"][0]["last_set_logs"]
    assert len(logs) == 1
    assert logs[0]["workout_id"] == newer["id"]
    assert logs[0]["weight"] == 105


def test_sync_results_rejects_legacy_set_logs_payload(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    _create_primitive_workout(client, exercise_id)

    response = client.post(
        "/api/sync/results",
        json={
            "set_logs": [
                {
                    "id": "99999999-9999-4999-9999-999999999999",
                    "workout_item_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                    "set_index": 0,
                    "completed_at": "2026-04-20T07:30:00Z",
                }
            ]
        },
    )
    assert response.status_code == 422


def test_push_primitive_slot_log_and_status(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    workout = _create_primitive_workout(client, exercise_id)

    response = client.post(
        "/api/sync/results",
        json={
            "primitive_set_logs": [_primitive_slot_log()],
            "status_updates": [
                {
                    "workout_id": workout["id"],
                    "status": "completed",
                    "completed_at": "2026-04-20T08:00:00Z",
                    "notes": "good session",
                }
            ],
        },
    )
    assert response.status_code == 200, response.text
    assert response.json() == {
        "primitive_set_logs_received": 1,
        "status_updates_received": 1,
        "workout_resets_received": 0,
    }

    with Session(test_engine) as session:
        row = session.get(PrimitiveSetLog, "88888888-8888-4888-8888-888888888888")
        assert row is not None
        assert row.role == "slot"
        assert row.planned_exercise_id == exercise_id
        workout_row = session.get(Workout, workout["id"])
        assert workout_row is not None
        assert workout_row.status == "completed"
        assert workout_row.notes == "good session"


def test_push_primitive_set_result_and_distance_slot(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    workout = _create_primitive_workout(client, exercise_id)

    response = client.post(
        "/api/sync/results",
        json={
            "primitive_set_logs": [
                _primitive_slot_log(
                    log_id="88888888-8888-4888-8888-888888888889",
                    reps=None,
                    weight=None,
                )
                | {"distance_m": 1000, "duration_sec": 360},
                {
                    "id": "88888888-8888-4888-8888-88888888888a",
                    "role": "set_result",
                    "set_id": "30000000-0000-4000-8000-000000000001",
                    "block_id": "20000000-0000-4000-8000-000000000001",
                    "workout_id": workout["id"],
                    "set_index": 0,
                    "rounds": 3,
                    "completed_at": "2026-04-20T07:40:00Z",
                },
            ]
        },
    )
    assert response.status_code == 200, response.text

    with Session(test_engine) as session:
        distance = session.get(PrimitiveSetLog, "88888888-8888-4888-8888-888888888889")
        aggregate = session.get(PrimitiveSetLog, "88888888-8888-4888-8888-88888888888a")
        assert distance is not None
        assert distance.distance_m == 1000
        assert aggregate is not None
        assert aggregate.role == "set_result"
        assert aggregate.rounds == 3


def test_push_rejects_primitive_log_referencing_wrong_slot(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    _create_primitive_workout(client, exercise_id)

    response = client.post(
        "/api/sync/results",
        json={
            "primitive_set_logs": [
                _primitive_slot_log(slot_id="40000000-0000-4000-8000-000000000099")
            ]
        },
    )

    assert response.status_code == 422
    assert "slot_id outside workout" in response.text


def test_push_rejects_primitive_log_referencing_wrong_exercise(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    _create_primitive_workout(client, exercise_id)

    response = client.post(
        "/api/sync/results",
        json={"primitive_set_logs": [_primitive_slot_log(exercise_id=_PULLUP)]},
    )

    assert response.status_code == 422
    assert "planned_exercise_id outside workout" in response.text


def test_push_rejects_primitive_aggregate_referencing_wrong_set(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    workout = _create_primitive_workout(client, exercise_id)

    response = client.post(
        "/api/sync/results",
        json={
            "primitive_set_logs": [
                {
                    "id": "88888888-8888-4888-8888-88888888888b",
                    "role": "set_result",
                    "set_id": "30000000-0000-4000-8000-000000000099",
                    "block_id": "20000000-0000-4000-8000-000000000001",
                    "workout_id": workout["id"],
                    "set_index": 0,
                    "rounds": 3,
                    "completed_at": "2026-04-20T07:40:00Z",
                }
            ]
        },
    )

    assert response.status_code == 422
    assert "set_id outside workout" in response.text


def test_push_primitive_log_is_idempotent_by_id(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    _create_primitive_workout(client, exercise_id)
    first = _primitive_slot_log(weight=100)
    second = _primitive_slot_log(weight=105)

    assert client.post("/api/sync/results", json={"primitive_set_logs": [first]}).status_code == 200
    assert (
        client.post("/api/sync/results", json={"primitive_set_logs": [second]}).status_code == 200
    )

    with Session(test_engine) as session:
        rows = session.query(PrimitiveSetLog).all()
        assert len(rows) == 1
        assert rows[0].weight == 105


def test_workout_reset_deletes_primitive_logs_and_replans(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    workout = _create_primitive_workout(client, exercise_id)
    client.post(
        "/api/sync/results",
        json={
            "primitive_set_logs": [_primitive_slot_log()],
            "status_updates": [
                {
                    "workout_id": workout["id"],
                    "status": "completed",
                    "completed_at": "2026-04-20T08:00:00Z",
                }
            ],
        },
    )

    response = client.post(
        "/api/sync/results",
        json={"workout_resets": [{"workout_id": workout["id"]}]},
    )
    assert response.status_code == 200, response.text

    with Session(test_engine) as session:
        assert session.query(PrimitiveSetLog).count() == 0
        workout_row = session.get(Workout, workout["id"])
        assert workout_row is not None
        assert workout_row.status == "planned"
        assert workout_row.completed_at is None


def test_push_primitive_log_for_missing_workout_404(client) -> None:
    response = client.post(
        "/api/sync/results",
        json={
            "primitive_set_logs": [
                _primitive_slot_log(workout_id="00000000-0000-4000-8000-000000000000")
            ]
        },
    )
    assert response.status_code == 404


def test_push_rejects_cross_tenant_primitive_log(client, test_engine) -> None:
    with Session(test_engine) as session:
        session.add(AppUser(id=_OTHER_USER, name="Other"))
        session.add(Exercise(id=_PULLUP, name="Pull-up"))
        session.add(
            Workout(
                id="10000000-0000-4000-8000-000000000009",
                user_id=_OTHER_USER,
                name="Other",
                status="planned",
                source="claude",
                primitive_blocks_json="[]",
            )
        )
        session.commit()

    response = client.post(
        "/api/sync/results",
        json={
            "primitive_set_logs": [
                _primitive_slot_log(workout_id="10000000-0000-4000-8000-000000000009")
            ]
        },
    )
    assert response.status_code == 404


def test_sync_results_rollback_on_late_foreign_status(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    workout = _create_primitive_workout(client, exercise_id)
    with Session(test_engine) as session:
        session.add(AppUser(id=_OTHER_USER, name="Other"))
        session.add(
            Workout(
                id="10000000-0000-4000-8000-000000000009",
                user_id=_OTHER_USER,
                name="Other",
                status="planned",
                source="claude",
                primitive_blocks_json="[]",
            )
        )
        session.commit()

    response = client.post(
        "/api/sync/results",
        json={
            "primitive_set_logs": [_primitive_slot_log()],
            "status_updates": [
                {
                    "workout_id": workout["id"],
                    "status": "completed",
                    "completed_at": "2026-04-20T08:00:00Z",
                },
                {
                    "workout_id": "10000000-0000-4000-8000-000000000009",
                    "status": "completed",
                    "completed_at": "2026-04-20T08:01:00Z",
                },
            ],
        },
    )
    assert response.status_code == 404

    with Session(test_engine) as session:
        assert session.get(PrimitiveSetLog, "88888888-8888-4888-8888-888888888888") is None
        workout_row = session.get(Workout, workout["id"])
        assert workout_row is not None
        assert workout_row.status == "planned"
