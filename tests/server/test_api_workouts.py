"""/api/workouts — nested create, update, list with filters, get by id."""

from sqlalchemy.orm import Session

from workoutdb_server.models import AppUser, Exercise


def _seed(engine) -> tuple[str, str]:
    with Session(engine) as session:
        user = AppUser(name="Eric")
        exercise = Exercise(id="back-squat", name="Back Squat")
        session.add_all([user, exercise])
        session.commit()
        return user.id, exercise.id


def _workout_payload(user_id: str, exercise_id: str, **overrides) -> dict:
    base = {
        "user_id": user_id,
        "name": "Tuesday Legs",
        "scheduled_date": "2026-04-20",
        "status": "planned",
        "source": "claude",
        "tags_json": '["hypertrophy_block_2"]',
        "blocks": [
            {
                "position": 0,
                "name": "Main",
                "timing_mode": "straight_sets",
                "timing_config_json": '{"rest_between_sets_sec": 180}',
                "rounds": None,
                "workout_items": [
                    {
                        "position": 0,
                        "exercise_id": exercise_id,
                        "prescription_json": '{"sets": 5, "reps": 5, "load_kg": 100}',
                        "alternatives": [
                            {
                                "exercise_id": exercise_id,
                                "reason": "bar taken",
                            }
                        ],
                    }
                ],
            }
        ],
    }
    base.update(overrides)
    return base


def test_create_nested_workout(client, test_engine) -> None:
    user_id, exercise_id = _seed(test_engine)

    response = client.post("/api/workouts", json=_workout_payload(user_id, exercise_id))
    assert response.status_code == 200
    body = response.json()

    assert body["name"] == "Tuesday Legs"
    assert len(body["blocks"]) == 1
    assert len(body["blocks"][0]["workout_items"]) == 1
    assert len(body["blocks"][0]["workout_items"][0]["alternatives"]) == 1


def test_list_filters_by_status(client, test_engine) -> None:
    user_id, exercise_id = _seed(test_engine)
    client.post("/api/workouts", json=_workout_payload(user_id, exercise_id))
    client.post(
        "/api/workouts",
        json=_workout_payload(
            user_id, exercise_id, name="Other", status="completed", scheduled_date="2026-04-15"
        ),
    )

    response = client.get(f"/api/workouts?user_id={user_id}&status=completed")
    assert response.status_code == 200
    rows = response.json()
    assert len(rows) == 1
    assert rows[0]["name"] == "Other"


def test_list_filters_by_tag(client, test_engine) -> None:
    user_id, exercise_id = _seed(test_engine)
    client.post("/api/workouts", json=_workout_payload(user_id, exercise_id))
    client.post(
        "/api/workouts",
        json=_workout_payload(user_id, exercise_id, name="Peaking", tags_json='["peaking_week"]'),
    )

    response = client.get(f"/api/workouts?user_id={user_id}&tag=peaking_week")
    rows = response.json()
    assert len(rows) == 1
    assert rows[0]["name"] == "Peaking"


def test_update_replaces_blocks(client, test_engine) -> None:
    user_id, exercise_id = _seed(test_engine)
    created = client.post("/api/workouts", json=_workout_payload(user_id, exercise_id)).json()

    response = client.put(
        f"/api/workouts/{created['id']}",
        json={
            "name": "Renamed",
            "blocks": [
                {
                    "position": 0,
                    "timing_mode": "rest",
                    "timing_config_json": '{"duration_sec": 60}',
                    "workout_items": [],
                }
            ],
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["name"] == "Renamed"
    assert len(body["blocks"]) == 1
    assert body["blocks"][0]["timing_mode"] == "rest"
    assert body["blocks"][0]["workout_items"] == []


def test_get_by_id_404(client, test_engine) -> None:
    _seed(test_engine)
    response = client.get("/api/workouts/nonexistent")
    assert response.status_code == 404


def test_create_rejects_unknown_user(client, test_engine) -> None:
    _seed(test_engine)
    payload = _workout_payload("unknown-user-id", "back-squat")
    response = client.post("/api/workouts", json=payload)
    assert response.status_code == 400
    assert "user_id" in response.json()["detail"]


def test_list_pagination(client, test_engine) -> None:
    user_id, exercise_id = _seed(test_engine)
    for i in range(5):
        client.post(
            "/api/workouts",
            json=_workout_payload(
                user_id, exercise_id, name=f"W{i}", scheduled_date=f"2026-04-{20 + i}"
            ),
        )

    page1 = client.get(f"/api/workouts?user_id={user_id}&limit=2&offset=0").json()
    page2 = client.get(f"/api/workouts?user_id={user_id}&limit=2&offset=2").json()
    assert len(page1) == 2
    assert len(page2) == 2
    assert {w["name"] for w in page1}.isdisjoint({w["name"] for w in page2})
