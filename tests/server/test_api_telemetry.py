"""/api/telemetry/events — batch telemetry ingest.

Covers: happy path (batch accepted), idempotent upsert (same id twice),
auth required, cross-tenant isolation (user cannot write another user's
events).
"""

from datetime import datetime

from sqlalchemy.orm import Session
from workoutdb_server.models import AppUser, EventLog

_SESSION_ID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
_EVENT_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
_EVENT_B = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
_OTHER_USER = "e0000009-0000-4000-8000-000000000009"


def _event(event_id: str, name: str = "today.start_tap") -> dict:
    return {
        "id": event_id,
        "timestamp": "2026-04-18T14:32:15Z",
        "session_id": _SESSION_ID,
        "kind": "interaction",
        "name": name,
        "data_json": '{"tab":"today"}',
        "workout_id": None,
        "set_log_id": None,
    }


def test_push_events_happy_path(client, test_engine, test_user_id) -> None:
    response = client.post(
        "/api/telemetry/events",
        json={"events": [_event(_EVENT_A), _event(_EVENT_B, name="execution.log_set")]},
    )
    assert response.status_code == 200
    assert response.json() == {"events_received": 2}

    with Session(test_engine) as session:
        rows = session.query(EventLog).order_by(EventLog.id).all()
        assert len(rows) == 2
        by_id = {row.id: row for row in rows}
        assert by_id[_EVENT_A].user_id == test_user_id
        assert by_id[_EVENT_A].kind == "interaction"
        assert by_id[_EVENT_A].name == "today.start_tap"
        assert by_id[_EVENT_A].session_id == _SESSION_ID
        assert by_id[_EVENT_A].received_at is not None
        assert by_id[_EVENT_B].name == "execution.log_set"


def test_push_events_idempotent_by_id(client, test_engine) -> None:
    """Re-pushing the same event id updates in place, no duplicates.

    The app retries on transient failures; the server must trust the UUID.
    """
    payload = {"events": [_event(_EVENT_A, name="first")]}
    assert client.post("/api/telemetry/events", json=payload).status_code == 200

    # Same id, different name — must update, not insert.
    payload["events"][0]["name"] = "second"
    assert client.post("/api/telemetry/events", json=payload).status_code == 200

    with Session(test_engine) as session:
        rows = session.query(EventLog).filter_by(id=_EVENT_A).all()
        assert len(rows) == 1
        assert rows[0].name == "second"


def test_push_events_requires_auth(client) -> None:
    """No bearer token → 401/403.

    We take the `client` fixture (which overrides `verify_bearer` for
    ergonomic testing) and temporarily clear that override, so the real
    auth dependency runs with no Authorization header.
    """
    from workoutdb_server.api.deps import verify_bearer
    from workoutdb_server.main import app

    override = app.dependency_overrides.pop(verify_bearer, None)
    try:
        response = client.post(
            "/api/telemetry/events",
            json={"events": [_event(_EVENT_A)]},
        )
        assert response.status_code in (401, 403), response.text
    finally:
        if override is not None:
            app.dependency_overrides[verify_bearer] = override


def test_push_events_empty_batch_ok(client) -> None:
    response = client.post("/api/telemetry/events", json={"events": []})
    assert response.status_code == 200
    assert response.json() == {"events_received": 0}


def test_push_events_cross_tenant_upsert_ignored(client, test_engine, test_user_id) -> None:
    """A row owned by another user must not be overwritten by the auth'd user.

    We simulate an existing telemetry row belonging to a different user, then
    have the auth'd client push the *same event id* with different content.
    The server must silently refuse the overwrite — the other user's row
    stays intact.
    """
    # Seed: another user's event with the same id.
    with Session(test_engine) as session:
        session.add(AppUser(id=_OTHER_USER, name="Other"))
        session.add(
            EventLog(
                id=_EVENT_A,
                user_id=_OTHER_USER,
                ts=datetime(2026, 4, 1),
                session_id=_SESSION_ID,
                kind="interaction",
                name="other.event",
                data_json=None,
                workout_id=None,
                set_log_id=None,
                received_at=datetime(2026, 4, 1),
            )
        )
        session.commit()

    # Auth'd user tries to overwrite with a conflicting payload.
    response = client.post(
        "/api/telemetry/events",
        json={"events": [_event(_EVENT_A, name="attempted.overwrite")]},
    )
    assert response.status_code == 200

    # Other user's row must be untouched, and no new row created under the
    # auth'd user (since the id already exists).
    with Session(test_engine) as session:
        rows = session.query(EventLog).filter_by(id=_EVENT_A).all()
        assert len(rows) == 1
        assert rows[0].user_id == _OTHER_USER
        assert rows[0].name == "other.event"
        # Auth'd user shouldn't have a row at all yet.
        auth_rows = session.query(EventLog).filter_by(user_id=test_user_id).all()
        assert auth_rows == []


def test_push_events_malformed_422(client) -> None:
    response = client.post(
        "/api/telemetry/events",
        json={"events": [{"id": "x", "kind": "interaction"}]},  # missing required fields
    )
    assert response.status_code == 422


def test_telemetry_rejects_oversized_batch(client, test_engine) -> None:
    """Bug-033 regression: server caps events per POST at 500.

    Prior to the fix, `POST /api/telemetry/events` accepted arbitrary-size
    batches (1000+ events went through in ad-hoc testing). A misbehaving
    client could fan an entire 10k local ring buffer into one payload and
    blow up the server's event_log table. The client's push queue sends
    one event per `PushItem`, so 500-per-request is generous and never
    breached in the normal flow.
    """
    oversized = [
        {
            "id": f"aaaaaaaa-aaaa-4aaa-8aaa-{i:012x}",
            "timestamp": "2026-04-18T14:32:15Z",
            "session_id": _SESSION_ID,
            "kind": "interaction",
            "name": "today.start_tap",
            "data_json": None,
            "workout_id": None,
            "set_log_id": None,
        }
        for i in range(501)
    ]
    response = client.post("/api/telemetry/events", json={"events": oversized})
    assert response.status_code == 422, response.text
    # Nothing landed in the DB — the validator rejects before the handler
    # runs, so there's no partial write to clean up.
    with Session(test_engine) as session:
        rows = session.query(EventLog).count()
        assert rows == 0


def test_telemetry_rejects_non_Z_timestamp(client) -> None:
    """Session invariant: every datetime on the wire ends in literal `Z`.

    Prior to the `UtcDatetimeIn` validator, Pydantic's default datetime parser
    silently accepted `+00:00` / `+0000` / naive strings and coerced them to
    UTC, so a client that drifted from the `Z`-suffix contract would persist
    an off-spec row without the server noticing. This guard fails ingest at
    422 so the wire format stays one-way.
    """
    payload = {
        "events": [
            {
                "id": _EVENT_A,
                "timestamp": "2026-04-18T14:32:15+00:00",
                "session_id": _SESSION_ID,
                "kind": "interaction",
                "name": "today.start_tap",
                "data_json": None,
                "workout_id": None,
                "set_log_id": None,
            }
        ]
    }
    response = client.post("/api/telemetry/events", json=payload)
    assert response.status_code == 422, response.text
    # The error message must name the offending field so a client-side
    # fix is obvious — we don't want a future regression to widen the
    # validator into "accept anything" silently.
    body = response.json()
    assert any("timestamp" in str(err).lower() for err in body["detail"])


def test_telemetry_accepts_batch_at_cap(client) -> None:
    """Regression: exactly 500 events still goes through (off-by-one watch)."""
    batch = [
        {
            "id": f"bbbbbbbb-bbbb-4bbb-8bbb-{i:012x}",
            "timestamp": "2026-04-18T14:32:15Z",
            "session_id": _SESSION_ID,
            "kind": "interaction",
            "name": "today.start_tap",
            "data_json": None,
            "workout_id": None,
            "set_log_id": None,
        }
        for i in range(500)
    ]
    response = client.post("/api/telemetry/events", json={"events": batch})
    assert response.status_code == 200, response.text
    assert response.json() == {"events_received": 500}
