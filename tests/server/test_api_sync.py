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

# Canonical test UUIDs. Per docs/specs/v2-architecture.md, all entity ids are UUIDs.
_BACK_SQUAT = "e0000001-0000-4000-8000-000000000001"
_FRONT_SQUAT = "e0000002-0000-4000-8000-000000000002"
_OHP = "e0000004-0000-4000-8000-000000000004"
_OTHER_USER = "e0000009-0000-4000-8000-000000000009"
_NONEXISTENT_WORKOUT = "00000000-0000-4000-8000-000000000000"


def _seed_completed_workout(engine, user_id: str) -> tuple[str, str]:
    """Returns (exercise_id, workout_item_id). `user_id` is the auth'd user."""
    with Session(engine) as session:
        exercise = Exercise(id=_BACK_SQUAT, name="Back Squat")
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
    assert body["exercises"][0]["id"] == _BACK_SQUAT
    assert len(body["user_parameters"]) == 1
    assert body["user_parameters"][0]["key"] == "bodyweight_kg"

    # last_performed contains the completed session's logs
    assert len(body["last_performed"]) == 1
    last = body["last_performed"][0]
    assert last["exercise_id"] == _BACK_SQUAT
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
                    "rir": 2,
                    "skipped": True,
                    "side": "left",
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


def test_workout_status_update_persists_notes(client, test_engine, test_user_id) -> None:
    """Terminal status push must persist `notes` so the server is authoritative.

    Regression: the iOS Complete screen's note used to land ONLY in the
    local cache. The workout's `updated_at` still bumped (status flipped to
    completed), so the next incremental sync_pull re-materialized the
    Workout with the server's nil `notes` and DomainMapping overwrote the
    cache's freshly-typed note. Fix: carry `notes` on WorkoutStatusUpdate
    so the server stores it, which keeps the next pull aligned with what
    the user typed.
    """
    exercise_id, _ = _seed_completed_workout(test_engine, test_user_id)
    future_id = _create_future_workout(client, exercise_id)

    response = client.post(
        "/api/sync/results",
        json={
            "set_logs": [],
            "status_updates": [
                {
                    "workout_id": future_id,
                    "status": "completed",
                    "completed_at": "2026-04-20T08:00:00Z",
                    "notes": "leg day PR!",
                }
            ],
        },
    )
    assert response.status_code == 200

    detail = client.get(f"/api/workouts/{future_id}").json()
    assert detail["status"] == "completed"
    assert detail["notes"] == "leg day PR!"

    # A second pull of the same workout must still carry the note —
    # previous bug was the pull overwriting the local cache's value.
    pulled = client.get("/api/sync/pull").json()
    pulled_workout = next(w for w in pulled["workouts"] if w["id"] == future_id)
    assert pulled_workout["notes"] == "leg day PR!"


def test_workout_status_update_none_notes_leaves_existing_alone(
    client, test_engine, test_user_id
) -> None:
    """Status push without `notes` (or with `notes=null`) MUST NOT clobber
    an existing server-side note. Non-terminal flips (e.g. `active`) pass
    nil; those must be no-ops on the notes column.
    """
    exercise_id, _ = _seed_completed_workout(test_engine, test_user_id)
    future_id = _create_future_workout(client, exercise_id)

    # First push: record a note via the completed push.
    client.post(
        "/api/sync/results",
        json={
            "set_logs": [],
            "status_updates": [
                {
                    "workout_id": future_id,
                    "status": "completed",
                    "completed_at": "2026-04-20T08:00:00Z",
                    "notes": "felt strong",
                }
            ],
        },
    )
    assert client.get(f"/api/workouts/{future_id}").json()["notes"] == "felt strong"

    # Second push without `notes` in the body — server keeps the existing value.
    response = client.post(
        "/api/sync/results",
        json={
            "set_logs": [],
            "status_updates": [
                {
                    "workout_id": future_id,
                    "status": "completed",
                    "completed_at": "2026-04-20T08:05:00Z",
                }
            ],
        },
    )
    assert response.status_code == 200
    assert client.get(f"/api/workouts/{future_id}").json()["notes"] == "felt strong"

    # Explicit null behaves the same — "not provided" and "null" both mean
    # "don't touch the existing value".
    response = client.post(
        "/api/sync/results",
        json={
            "set_logs": [],
            "status_updates": [
                {
                    "workout_id": future_id,
                    "status": "completed",
                    "completed_at": "2026-04-20T08:06:00Z",
                    "notes": None,
                }
            ],
        },
    )
    assert response.status_code == 200
    assert client.get(f"/api/workouts/{future_id}").json()["notes"] == "felt strong"


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
        session.add(Exercise(id=_BACK_SQUAT, name="Back Squat"))
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
                        "exercise_id": _BACK_SQUAT,
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
                        "exercise_id": _BACK_SQUAT,
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
    # Smart-defaults merge re-serializes with sort_keys + compact separators;
    # assert on the key/value pair rather than a whitespace-specific literal.
    assert '"load_kg":110' in pj


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


def test_set_log_round_trips_duration_distance_hr_cadence(
    client, test_engine, test_user_id
) -> None:
    """Cardio fields (`duration_sec`, `distance_m`, `hr_avg_bpm`, `cadence_avg_spm`,
    `started_at`) must round-trip cleanly through /api/sync/results and
    /api/sync/pull. These are the columns the iOS `IntervalsDriver` /
    `ContinuousDriver` now populate via `.logCardioSet`.
    """
    exercise_id, _ = _seed_completed_workout(test_engine, test_user_id)
    future_id = _create_future_workout(client, exercise_id)
    item_id = client.get(f"/api/workouts/{future_id}").json()["blocks"][0][
        "workout_items"
    ][0]["id"]

    log_id = "cadec1a0-0000-4000-8000-000000000001"
    response = client.post(
        "/api/sync/results",
        json={
            "set_logs": [
                {
                    "id": log_id,
                    "workout_item_id": item_id,
                    "set_index": 1,
                    # No reps / weight / rir — cardio row.
                    "duration_sec": 96.5,
                    "distance_m": 400.0,
                    "hr_avg_bpm": 165,
                    "cadence_avg_spm": 184,
                    "started_at": "2026-04-20T07:29:00Z",
                    "completed_at": "2026-04-20T07:30:36Z",
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

    with Session(test_engine) as session:
        row = session.query(SetLog).filter_by(id=log_id).one()
        assert row.duration_sec == 96.5
        assert row.distance_m == 400.0
        assert row.hr_avg_bpm == 165
        assert row.cadence_avg_spm == 184
        assert row.reps is None
        assert row.weight is None
        assert row.rir is None
        assert row.started_at is not None

    # The pull path must surface every cardio column. `last_performed`
    # is the path the iOS `LastPerformed` UI reads — if cardio columns
    # dropped anywhere between ORM and wire this test would fail on
    # the Read-side schema.
    body = client.get("/api/sync/pull").json()
    last = next(
        lp for lp in body["last_performed"] if lp["exercise_id"] == exercise_id
    )
    log = next(sl for sl in last["last_set_logs"] if sl["id"] == log_id)
    assert log["duration_sec"] == 96.5
    assert log["distance_m"] == 400.0
    assert log["hr_avg_bpm"] == 165
    assert log["cadence_avg_spm"] == 184
    assert log["reps"] is None
    assert log["weight"] is None
    assert log["started_at"] == "2026-04-20T07:29:00Z"


def test_pull_last_performed_covers_alternatives(client, test_engine, test_user_id) -> None:
    """A user can swap to an alternative mid-workout; the app needs its history too."""
    # Seed: a completed front-squat session (this will be the alternative).
    with Session(test_engine) as session:
        back_squat = Exercise(id=_BACK_SQUAT, name="Back Squat")
        front_squat = Exercise(id=_FRONT_SQUAT, name="Front Squat")
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
                            "exercise_id": _BACK_SQUAT,
                            "prescription_json": "{}",
                            "alternatives": [
                                {
                                    "exercise_id": _FRONT_SQUAT,
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
    assert _FRONT_SQUAT in exercise_ids, (
        "sync/pull must include last_performed for exercises referenced only as alternatives"
    )


def test_incremental_pull_still_returns_last_performed(
    client, test_engine, test_user_id
) -> None:
    """qa-001 regression: an incremental pull with no delta workouts must still include
    `last_performed` for every exercise in the user's catalog.

    Earlier the snapshot was scoped to the workouts returned by the delta, so a pull
    with `since >= latest_updated_at` (the steady state when the user hasn't asked
    Claude for new work yet) returned an empty list. The iOS client's cold-launch
    save path overwrote its local store with that empty list, erasing every "LAST · …"
    chip until a full pull was forced.
    """
    # Seed one completed workout so there's history to surface.
    exercise_id, _ = _seed_completed_workout(test_engine, test_user_id)

    # Full pull establishes a baseline `server_time`.
    first = client.get("/api/sync/pull").json()
    assert any(lp["exercise_id"] == exercise_id for lp in first["last_performed"])
    baseline_server_time = first["server_time"]

    # Incremental pull with `since = server_time`. No workouts changed in the
    # interval, so `workouts` should be empty. `last_performed` must NOT be —
    # the client relies on this snapshot to rebuild its chip map every launch.
    second = client.get(f"/api/sync/pull?since={baseline_server_time}").json()
    assert second["workouts"] == [], (
        "setup sanity: with no updates since baseline, the delta must be empty"
    )
    assert any(lp["exercise_id"] == exercise_id for lp in second["last_performed"]), (
        "incremental pull must still include last_performed for prior exercises; "
        "returning [] erases every LAST · chip on the client"
    )


def test_push_set_log_for_missing_workout_item_404(client) -> None:
    """A set_log referencing a non-existent workout_item_id must 404, not silently drop."""
    response = client.post(
        "/api/sync/results",
        json={
            "set_logs": [
                {
                    "id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
                    "workout_item_id": _NONEXISTENT_WORKOUT,
                    "set_index": 1,
                    "completed_at": "2026-04-20T07:30:00Z",
                }
            ],
            "status_updates": [],
        },
    )
    assert response.status_code == 404
    # Detail mentions the offending workout_item_id so the app can surface a useful error.
    assert _NONEXISTENT_WORKOUT in response.json()["detail"]


def test_push_results_malformed_input_422(client) -> None:
    """Malformed sync/results payload returns 422 (FastAPI default) with structured detail."""
    response = client.post(
        "/api/sync/results",
        json={"set_logs": "not-a-list", "status_updates": []},
    )
    assert response.status_code == 422
    assert "detail" in response.json()


def test_push_status_for_missing_workout_404(client) -> None:
    response = client.post(
        "/api/sync/results",
        json={
            "set_logs": [],
            "status_updates": [
                {"workout_id": _NONEXISTENT_WORKOUT, "status": "completed"},
            ],
        },
    )
    assert response.status_code == 404


def test_push_rejects_cross_tenant_set_log(client, test_engine) -> None:
    """A set_log for another user's workout_item must 404 — tenant isolation."""
    with Session(test_engine) as session:
        other = AppUser(id=_OTHER_USER, name="Other")
        exercise = Exercise(id=_OHP, name="OHP")
        session.add_all([other, exercise])
        session.flush()
        workout = Workout(
            user_id=_OTHER_USER,
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


def test_sync_results_mixed_ownership_rejects_foreign_items(
    client, test_engine, test_user_id
) -> None:
    """Batched set_logs: one foreign workout_item mixed with own items must reject all.

    Regression guard for perf-007: the ownership check was refactored from a
    per-row `db.get(WorkoutItem, ...)` loop into a single batched query that
    builds an `{item_id: owner_user_id}` map. If the map build drops the
    tenant check (e.g. forgets to compare against the auth'd user) or the
    loop forgets to validate on lookup hit, a foreign item could slip in
    next to a valid own item. The batch must 404 as a whole — not partially
    commit.
    """
    own_exercise_id, own_item_id = _seed_completed_workout(test_engine, test_user_id)

    # Seed a workout for a different user with its own workout_item.
    with Session(test_engine) as session:
        session.add(AppUser(id=_OTHER_USER, name="Other"))
        session.add(Exercise(id=_OHP, name="OHP"))
        session.flush()
        foreign_workout = Workout(
            user_id=_OTHER_USER,
            name="Other's workout",
            status="planned",
            source="claude",
        )
        session.add(foreign_workout)
        session.flush()
        foreign_block = Block(
            workout_id=foreign_workout.id,
            position=0,
            timing_mode="straight_sets",
            timing_config_json="{}",
        )
        session.add(foreign_block)
        session.flush()
        foreign_item = WorkoutItem(
            block_id=foreign_block.id,
            position=0,
            exercise_id=_OHP,
            prescription_json="{}",
        )
        session.add(foreign_item)
        session.commit()
        foreign_item_id = foreign_item.id

    own_log_id = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    foreign_log_id = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"

    response = client.post(
        "/api/sync/results",
        json={
            "set_logs": [
                {
                    "id": own_log_id,
                    "workout_item_id": own_item_id,
                    "set_index": 1,
                    "reps": 5,
                    "weight": 100.0,
                    "weight_unit": "kg",
                    "completed_at": "2026-04-20T07:30:00Z",
                },
                {
                    "id": foreign_log_id,
                    "workout_item_id": foreign_item_id,
                    "set_index": 1,
                    "reps": 5,
                    "weight": 100.0,
                    "weight_unit": "kg",
                    "completed_at": "2026-04-20T07:31:00Z",
                },
            ],
            "status_updates": [],
        },
    )
    assert response.status_code == 404, response.text
    assert foreign_item_id in response.json()["detail"]

    # Neither log must have been persisted — SQLAlchemy's rollback on the
    # raised HTTPException keeps the whole batch atomic.
    with Session(test_engine) as session:
        assert session.get(SetLog, own_log_id) is None
        assert session.get(SetLog, foreign_log_id) is None


def test_sync_results_rejects_malformed_uuid(client, test_user_id):
    """bug-030 regression: posting a non-UUID string in `id` must 422, not silently insert.

    Before the fix, the UUID-normalizing base lowercased the string but did
    not validate UUID format — so `"id": "not-a-uuid"` returned 200 and
    inserted the raw string as primary key, corrupting the event_log /
    set_log table. Input-side schemas now inherit `_UuidInputBase`, which
    enforces format.
    """
    response = client.post(
        "/api/sync/results",
        json={
            "set_logs": [
                {
                    "id": "not-a-uuid",
                    "workout_item_id": "c0000001-0000-4000-8000-000000000001",
                    "set_index": 1,
                    "reps": 5,
                    "weight": 100.0,
                    "weight_unit": "kg",
                    "completed_at": "2026-04-20T07:30:00Z",
                }
            ],
            "status_updates": [],
        },
    )
    assert response.status_code == 422, response.text
    assert "not a valid UUID" in response.text.lower() or "uuid" in response.text.lower()


def test_sync_pull_tolerates_legacy_non_uuid_exercise_id(client, test_engine, test_user_id):
    """bug-031 regression: Read-side schemas must trust the DB, not revalidate UUIDs.

    bug-030's fix (reject malformed UUIDs at ingest) accidentally also ran on
    ORM → Pydantic conversions during sync_pull. Any pre-existing non-UUID
    id in the DB (seed data, legacy imports, test fixtures) 500'd the pull
    with `ValidationError: exercise_id is not a valid UUID: 'ex-0'`. The fix
    split the base class: `_UuidInputBase` enforces format at write time,
    `_UuidReadBase` only lowercases on read — the DB is trusted.
    """
    legacy_exercise_id = "ex-0"
    with Session(test_engine) as session:
        session.add(Exercise(id=legacy_exercise_id, name="Legacy Exercise"))
        session.flush()
        workout = Workout(
            user_id=test_user_id,
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
            exercise_id=legacy_exercise_id,
            prescription_json="{}",
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
        session.commit()

    response = client.get("/api/sync/pull")
    assert response.status_code == 200, response.text
    body = response.json()

    # Legacy id round-trips unchanged (already lowercase, not rejected).
    exercise_ids = {e["id"] for e in body["exercises"]}
    assert legacy_exercise_id in exercise_ids
    last_performed_ids = {lp["exercise_id"] for lp in body["last_performed"]}
    assert legacy_exercise_id in last_performed_ids


def test_sync_results_rejects_malformed_workout_item_id(client, test_user_id):
    """Same class as test_sync_results_rejects_malformed_uuid but for a *_id field.

    Any UUID-typed field the `_UuidInputBase` validator covers must reject
    malformed strings identically, not just the primary `id` column.
    """
    response = client.post(
        "/api/sync/results",
        json={
            "set_logs": [
                {
                    "id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                    "workout_item_id": "this-is-not-a-uuid-either",
                    "set_index": 1,
                    "reps": 5,
                    "weight": 100.0,
                    "weight_unit": "kg",
                    "completed_at": "2026-04-20T07:30:00Z",
                }
            ],
            "status_updates": [],
        },
    )
    assert response.status_code == 422, response.text
