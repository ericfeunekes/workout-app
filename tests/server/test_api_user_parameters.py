"""/api/user-parameters — append-only log, latest-per-key, history queries.

The authenticated user_id comes from the bearer token (conftest seeds it as test_user_id).
"""


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

    The app posts a single-element array with `source: "app_log"` and an
    `updated_at` stamped at completion time. `user_id` + row id are both
    server-derived and MUST NOT be present in the payload.
    """
    response = client.post(
        "/api/user-parameters",
        json=[
            {
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
    assert row["key"] == "bodyweight_kg"
    assert row["value"] == "82.5"
    assert row["source"] == "app_log"
    assert row["user_id"] == test_user_id
    # Server-generated id is a lowercase UUID string.
    assert len(row["id"]) == 36
