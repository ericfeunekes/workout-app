"""/api/workouts — nested create, update, list with filters, get by id.

The authenticated user_id comes from the bearer token (conftest seeds it as test_user_id).
"""

from sqlalchemy.orm import Session

from workoutdb_server.models import AppUser, Exercise


def _seed_exercise(engine) -> str:
    with Session(engine) as session:
        exercise = Exercise(id="back-squat", name="Back Squat")
        session.add(exercise)
        session.commit()
        return exercise.id


def _workout_payload(exercise_id: str, **overrides) -> dict:
    base = {
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


def test_create_nested_workout(client, test_engine, test_user_id) -> None:
    exercise_id = _seed_exercise(test_engine)

    response = client.post("/api/workouts", json=_workout_payload(exercise_id))
    assert response.status_code == 200
    body = response.json()

    assert body["name"] == "Tuesday Legs"
    assert body["user_id"] == test_user_id
    assert len(body["blocks"]) == 1
    assert len(body["blocks"][0]["workout_items"]) == 1
    assert len(body["blocks"][0]["workout_items"][0]["alternatives"]) == 1


def test_list_filters_by_status(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    client.post("/api/workouts", json=_workout_payload(exercise_id))
    client.post(
        "/api/workouts",
        json=_workout_payload(
            exercise_id, name="Other", status="completed", scheduled_date="2026-04-15"
        ),
    )

    response = client.get("/api/workouts?status=completed")
    assert response.status_code == 200
    rows = response.json()
    assert len(rows) == 1
    assert rows[0]["name"] == "Other"


def test_list_filters_by_tag(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    client.post("/api/workouts", json=_workout_payload(exercise_id))
    client.post(
        "/api/workouts",
        json=_workout_payload(exercise_id, name="Peaking", tags_json='["peaking_week"]'),
    )

    response = client.get("/api/workouts?tag=peaking_week")
    rows = response.json()
    assert len(rows) == 1
    assert rows[0]["name"] == "Peaking"


def test_update_replaces_blocks(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    created = client.post("/api/workouts", json=_workout_payload(exercise_id)).json()

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
    _seed_exercise(test_engine)
    response = client.get("/api/workouts/nonexistent")
    assert response.status_code == 404


def test_get_rejects_another_users_workout(client, test_engine, test_user_id) -> None:
    """Tenant isolation: workouts owned by a different user_id must 404, not leak."""
    _seed_exercise(test_engine)
    with Session(test_engine) as session:
        other = AppUser(id="other-user", name="Other")
        session.add(other)
        session.commit()

    # Directly insert a workout owned by 'other-user' so we bypass the auth'd POST.
    with Session(test_engine) as session:
        from workoutdb_server.models import Workout

        w = Workout(
            user_id="other-user",
            name="Private",
            status="planned",
            source="claude",
        )
        session.add(w)
        session.commit()
        other_workout_id = w.id

    response = client.get(f"/api/workouts/{other_workout_id}")
    assert response.status_code == 404, (
        f"Cross-tenant read leak: authenticated as {test_user_id}, "
        f"reached workout owned by other-user"
    )


def test_list_pagination(client, test_engine) -> None:
    exercise_id = _seed_exercise(test_engine)
    for i in range(5):
        client.post(
            "/api/workouts",
            json=_workout_payload(exercise_id, name=f"W{i}", scheduled_date=f"2026-04-{20 + i}"),
        )

    page1 = client.get("/api/workouts?limit=2&offset=0").json()
    page2 = client.get("/api/workouts?limit=2&offset=2").json()
    assert len(page1) == 2
    assert len(page2) == 2
    assert {w["name"] for w in page1}.isdisjoint({w["name"] for w in page2})
