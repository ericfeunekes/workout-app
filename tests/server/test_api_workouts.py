"""/api/workouts primitive-only contract tests."""

import copy

import pytest
from sqlalchemy.orm import Session
from workoutdb_server.models import AppUser, Exercise, Workout

_BACK_SQUAT = "e0000001-0000-4000-8000-000000000001"
_FRONT_SQUAT = "e0000002-0000-4000-8000-000000000002"
_OTHER_USER = "e0000009-0000-4000-8000-000000000009"


def _seed_exercise(engine, exercise_id: str = _BACK_SQUAT, name: str = "Back Squat") -> str:
    with Session(engine) as session:
        session.add(Exercise(id=exercise_id, name=name))
        session.commit()
    return exercise_id


def _slot(exercise_id: str, slot_id: str = "40000000-0000-4000-8000-000000000001") -> dict:
    return {
        "id": slot_id,
        "exercise_id": exercise_id,
        "work_target": [
            {"metric": "reps", "value_form": "single", "value": 5, "role": "completion"}
        ],
        "load": {"value": 100, "unit": "kg", "unit_type": "absolute"},
    }


def _primitive_block(
    exercise_id: str,
    *,
    block_id: str = "20000000-0000-4000-8000-000000000001",
    set_id: str = "30000000-0000-4000-8000-000000000001",
    timing: dict | None = None,
    traversal: str = "sequential",
    work_target: list[dict] | None = None,
    slots: list[dict] | None = None,
) -> dict:
    return {
        "id": block_id,
        "title": "Main",
        "work_target": work_target or [],
        "sets": [
            {
                "id": set_id,
                "timing": timing or {"mode": "set_bounded"},
                "traversal": traversal,
                "work_target": work_target or [],
                "slots": slots if slots is not None else [_slot(exercise_id)],
            }
        ],
    }


def _workout_payload(exercise_id: str, **overrides) -> dict:
    base = {
        "name": "Tuesday Legs",
        "scheduled_date": "2026-04-20",
        "status": "planned",
        "source": "claude",
        "tags_json": '["hypertrophy_block_2"]',
        "primitive_blocks": [_primitive_block(exercise_id)],
    }
    base.update(overrides)
    return base


def test_create_primitive_workout(client, test_engine, test_user_id) -> None:
    exercise_id = _seed_exercise(test_engine)

    response = client.post("/api/workouts", json=_workout_payload(exercise_id))
    assert response.status_code == 200, response.text
    body = response.json()

    assert body["name"] == "Tuesday Legs"
    assert body["user_id"] == test_user_id
    assert "blocks" not in body
    assert body["primitive_blocks"][0]["sets"][0]["slots"][0]["exercise_id"] == exercise_id

    readback = client.get(f"/api/workouts/{body['id']}")
    assert readback.status_code == 200
    assert readback.json()["primitive_blocks"] == body["primitive_blocks"]


def test_read_rejects_invalid_persisted_primitive_block(client, test_engine, test_user_id) -> None:
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

    response = client.get("/api/workouts/10000000-0000-4000-8000-000000000010")
    assert response.status_code == 500
    assert "Persisted primitive workout 10000000-0000-4000-8000-000000000010 is invalid" in (
        response.text
    )


def test_list_rejects_invalid_persisted_primitive_block(client, test_engine, test_user_id) -> None:
    with Session(test_engine) as session:
        session.add(
            Workout(
                id="10000000-0000-4000-8000-000000000014",
                user_id=test_user_id,
                name="Future primitive list",
                status="planned",
                source="claude",
                primitive_blocks_json=(
                    '[{"id":"20000000-0000-4000-8000-000000000014",'
                    '"sets":[{"id":"30000000-0000-4000-8000-000000000014",'
                    '"timing":{"mode":"future_mode"},"slots":"not-a-list"}]}]'
                ),
            )
        )
        session.commit()

    response = client.get("/api/workouts")
    assert response.status_code == 500
    assert "Persisted primitive workout 10000000-0000-4000-8000-000000000014 is invalid" in (
        response.text
    )


def test_read_rejects_malformed_persisted_primitive_json(client, test_engine, test_user_id) -> None:
    with Session(test_engine) as session:
        session.add(
            Workout(
                id="10000000-0000-4000-8000-000000000011",
                user_id=test_user_id,
                name="Malformed primitive",
                status="planned",
                source="claude",
                primitive_blocks_json='{"not":"a-list"}',
            )
        )
        session.commit()

    response = client.get("/api/workouts/10000000-0000-4000-8000-000000000011")
    assert response.status_code == 500
    assert "Persisted primitive workout 10000000-0000-4000-8000-000000000011 is invalid" in (
        response.text
    )


def test_read_rejects_empty_persisted_primitive_json(client, test_engine, test_user_id) -> None:
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

    response = client.get("/api/workouts/10000000-0000-4000-8000-000000000012")
    assert response.status_code == 500
    assert "Persisted primitive workout 10000000-0000-4000-8000-000000000012 is invalid" in (
        response.text
    )


def test_read_rejects_empty_persisted_primitive_array(client, test_engine, test_user_id) -> None:
    with Session(test_engine) as session:
        session.add(
            Workout(
                id="10000000-0000-4000-8000-000000000013",
                user_id=test_user_id,
                name="No primitive work",
                status="planned",
                source="claude",
                primitive_blocks_json="[]",
            )
        )
        session.commit()

    response = client.get("/api/workouts/10000000-0000-4000-8000-000000000013")
    assert response.status_code == 500
    assert "Persisted primitive workout 10000000-0000-4000-8000-000000000013 is invalid" in (
        response.text
    )


def test_create_rejects_legacy_blocks_payload(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    payload = _workout_payload(exercise_id)
    payload["blocks"] = [
        {
            "position": 0,
            "timing_mode": "straight_sets",
            "timing_config_json": "{}",
            "workout_items": [],
        }
    ]

    response = client.post("/api/workouts", json=payload)
    assert response.status_code == 422


def test_create_rejects_extra_fields_inside_primitive_tree(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    payload = _workout_payload(exercise_id)
    payload["primitive_blocks"][0]["sets"][0]["slots"][0]["workoutkit_activity"] = "running"

    response = client.post("/api/workouts", json=payload)

    assert response.status_code == 422
    assert "workoutkit_activity" in response.text


@pytest.mark.parametrize(
    ("path", "field"),
    [
        (("primitive_blocks", 0), "adapter_profile"),
        (("primitive_blocks", 0, "work_target", 0), "export_metric"),
        (("primitive_blocks", 0, "sets", 0), "adapter_profile"),
        (("primitive_blocks", 0, "sets", 0, "timing"), "workoutkit_goal"),
        (("primitive_blocks", 0, "sets", 0, "work_target", 0), "export_metric"),
        (("primitive_blocks", 0, "sets", 0, "slots", 0), "workoutkit_activity"),
        (("primitive_blocks", 0, "sets", 0, "slots", 0, "work_target", 0), "export_metric"),
        (("primitive_blocks", 0, "sets", 0, "slots", 0, "load"), "strava_load"),
        (("primitive_blocks", 0, "sets", 0, "slots", 0, "stimuli", 0), "healthkit_zone"),
    ],
)
def test_create_rejects_extra_fields_inside_every_primitive_submodel(
    client, test_engine, path, field
) -> None:
    exercise_id = _seed_exercise(test_engine)
    payload = _workout_payload(
        exercise_id,
        primitive_blocks=[
            _primitive_block(
                exercise_id,
                work_target=[
                    {
                        "metric": "duration",
                        "value_form": "open",
                        "value": None,
                        "role": "observation",
                    }
                ],
                slots=[
                    _slot(exercise_id)
                    | {
                        "stimuli": [{"type": "rir", "target": 2}],
                    }
                ],
            )
        ],
    )
    payload = copy.deepcopy(payload)
    node = payload
    for segment in path:
        node = node[segment]
    node[field] = "not-owned-here"

    response = client.post("/api/workouts", json=payload)

    assert response.status_code == 422
    assert field in response.text


def test_create_requires_primitive_blocks(client) -> None:
    response = client.post(
        "/api/workouts",
        json={"name": "No work", "status": "planned", "source": "claude"},
    )
    assert response.status_code == 422


def test_create_rejects_unknown_primitive_slot_exercise(client) -> None:
    response = client.post(
        "/api/workouts",
        json=_workout_payload("00000000-0000-4000-8000-000000000000"),
    )
    assert response.status_code == 422
    assert "primitive slot exercise_id not found" in response.text


def test_create_rejects_zero_slot_sets(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    payload = _workout_payload(
        exercise_id,
        primitive_blocks=[
            _primitive_block(
                exercise_id,
                timing={"mode": "time_bounded", "interval_sec": 60, "rounds": 1},
                slots=[],
            )
        ],
    )

    response = client.post("/api/workouts", json=payload)
    assert response.status_code == 422


def test_create_accepts_legal_amrap_aggregate(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    payload = _workout_payload(
        exercise_id,
        primitive_blocks=[
            _primitive_block(
                exercise_id,
                timing={"mode": "cap_bounded", "cap_sec": 1200},
                traversal="amrap",
                work_target=[
                    {
                        "metric": "rounds",
                        "value_form": "open",
                        "value": None,
                        "role": "observation",
                    }
                ],
            )
        ],
    )

    response = client.post("/api/workouts", json=payload)
    assert response.status_code == 200, response.text
    assert response.json()["primitive_blocks"][0]["sets"][0]["traversal"] == "amrap"


def test_create_rejects_amrap_without_rounds_observation(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    payload = _workout_payload(
        exercise_id,
        primitive_blocks=[
            _primitive_block(
                exercise_id,
                timing={"mode": "cap_bounded", "cap_sec": 1200},
                traversal="amrap",
            )
        ],
    )

    response = client.post("/api/workouts", json=payload)
    assert response.status_code == 422


def test_create_normalizes_implicit_bodyweight_load(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    payload = _workout_payload(
        exercise_id,
        primitive_blocks=[
            _primitive_block(
                exercise_id,
                slots=[
                    {
                        "id": "40000000-0000-4000-8000-000000000002",
                        "exercise_id": exercise_id,
                        "load": {"unit": "bodyweight", "unit_type": "implicit_bodyweight"},
                    }
                ],
            )
        ],
    )

    response = client.post("/api/workouts", json=payload)
    assert response.status_code == 200, response.text
    stored = response.json()["primitive_blocks"][0]["sets"][0]["slots"][0]["load"]
    assert stored == {"value": None, "unit": "bodyweight", "unit_type": "implicit_bodyweight"}


def test_update_replaces_primitive_blocks_and_rejects_blocks(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    _seed_exercise(test_engine, _FRONT_SQUAT, "Front Squat")
    create = client.post("/api/workouts", json=_workout_payload(exercise_id))
    assert create.status_code == 200
    workout_id = create.json()["id"]

    replace = client.put(
        f"/api/workouts/{workout_id}",
        json={
            "primitive_blocks": [
                _primitive_block(
                    _FRONT_SQUAT,
                    block_id="20000000-0000-4000-8000-000000000002",
                    set_id="30000000-0000-4000-8000-000000000002",
                    slots=[
                        _slot(
                            _FRONT_SQUAT,
                            slot_id="40000000-0000-4000-8000-000000000002",
                        )
                    ],
                )
            ]
        },
    )
    assert replace.status_code == 200, replace.text
    assert (
        replace.json()["primitive_blocks"][0]["sets"][0]["slots"][0]["exercise_id"] == _FRONT_SQUAT
    )

    legacy = client.put(f"/api/workouts/{workout_id}", json={"blocks": []})
    assert legacy.status_code == 422


def test_update_rejects_empty_primitive_blocks(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    create = client.post("/api/workouts", json=_workout_payload(exercise_id))
    assert create.status_code == 200
    workout_id = create.json()["id"]

    response = client.put(f"/api/workouts/{workout_id}", json={"primitive_blocks": []})
    assert response.status_code == 422


def test_list_filters_by_status_and_tag(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    planned = client.post("/api/workouts", json=_workout_payload(exercise_id))
    skipped = client.post(
        "/api/workouts",
        json=_workout_payload(
            exercise_id,
            name="Skipped",
            status="skipped",
            tags_json='["deload"]',
            primitive_blocks=[
                _primitive_block(
                    exercise_id,
                    block_id="20000000-0000-4000-8000-000000000003",
                    set_id="30000000-0000-4000-8000-000000000003",
                    slots=[
                        _slot(
                            exercise_id,
                            slot_id="40000000-0000-4000-8000-000000000003",
                        )
                    ],
                )
            ],
        ),
    )
    assert planned.status_code == 200
    assert skipped.status_code == 200

    planned_rows = client.get("/api/workouts", params={"status": "planned"}).json()
    assert [row["name"] for row in planned_rows] == ["Tuesday Legs"]

    deload_rows = client.get("/api/workouts", params={"tag": "deload"}).json()
    assert [row["name"] for row in deload_rows] == ["Skipped"]


def test_post_existing_id_upserts_for_same_user(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    workout_id = "10000000-0000-4000-8000-000000000001"

    first = client.post("/api/workouts", json=_workout_payload(exercise_id, id=workout_id))
    assert first.status_code == 200
    second = client.post(
        "/api/workouts",
        json=_workout_payload(exercise_id, id=workout_id, name="Updated primitive"),
    )
    assert second.status_code == 200
    assert second.json()["name"] == "Updated primitive"

    rows = client.get("/api/workouts").json()
    assert [row["id"] for row in rows] == [workout_id]


def test_post_existing_id_owned_by_other_user_404(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    with Session(test_engine) as session:
        session.add(AppUser(id=_OTHER_USER, name="Other"))
        session.add(
            Workout(
                id="10000000-0000-4000-8000-000000000002",
                user_id=_OTHER_USER,
                name="Other",
                status="planned",
                source="claude",
                primitive_blocks_json="[]",
            )
        )
        session.commit()

    response = client.post(
        "/api/workouts",
        json=_workout_payload(
            exercise_id,
            id="10000000-0000-4000-8000-000000000002",
        ),
    )
    assert response.status_code == 404
