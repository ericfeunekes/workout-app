"""/api/user-parameters — append-only log, latest-per-key, history queries.

The authenticated user_id comes from the bearer token (conftest seeds it as test_user_id).
"""

from datetime import datetime

from sqlalchemy.orm import Session
from workoutdb_server.models import AppUser, UserParameter

_OTHER_USER = "e0000009-0000-4000-8000-000000000009"


def test_append_inserts_every_time(client) -> None:
    # Push bodyweight twice for the same key
    client.post(
        "/api/user-parameters",
        json=[
            {"key": "bodyweight_kg", "value": "82.0"},
            {"key": "bodyweight_kg", "value": "81.5"},
        ],
    )

    # Full history for that key
    response = client.get("/api/user-parameters?key=bodyweight_kg")
    assert response.status_code == 200
    rows = response.json()
    assert len(rows) == 2
    assert {r["value"] for r in rows} == {"82.0", "81.5"}


def test_latest_per_key(client, test_user_id) -> None:
    client.post(
        "/api/user-parameters",
        json=[
            {
                "key": "bodyweight_kg",
                "value": "82.0",
                "updated_at": "2026-04-10T00:00:00Z",
            },
            {
                "key": "bodyweight_kg",
                "value": "81.5",
                "updated_at": "2026-04-17T00:00:00Z",
            },
            {
                "key": "1rm_back_squat_kg",
                "value": "150",
                "updated_at": "2026-04-01T00:00:00Z",
            },
        ],
    )

    response = client.get("/api/user-parameters?latest=true")
    assert response.status_code == 200
    rows = response.json()

    latest_by_key = {r["key"]: r["value"] for r in rows}
    assert latest_by_key == {"bodyweight_kg": "81.5", "1rm_back_squat_kg": "150"}
    assert all(r["user_id"] == test_user_id for r in rows)


def test_append_accepts_app_shaped_bodyweight_payload(client, test_user_id) -> None:
    """Pin the shape the iOS `CompleteView` sends on save & done (bug-011).

    The app posts a single-element array with `source: "app_log"`, an
    `updated_at` stamped at completion time, AND a client-owned `id`
    derived deterministically from `(userID, key, updated_at)`. The id
    keeps a retried push idempotent (see `test_post_user_parameters_
    upserts_on_duplicate_id`). `user_id` stays server-derived from the
    bearer token.
    """
    client_id = "11111111-1111-1111-1111-aaaaaaaaaaaa"
    response = client.post(
        "/api/user-parameters",
        json=[
            {
                "id": client_id,
                "key": "bodyweight_kg",
                "value": "82.5",
                "source": "app_log",
                "updated_at": "2026-04-18T12:34:56Z",
            }
        ],
    )
    assert response.status_code == 200
    rows = response.json()
    assert len(rows) == 1
    row = rows[0]
    assert row["id"] == client_id
    assert row["key"] == "bodyweight_kg"
    assert row["value"] == "82.5"
    assert row["source"] == "app_log"
    assert row["user_id"] == test_user_id


def test_post_user_parameters_upserts_on_duplicate_id(client) -> None:
    """Replaying the same push (app crash between commit and queue-remove)
    must not create a second `user_parameters` row.

    Without the id-keyed upsert, the second call would insert a duplicate
    — and since the read path is append-only (`user_parameters` is history-
    preserving by design), that duplicate would live forever and show up
    in every `latest=true` resolution tie-break window.
    """
    client_id = "22222222-2222-2222-2222-bbbbbbbbbbbb"
    payload = [
        {
            "id": client_id,
            "key": "bodyweight_kg",
            "value": "82.5",
            "source": "app_log",
            "updated_at": "2026-04-18T12:34:56Z",
        }
    ]

    first = client.post("/api/user-parameters", json=payload)
    assert first.status_code == 200
    second = client.post("/api/user-parameters", json=payload)
    assert second.status_code == 200

    history = client.get("/api/user-parameters?key=bodyweight_kg")
    assert history.status_code == 200
    rows = history.json()
    assert len(rows) == 1, "replay must upsert on id, not insert a second row"
    assert rows[0]["id"] == client_id
    assert rows[0]["value"] == "82.5"


def test_user_parameters_duplicate_id_other_user_returns_403(
    client, test_engine
) -> None:
    """Tenant guard on the upsert-by-id branch.

    The client derives deterministic ids from `(userID, key, timestamp)`,
    so same-id-different-user in practice requires either a collision or
    an attacker replaying another user's UUID. Before the guard the
    duplicate-id branch returned the existing row unconditionally, which
    would leak (or silently "claim") another tenant's row. Now the guard
    raises 403 so the sibling tenant's data stays isolated.
    """
    foreign_id = "33333333-3333-3333-3333-cccccccccccc"
    with Session(test_engine) as session:
        session.add(AppUser(id=_OTHER_USER, name="Other"))
        session.flush()
        session.add(
            UserParameter(
                id=foreign_id,
                user_id=_OTHER_USER,
                key="bodyweight_kg",
                value="999.0",
                updated_at=datetime(2026, 4, 10),
                source="app_log",
            )
        )
        session.commit()

    # The auth'd user (test_user_id) tries to replay the foreign id.
    response = client.post(
        "/api/user-parameters",
        json=[
            {
                "id": foreign_id,
                "key": "bodyweight_kg",
                "value": "82.5",
                "source": "app_log",
                "updated_at": "2026-04-18T12:34:56Z",
            }
        ],
    )
    assert response.status_code == 403, response.text
    assert "another user" in response.json()["detail"].lower()

    # The foreign row is untouched — no value leak, no value overwrite.
    with Session(test_engine) as session:
        row = session.get(UserParameter, foreign_id)
        assert row is not None
        assert row.user_id == _OTHER_USER
        assert row.value == "999.0"


def test_post_user_parameters_omitted_id_still_inserts(client) -> None:
    """Claude's bulk imports don't retry client-side and may omit `id`;
    the server must fall back to generating a fresh UUID per row."""
    response = client.post(
        "/api/user-parameters",
        json=[
            {
                "key": "1rm_back_squat_kg",
                "value": "150",
                "source": "claude",
            }
        ],
    )
    assert response.status_code == 200
    rows = response.json()
    assert len(rows) == 1
    # Server-generated id is a 36-char lowercase UUID.
    assert len(rows[0]["id"]) == 36
    assert rows[0]["id"] == rows[0]["id"].lower()
