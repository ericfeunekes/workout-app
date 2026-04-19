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
    """If the client sends the same shape the library provides, prescription_json_raw is null.

    R2.10: the client must also author `weight_unit` explicitly for the
    merge to be a true no-op — otherwise the server stamps the "lb"
    default and the canonicalized form differs from the input, which
    preserves the raw payload.
    """
    library = {"target_rir": 2}
    exercise_id = _seed_exercise_with_defaults(
        test_engine, default_prescription_json=json.dumps(library)
    )
    full = {
        "sets": 4,
        "reps": 5,
        "load_kg": 102.5,
        "target_rir": 2,
        "weight_unit": "lb",
    }

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


def test_post_workouts_unknown_exercise_id_returns_422(client, test_engine) -> None:
    """bug-036: workout_item pointing at a non-existent exercise_id must 422,
    not 500. Prior behavior: the FK constraint on `workout_items.exercise_id`
    fired at commit time and bubbled a generic IntegrityError. Now we
    prevalidate in `_build_item()` and raise a specific 422 naming the bad id.
    """
    _seed_exercise(test_engine)  # a real exercise, but we'll reference a different id
    missing_id = "deadbeef-dead-4bee-8bee-beefdeadbeef"

    payload = _workout_payload(_BACK_SQUAT)
    payload["blocks"][0]["workout_items"][0]["exercise_id"] = missing_id
    # Also align the alternative so the only bad ref is the item's exercise_id.
    payload["blocks"][0]["workout_items"][0]["alternatives"] = []

    response = client.post("/api/workouts", json=payload)
    assert response.status_code == 422, response.text
    assert missing_id in response.text
    assert "not found" in response.text


def test_post_workouts_unknown_alternative_exercise_id_returns_422(
    client, test_engine
) -> None:
    """bug-R2.3 follow-up: a client-supplied alternative pointing at a
    non-existent exercise_id must 422, not 500. Prior behavior: the FK
    constraint on `exercise_alternative.exercise_id` fired at commit time
    and bubbled a generic IntegrityError. Now we prevalidate every resolved
    alternative in `_build_item()` BEFORE any DB writes, so the 422 path
    leaves no partial rows.
    """
    _seed_exercise(test_engine)
    missing_id = "deadbeef-dead-4bee-8bee-beefdeadbeef"

    payload = _workout_payload(_BACK_SQUAT)
    # Only the alternative references a bad exercise id.
    payload["blocks"][0]["workout_items"][0]["alternatives"] = [
        {"exercise_id": missing_id, "reason": "bar taken"}
    ]

    response = client.post("/api/workouts", json=payload)
    assert response.status_code == 422, response.text
    assert missing_id in response.text
    assert "alternative" in response.text
    assert "not found" in response.text

    # Transaction cleanliness: no workout row was committed.
    with Session(test_engine) as session:
        from workoutdb_server.models import Workout

        assert session.query(Workout).count() == 0


def test_post_workouts_library_default_alternative_with_unknown_exercise_id_returns_422(
    client, test_engine
) -> None:
    """bug-R2.3 follow-up: a library-default alternative (authored on the
    Exercise's `default_alternatives_json`) that points at a non-existent
    exercise must 422 when the item omits alternatives and the library
    default materializes. Previously this crashed at commit with 500.
    """
    missing_id = "cafebabe-cafe-4bab-8bab-cafebabecafe"
    lib_alts = [
        {
            "exercise_id": missing_id,
            "reason": "library default with stale target",
            "parameter_overrides_json": None,
        }
    ]
    exercise_id = _seed_exercise_with_defaults(
        test_engine,
        default_alternatives_json=json.dumps(lib_alts),
    )

    payload = _workout_payload(exercise_id)
    # Item omits alternatives so library defaults materialize.
    payload["blocks"][0]["workout_items"][0]["alternatives"] = []

    response = client.post("/api/workouts", json=payload)
    assert response.status_code == 422, response.text
    assert missing_id in response.text
    assert "alternative" in response.text
    assert "not found" in response.text

    # Transaction cleanliness: no workout row was committed.
    with Session(test_engine) as session:
        from workoutdb_server.models import Workout

        assert session.query(Workout).count() == 0


def test_library_alternative_id_is_minted_fresh_per_workout(client, test_engine) -> None:
    """bug-034: a library-default alternative carrying an `id` gets a fresh
    UUID minted on every workout materialization. Two workouts sharing the
    same library default must land as two distinct `exercise_alternatives`
    rows on disk — the same id would UNIQUE-crash the second POST.
    """
    lib_alts = [
        {
            # Deliberately carry an `id` — some real-world library defaults
            # ship with one. It must not propagate to stored rows.
            "id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            "exercise_id": _BACK_SQUAT,
            "reason": "bar taken",
            "parameter_overrides_json": None,
        }
    ]
    exercise_id = _seed_exercise_with_defaults(
        test_engine,
        default_alternatives_json=json.dumps(lib_alts),
    )

    # First workout: item omits alternatives so library defaults materialize.
    first = _workout_payload(exercise_id)
    first["id"] = "11111111-1111-4111-8111-111111111111"
    first["blocks"][0]["workout_items"][0]["alternatives"] = []
    resp1 = client.post("/api/workouts", json=first)
    assert resp1.status_code == 200, resp1.text
    first_alts = resp1.json()["blocks"][0]["workout_items"][0]["alternatives"]
    assert len(first_alts) == 1

    # Second workout: same library default. Pre-fix this would UNIQUE-crash
    # with a 500 on the reused alternative id.
    second = _workout_payload(exercise_id)
    second["id"] = "22222222-2222-4222-8222-222222222222"
    second["blocks"][0]["workout_items"][0]["alternatives"] = []
    resp2 = client.post("/api/workouts", json=second)
    assert resp2.status_code == 200, resp2.text
    second_alts = resp2.json()["blocks"][0]["workout_items"][0]["alternatives"]
    assert len(second_alts) == 1

    # The two materialized alternatives must have distinct ids — and neither
    # should echo the library's template id.
    assert first_alts[0]["id"] != second_alts[0]["id"]
    template_id = lib_alts[0]["id"]
    assert first_alts[0]["id"] != template_id
    assert second_alts[0]["id"] != template_id


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


# ---------- qa-017: autoreg.apply_to server-side validation ----------


def _prescription_with_apply_to(apply_to: str) -> str:
    """Build a minimally-valid autoreg prescription pinned to a given apply_to.

    Uses `target_rir` because the spec makes it required when `autoreg` is
    present; keeps the fixture below the check we actually care about.
    """
    return json.dumps(
        {
            "sets": 3,
            "reps": 5,
            "load_kg": 100,
            "target_rir": 2,
            "autoreg": {
                "overshoot_at": 2,
                "overshoot_step_kg": 2.5,
                "undershoot_at": 2,
                "undershoot_step_kg": 2.5,
                "apply_to": apply_to,
            },
        }
    )


def test_post_workout_rejects_apply_to_next(client, test_engine) -> None:
    """qa-017: `apply_to: "next"` is reserved-unimplemented; ingest must 422."""
    exercise_id = _seed_exercise(test_engine)

    payload = _workout_payload(exercise_id)
    payload["blocks"][0]["workout_items"][0]["prescription_json"] = (
        _prescription_with_apply_to("next")
    )

    response = client.post("/api/workouts", json=payload)
    assert response.status_code == 422, response.text
    body_text = response.text
    assert "apply_to" in body_text
    assert "'next'" in body_text or '"next"' in body_text
    # Error points at the offending item so the author can find it.
    assert "blocks[0].workout_items[0]" in body_text

    # Transaction cleanliness: no workout row was committed.
    with Session(test_engine) as session:
        from workoutdb_server.models import Workout

        assert session.query(Workout).count() == 0


def test_post_workout_accepts_apply_to_remaining(client, test_engine) -> None:
    """qa-017: `apply_to: "remaining"` is the only shipped value; ingest succeeds."""
    exercise_id = _seed_exercise(test_engine)

    payload = _workout_payload(exercise_id)
    payload["blocks"][0]["workout_items"][0]["prescription_json"] = (
        _prescription_with_apply_to("remaining")
    )

    response = client.post("/api/workouts", json=payload)
    assert response.status_code == 200, response.text
    body = response.json()
    resolved = json.loads(body["blocks"][0]["workout_items"][0]["prescription_json"])
    assert resolved["autoreg"]["apply_to"] == "remaining"


def test_post_workout_rejects_apply_to_all_future(client, test_engine) -> None:
    """qa-017: `apply_to: "all-future"` is reserved-unimplemented; ingest must 422."""
    exercise_id = _seed_exercise(test_engine)

    payload = _workout_payload(exercise_id)
    payload["blocks"][0]["workout_items"][0]["prescription_json"] = (
        _prescription_with_apply_to("all-future")
    )

    response = client.post("/api/workouts", json=payload)
    assert response.status_code == 422, response.text
    assert "apply_to" in response.text
    assert "all-future" in response.text


def test_post_workout_rejects_apply_to_arbitrary_string(client, test_engine) -> None:
    """qa-017: an arbitrary string (typo, future value) is also rejected."""
    exercise_id = _seed_exercise(test_engine)

    payload = _workout_payload(exercise_id)
    payload["blocks"][0]["workout_items"][0]["prescription_json"] = (
        _prescription_with_apply_to("everywhere")
    )

    response = client.post("/api/workouts", json=payload)
    assert response.status_code == 422, response.text


def test_post_workout_accepts_workout_with_no_autoreg(client, test_engine) -> None:
    """qa-017: prescriptions without an `autoreg` block pass through untouched."""
    exercise_id = _seed_exercise(test_engine)

    # _workout_payload's default prescription has no autoreg sub-object.
    response = client.post("/api/workouts", json=_workout_payload(exercise_id))
    assert response.status_code == 200, response.text


def test_post_workout_accepts_autoreg_without_apply_to(client, test_engine) -> None:
    """qa-017: autoreg present but `apply_to` omitted is fine — the app defaults it."""
    exercise_id = _seed_exercise(test_engine)

    payload = _workout_payload(exercise_id)
    payload["blocks"][0]["workout_items"][0]["prescription_json"] = json.dumps(
        {
            "sets": 3,
            "reps": 5,
            "load_kg": 100,
            "target_rir": 2,
            "autoreg": {"overshoot_at": 2, "overshoot_step_kg": 2.5},
        }
    )

    response = client.post("/api/workouts", json=payload)
    assert response.status_code == 200, response.text


def test_put_workout_rejects_invalid_apply_to(client, test_engine) -> None:
    """qa-017: the PUT path runs the same merge+validate pipeline; same 422."""
    exercise_id = _seed_exercise(test_engine)
    created = client.post("/api/workouts", json=_workout_payload(exercise_id)).json()

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
                        "prescription_json": _prescription_with_apply_to("next"),
                        "alternatives": [],
                    }
                ],
            }
        ]
    }
    response = client.put(f"/api/workouts/{created['id']}", json=put_payload)
    assert response.status_code == 422, response.text
    assert "apply_to" in response.text
    assert "blocks[0].workout_items[0]" in response.text


def test_post_workout_rejects_apply_to_from_library_default(client, test_engine) -> None:
    """qa-017: a library-default `apply_to` that violates is caught post-merge.

    Smart-defaults (ADR-2026-04-18) merge library fields into the item's
    prescription at ingest. The client payload here has no `apply_to`, but
    the merged result does — and it's invalid. The validator runs AFTER
    the merge so it catches both authoring paths (client-side + Claude's
    library defaults) in one place.
    """
    library = {
        "target_rir": 2,
        "autoreg": {
            "overshoot_at": 2,
            "overshoot_step_kg": 2.5,
            "apply_to": "all-future",  # library-authored violation
        },
    }
    exercise_id = _seed_exercise_with_defaults(
        test_engine, default_prescription_json=json.dumps(library)
    )

    payload = _workout_payload(exercise_id)
    # Client sends a sparse item with no autoreg — the merge pulls it in.
    payload["blocks"][0]["workout_items"][0]["prescription_json"] = json.dumps(
        {"sets": 3, "reps": 5, "load_kg": 100}
    )
    payload["blocks"][0]["workout_items"][0]["alternatives"] = []

    response = client.post("/api/workouts", json=payload)
    assert response.status_code == 422, response.text
    assert "apply_to" in response.text
    assert "all-future" in response.text


def test_post_workout_rejects_nested_invalid_apply_to_in_block_item(client, test_engine) -> None:
    """qa-017: the validator targets the right item inside a multi-block tree.

    A healthy item on block 0 sits alongside a violating item on block 1.
    The error message must point at block 1 / item 0 so the author can
    find the offender — NOT just say "somewhere in this workout."
    """
    exercise_id = _seed_exercise(test_engine)

    payload = _workout_payload(exercise_id)
    # Append a second block whose sole item carries the invalid apply_to.
    payload["blocks"].append(
        {
            "position": 1,
            "name": "Accessories",
            "timing_mode": "straight_sets",
            "timing_config_json": "{}",
            "workout_items": [
                {
                    "position": 0,
                    "exercise_id": exercise_id,
                    "prescription_json": _prescription_with_apply_to("next"),
                    "alternatives": [],
                }
            ],
        }
    )

    response = client.post("/api/workouts", json=payload)
    assert response.status_code == 422, response.text
    assert "blocks[1].workout_items[0]" in response.text
    assert "apply_to" in response.text

    # Transaction cleanliness: no partial row from the healthy block 0.
    with Session(test_engine) as session:
        from workoutdb_server.models import Workout

        assert session.query(Workout).count() == 0


def test_api_workouts_rejects_non_Z_timestamp(client, test_engine) -> None:
    """`UtcDatetimeIn` must reject `+00:00` on workout `completed_at` too.

    Parity with `test_telemetry_rejects_non_Z_timestamp` — every Write/Update
    schema shares the same validator. A client that slipped through the
    telemetry regression but stayed on the old `datetime` parser here would
    still corrupt the invariant, so both paths carry a guard.
    """
    exercise_id = _seed_exercise(test_engine)
    create = client.post("/api/workouts", json=_workout_payload(exercise_id))
    assert create.status_code == 200
    workout_id = create.json()["id"]

    response = client.put(
        f"/api/workouts/{workout_id}",
        json={"status": "completed", "completed_at": "2026-04-18T12:00:00+00:00"},
    )
    assert response.status_code == 422, response.text
    body = response.json()
    assert any("completed_at" in str(err).lower() for err in body["detail"])
