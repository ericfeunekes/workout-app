"""/api/exercises — Claude-owned IDs, upsert by id."""

import json

# Canonical test UUIDs. Per docs/specs/v2-architecture.md, exercise ids are UUIDs.
_BACK_SQUAT = "e0000001-0000-4000-8000-000000000001"
_FRONT_SQUAT = "e0000002-0000-4000-8000-000000000002"


def test_upsert_creates_and_updates(client) -> None:
    # Create
    response = client.post(
        "/api/exercises",
        json=[
            {"id": _BACK_SQUAT, "name": "Back Squat"},
            {"id": _FRONT_SQUAT, "name": "Front Squat", "notes": "keep elbows high"},
        ],
    )
    assert response.status_code == 200
    body = response.json()
    assert {e["id"] for e in body} == {_BACK_SQUAT, _FRONT_SQUAT}

    # Update by same id
    response = client.post(
        "/api/exercises",
        json=[{"id": _BACK_SQUAT, "name": "Low-Bar Back Squat"}],
    )
    assert response.status_code == 200
    assert response.json()[0]["name"] == "Low-Bar Back Squat"

    # List sees 2 exercises still
    response = client.get("/api/exercises")
    assert response.status_code == 200
    names = {e["name"] for e in response.json()}
    assert names == {"Low-Bar Back Squat", "Front Squat"}


def test_list_empty(client) -> None:
    response = client.get("/api/exercises")
    assert response.status_code == 200
    assert response.json() == []


def test_upsert_with_smart_defaults(client) -> None:
    """ExerciseUpsert accepts default_prescription_json + default_alternatives_json."""
    library_prescription = {
        "target_rir": 2,
        "autoreg": {
            "overshoot_at": 2,
            "overshoot_step_kg": 2.5,
            "undershoot_at": 2,
            "undershoot_step_kg": 2.5,
            "apply_to": "remaining",
        },
    }
    library_alternatives = [
        {
            "exercise_id": _FRONT_SQUAT,
            "reason": "bar taken",
            "parameter_overrides_json": None,
        }
    ]

    response = client.post(
        "/api/exercises",
        json=[
            {
                "id": _BACK_SQUAT,
                "name": "Back Squat",
                "default_prescription_json": json.dumps(library_prescription),
                "default_alternatives_json": json.dumps(library_alternatives),
            }
        ],
    )
    assert response.status_code == 200
    body = response.json()[0]
    assert json.loads(body["default_prescription_json"])["target_rir"] == 2
    assert json.loads(body["default_alternatives_json"])[0]["reason"] == "bar taken"

    # Update-by-id preserves / overwrites the defaults appropriately.
    response = client.post(
        "/api/exercises",
        json=[{"id": _BACK_SQUAT, "name": "Back Squat"}],
    )
    assert response.status_code == 200
    body = response.json()[0]
    # Omitting defaults on update clears them (Pydantic field defaults to None).
    assert body["default_prescription_json"] is None
    assert body["default_alternatives_json"] is None


def test_post_exercises_rejects_malformed_default_prescription_json(client) -> None:
    """bug-032 regression: malformed default_prescription_json must 422 at ingest.

    `prescription_merge._load_or_empty` crashes on unparseable JSON, so every
    `POST /api/workouts` referencing this exercise would 500. Fix at the
    write side: reject invalid JSON before the row lands in the DB.
    """
    response = client.post(
        "/api/exercises",
        json=[
            {
                "id": _BACK_SQUAT,
                "name": "Back Squat",
                "default_prescription_json": "not-json",
            }
        ],
    )
    assert response.status_code == 422, response.text
    assert "default_prescription_json" in response.text
    assert "not valid JSON" in response.text


def test_post_exercises_accepts_valid_default_prescription_json(client) -> None:
    """bug-032: a parseable JSON blob (even just `{}`) must be accepted."""
    response = client.post(
        "/api/exercises",
        json=[
            {
                "id": _BACK_SQUAT,
                "name": "Back Squat",
                "default_prescription_json": "{}",
            }
        ],
    )
    assert response.status_code == 200, response.text
    assert response.json()[0]["default_prescription_json"] == "{}"


def test_post_exercises_rejects_malformed_default_alternatives_json(client) -> None:
    """bug-032 regression: same class as prescription_json but for alternatives.

    `merge_alternatives` calls `json.loads` and raises if the column is
    malformed — identical crash path, fix at ingest.
    """
    response = client.post(
        "/api/exercises",
        json=[
            {
                "id": _BACK_SQUAT,
                "name": "Back Squat",
                "default_alternatives_json": "not-an-array {{",
            }
        ],
    )
    assert response.status_code == 422, response.text
    assert "default_alternatives_json" in response.text
    assert "not valid JSON" in response.text


def test_post_exercises_rejects_non_object_default_prescription_json(client) -> None:
    """bug-035: a parseable-but-wrong-shape `default_prescription_json` must 422
    at ingest. `_load_or_empty` in the merge helper requires an object; an
    array or scalar crashes later `POST /api/workouts` calls with a 500.

    Covers both array and string shapes — both parse as valid JSON but would
    explode in `merge_prescriptions`.
    """
    for bad_shape in (
        json.dumps([{"sets": 4}]),  # array
        json.dumps("a scalar string"),  # string
        json.dumps(42),  # number
    ):
        response = client.post(
            "/api/exercises",
            json=[
                {
                    "id": _BACK_SQUAT,
                    "name": "Back Squat",
                    "default_prescription_json": bad_shape,
                }
            ],
        )
        assert response.status_code == 422, response.text
        assert "default_prescription_json" in response.text
        assert "must be a JSON object" in response.text


def test_post_exercises_rejects_non_array_default_alternatives_json(client) -> None:
    """bug-035: parseable-but-wrong-shape `default_alternatives_json` must 422.
    `merge_alternatives` requires a JSON array; anything else crashes the
    workout-build path with a 500.
    """
    for bad_shape in (
        json.dumps({"exercise_id": _FRONT_SQUAT}),  # object
        json.dumps("a string"),  # string
    ):
        response = client.post(
            "/api/exercises",
            json=[
                {
                    "id": _BACK_SQUAT,
                    "name": "Back Squat",
                    "default_alternatives_json": bad_shape,
                }
            ],
        )
        assert response.status_code == 422, response.text
        assert "default_alternatives_json" in response.text
        assert "must be a JSON array" in response.text
