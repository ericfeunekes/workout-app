"""/api/workouts — nested create, update, list with filters, get by id.

The authenticated user_id comes from the bearer token (conftest seeds it as test_user_id).
"""

import json

from sqlalchemy.orm import Session
from workoutdb_server.models import AppUser, Exercise

# Canonical test UUIDs. Per docs/specs/v2-architecture.md, all entity ids are UUIDs.
_BACK_SQUAT = "e0000001-0000-4000-8000-000000000001"
_OTHER_USER = "e0000009-0000-4000-8000-000000000009"
_NONEXISTENT_WORKOUT = "00000000-0000-4000-8000-000000000000"


def _seed_exercise(engine) -> str:
    with Session(engine) as session:
        exercise = Exercise(id=_BACK_SQUAT, name="Back Squat")
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
    response = client.get(f"/api/workouts/{_NONEXISTENT_WORKOUT}")
    assert response.status_code == 404


def test_get_rejects_another_users_workout(client, test_engine, test_user_id) -> None:
    """Tenant isolation: workouts owned by a different user_id must 404, not leak."""
    _seed_exercise(test_engine)
    with Session(test_engine) as session:
        other = AppUser(id=_OTHER_USER, name="Other")
        session.add(other)
        session.commit()

    # Directly insert a workout owned by the other user so we bypass the auth'd POST.
    with Session(test_engine) as session:
        from workoutdb_server.models import Workout

        w = Workout(
            user_id=_OTHER_USER,
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
        f"reached workout owned by {_OTHER_USER}"
    )


def test_update_missing_workout_404(client, test_engine) -> None:
    """PUT /api/workouts/:id on a non-existent id must 404, not create/leak."""
    _seed_exercise(test_engine)
    response = client.put(
        f"/api/workouts/{_NONEXISTENT_WORKOUT}",
        json={"name": "does-not-exist"},
    )
    assert response.status_code == 404
    # Response must not leak the nonexistent ID back (low value but cheap to
    # pin — guards against shell-injected error messages in the future).
    body_text = response.text.lower()
    assert "does-not-exist" not in body_text


def test_update_rejects_another_users_workout(client, test_engine) -> None:
    """Tenant isolation on PUT: updating someone else's workout must 404.

    The 404 body must NOT disclose the owning user ID or any "owned by X"
    framing — the authorized user should be unable to distinguish "not
    found" from "belongs to someone else" via the response payload. This
    guards against information leaks if a future refactor flips the
    handler's order-of-checks (existence vs. ownership).
    """
    _seed_exercise(test_engine)
    with Session(test_engine) as session:
        session.add(AppUser(id=_OTHER_USER, name="Other"))
        session.commit()

    with Session(test_engine) as session:
        from workoutdb_server.models import Workout

        w = Workout(
            user_id=_OTHER_USER,
            name="Private",
            status="planned",
            source="claude",
        )
        session.add(w)
        session.commit()
        other_workout_id = w.id

    response = client.put(
        f"/api/workouts/{other_workout_id}",
        json={"name": "hijack"},
    )
    assert response.status_code == 404
    body_text = response.text
    # No leak of the other user's UUID, the workout's own UUID, or ownership
    # framing. All three would let an attacker map the ID-space indirectly.
    assert _OTHER_USER not in body_text
    assert other_workout_id not in body_text
    assert "owned by" not in body_text.lower()
    assert "another user" not in body_text.lower()
    assert "Private" not in body_text


def test_create_workout_malformed_input_422(client, test_engine) -> None:
    """Pydantic validation failures surface as 422 with structured detail (FastAPI default)."""
    _seed_exercise(test_engine)
    # Missing required fields (name, status, source, blocks) → Pydantic rejects.
    response = client.post("/api/workouts", json={"scheduled_date": "2026-04-20"})
    assert response.status_code == 422
    body = response.json()
    assert "detail" in body
    assert isinstance(body["detail"], list)


def _seed_exercise_with_defaults(
    engine,
    default_prescription_json: str | None = None,
    default_alternatives_json: str | None = None,
) -> str:
    """Seed the canonical test exercise with smart-defaults populated."""
    with Session(engine) as session:
        exercise = Exercise(
            id=_BACK_SQUAT,
            name="Back Squat",
            default_prescription_json=default_prescription_json,
            default_alternatives_json=default_alternatives_json,
        )
        session.add(exercise)
        session.commit()
        return exercise.id


def test_smart_defaults_resolve_prescription_on_create(client, test_engine) -> None:
    """Sparse client payload + library defaults → resolved form stored + raw preserved."""
    library = {
        "target_rir": 2,
        "autoreg": {
            "overshoot_at": 2,
            "overshoot_step_kg": 2.5,
            "undershoot_at": 2,
            "undershoot_step_kg": 2.5,
            "apply_to": "remaining",
        },
    }
    exercise_id = _seed_exercise_with_defaults(
        test_engine, default_prescription_json=json.dumps(library)
    )
    sparse = {"sets": 4, "reps": 5, "load_kg": 102.5}

    payload = _workout_payload(exercise_id)
    payload["blocks"][0]["workout_items"][0]["prescription_json"] = json.dumps(sparse)
    payload["blocks"][0]["workout_items"][0]["alternatives"] = []

    body = client.post("/api/workouts", json=payload).json()
    item = body["blocks"][0]["workout_items"][0]
    resolved = json.loads(item["prescription_json"])

    assert resolved["sets"] == 4
    assert resolved["reps"] == 5
    assert resolved["load_kg"] == 102.5
    assert resolved["target_rir"] == 2
    assert resolved["autoreg"]["apply_to"] == "remaining"
    # Raw preserved because the resolved form added fields.
    assert item["prescription_json_raw"] is not None
    assert json.loads(item["prescription_json_raw"]) == sparse


def test_smart_defaults_library_fallback_alternatives(client, test_engine) -> None:
    """Item omits alternatives → library defaults are materialized into stored rows."""
    lib_alts = [
        {
            "exercise_id": _BACK_SQUAT,
            "reason": "library default",
            "parameter_overrides_json": None,
        }
    ]
    exercise_id = _seed_exercise_with_defaults(
        test_engine,
        default_alternatives_json=json.dumps(lib_alts),
    )
    payload = _workout_payload(exercise_id)
    payload["blocks"][0]["workout_items"][0]["alternatives"] = []

    body = client.post("/api/workouts", json=payload).json()
    alts = body["blocks"][0]["workout_items"][0]["alternatives"]

    assert len(alts) == 1
    assert alts[0]["reason"] == "library default"
    # Assigned a UUID at insert time.
    assert alts[0]["id"]


def test_smart_defaults_noop_when_payload_fully_resolved(client, test_engine) -> None:
    """If the client sends the same shape the library provides, prescription_json_raw is null."""
    library = {"target_rir": 2}
    exercise_id = _seed_exercise_with_defaults(
        test_engine, default_prescription_json=json.dumps(library)
    )
    full = {"sets": 4, "reps": 5, "load_kg": 102.5, "target_rir": 2}

    payload = _workout_payload(exercise_id)
    payload["blocks"][0]["workout_items"][0]["prescription_json"] = json.dumps(full)
    payload["blocks"][0]["workout_items"][0]["alternatives"] = []

    body = client.post("/api/workouts", json=payload).json()
    item = body["blocks"][0]["workout_items"][0]

    assert item["prescription_json_raw"] is None
    resolved = json.loads(item["prescription_json"])
    assert resolved == full


def test_smart_defaults_repost_is_idempotent(client, test_engine) -> None:
    """Re-POSTing the same sparse workout re-merges against current library — no drift."""
    library = {"target_rir": 2, "autoreg": {"overshoot_step_kg": 2.5}}
    exercise_id = _seed_exercise_with_defaults(
        test_engine, default_prescription_json=json.dumps(library)
    )
    sparse = {"sets": 4, "reps": 5, "load_kg": 100}
    payload = _workout_payload(exercise_id)
    payload["id"] = "99999999-9999-4999-8999-999999999999"
    payload["blocks"][0]["workout_items"][0]["prescription_json"] = json.dumps(sparse)
    payload["blocks"][0]["workout_items"][0]["alternatives"] = []

    first = client.post("/api/workouts", json=payload).json()
    first_resolved = first["blocks"][0]["workout_items"][0]["prescription_json"]

    # Re-POST same payload — different workout id gets created; resolved form
    # must be byte-identical because the merge is deterministic.
    payload["id"] = "88888888-8888-4888-8888-888888888888"
    second = client.post("/api/workouts", json=payload).json()
    second_resolved = second["blocks"][0]["workout_items"][0]["prescription_json"]

    assert first_resolved == second_resolved


def test_smart_defaults_library_mutation_does_not_rewrite_history(client, test_engine) -> None:
    """POST a workout; mutate the exercise's default; re-GET original workout — unchanged."""
    library = {"target_rir": 2, "autoreg": {"overshoot_step_kg": 2.5}}
    exercise_id = _seed_exercise_with_defaults(
        test_engine, default_prescription_json=json.dumps(library)
    )
    sparse = {"sets": 4, "reps": 5, "load_kg": 100}
    payload = _workout_payload(exercise_id)
    payload["blocks"][0]["workout_items"][0]["prescription_json"] = json.dumps(sparse)
    payload["blocks"][0]["workout_items"][0]["alternatives"] = []

    created = client.post("/api/workouts", json=payload).json()
    original_resolved = created["blocks"][0]["workout_items"][0]["prescription_json"]

    # Claude rewrites the library default with a different shape.
    new_library = {"target_rir": 3, "autoreg": {"overshoot_step_kg": 5.0}}
    client.post(
        "/api/exercises",
        json=[
            {
                "id": exercise_id,
                "name": "Back Squat",
                "default_prescription_json": json.dumps(new_library),
            }
        ],
    )

    # Re-GET the original workout — resolved form must be exactly what the
    # first POST produced. Snapshot immutability is the whole point of the ADR.
    refetched = client.get(f"/api/workouts/{created['id']}").json()
    refetched_resolved = refetched["blocks"][0]["workout_items"][0]["prescription_json"]
    assert refetched_resolved == original_resolved


def test_smart_defaults_put_re_merges_against_current_library(client, test_engine) -> None:
    """PUT with sparse prescription re-merges against the *current* library defaults."""
    library_v1 = {"target_rir": 2}
    exercise_id = _seed_exercise_with_defaults(
        test_engine, default_prescription_json=json.dumps(library_v1)
    )
    created = client.post(
        "/api/workouts",
        json=_workout_payload(exercise_id),
    ).json()

    # Mutate the library.
    library_v2 = {"target_rir": 3}
    client.post(
        "/api/exercises",
        json=[
            {
                "id": exercise_id,
                "name": "Back Squat",
                "default_prescription_json": json.dumps(library_v2),
            }
        ],
    )

    # PUT with a sparse prescription — should pick up v2 library default.
    put_payload = {
        "blocks": [
            {
                "position": 0,
                "timing_mode": "straight_sets",
                "timing_config_json": "{}",
                "workout_items": [
                    {
                        "position": 0,
                        "exercise_id": exercise_id,
                        "prescription_json": json.dumps({"sets": 3, "reps": 5, "load_kg": 110}),
                        "alternatives": [],
                    }
                ],
            }
        ]
    }
    edited = client.put(f"/api/workouts/{created['id']}", json=put_payload).json()
    resolved = json.loads(edited["blocks"][0]["workout_items"][0]["prescription_json"])
    assert resolved["target_rir"] == 3  # picked up library v2


def test_post_workouts_repost_with_existing_id_upserts(client, test_engine) -> None:
    """bug-041: POST /api/workouts with an id that already exists for this
    user upserts in place — returns 200, not 500, and the scalar fields reflect
    the latest payload. Prior behavior was a PK constraint crash.
    """
    exercise_id = _seed_exercise(test_engine)

    stable_id = "a0000001-0000-4000-8000-000000000001"
    first = _workout_payload(exercise_id)
    first["id"] = stable_id
    first["name"] = "Original"

    resp1 = client.post("/api/workouts", json=first)
    assert resp1.status_code == 200
    assert resp1.json()["id"] == stable_id
    assert resp1.json()["name"] == "Original"

    # Re-POST same id with different scalar fields → 200 + DB reflects update.
    second = _workout_payload(exercise_id)
    second["id"] = stable_id
    second["name"] = "Renamed"
    second["status"] = "completed"
    second["tags_json"] = '["repost"]'

    resp2 = client.post("/api/workouts", json=second)
    assert resp2.status_code == 200
    body = resp2.json()
    assert body["id"] == stable_id
    assert body["name"] == "Renamed"
    assert body["status"] == "completed"
    assert body["tags_json"] == '["repost"]'

    # GET confirms persistence.
    refetched = client.get(f"/api/workouts/{stable_id}").json()
    assert refetched["name"] == "Renamed"
    assert refetched["status"] == "completed"


def test_post_workouts_repost_replaces_blocks(client, test_engine) -> None:
    """bug-041: re-POST with a different blocks tree replaces the old tree
    in place — no stranded orphan blocks, new blocks present. Mirrors the
    composition-matrix seeder's re-seed flow that originally surfaced the
    two-phase PUT workaround.
    """
    exercise_id = _seed_exercise(test_engine)
    stable_id = "b0000002-0000-4000-8000-000000000002"

    first = _workout_payload(exercise_id)
    first["id"] = stable_id
    resp1 = client.post("/api/workouts", json=first)
    assert resp1.status_code == 200
    assert len(resp1.json()["blocks"]) == 1
    original_block_timing = resp1.json()["blocks"][0]["timing_mode"]
    assert original_block_timing == "straight_sets"

    # Re-POST with a different blocks shape (tabata instead of straight_sets,
    # no workout items).
    second = _workout_payload(exercise_id)
    second["id"] = stable_id
    second["blocks"] = [
        {
            "position": 0,
            "timing_mode": "tabata",
            "timing_config_json": "{}",
            "workout_items": [],
        }
    ]
    resp2 = client.post("/api/workouts", json=second)
    assert resp2.status_code == 200
    body = resp2.json()
    assert len(body["blocks"]) == 1, "old blocks should be replaced, not appended"
    assert body["blocks"][0]["timing_mode"] == "tabata"
    assert body["blocks"][0]["workout_items"] == []

    # GET confirms the blocks survived — prior to the fix, a fraction of
    # re-POSTs landed with blocks: [] due to the cascade delete-orphan
    # flush-ordering issue.
    refetched = client.get(f"/api/workouts/{stable_id}").json()
    assert len(refetched["blocks"]) == 1
    assert refetched["blocks"][0]["timing_mode"] == "tabata"


def test_post_workouts_repost_rejects_another_users_id(client, test_engine) -> None:
    """bug-041 tenant isolation: POST with an id owned by another user must
    404, not overwrite that user's workout.
    """
    exercise_id = _seed_exercise(test_engine)
    other_id = "c0000003-0000-4000-8000-000000000003"

    with Session(test_engine) as session:
        session.add(AppUser(id=_OTHER_USER, name="Other"))
        session.commit()

    with Session(test_engine) as session:
        from workoutdb_server.models import Workout

        other = Workout(
            id=other_id,
            user_id=_OTHER_USER,
            name="Someone Else's",
            status="planned",
            source="claude",
        )
        session.add(other)
        session.commit()

    payload = _workout_payload(exercise_id)
    payload["id"] = other_id
    payload["name"] = "hijack"
    resp = client.post("/api/workouts", json=payload)
    assert resp.status_code == 404
    # And the original row is untouched.
    with Session(test_engine) as session:
        from workoutdb_server.models import Workout

        still = session.get(Workout, other_id)
        assert still is not None
        assert still.name == "Someone Else's"
        assert still.user_id == _OTHER_USER


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
