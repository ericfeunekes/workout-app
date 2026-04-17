"""/api/user-parameters — append-only log, latest-per-key, history queries."""

from workoutdb_server.models import AppUser


def _seed_user(engine) -> str:
    from sqlalchemy.orm import Session

    with Session(engine) as session:
        user = AppUser(name="Eric")
        session.add(user)
        session.commit()
        return user.id


def test_append_inserts_every_time(client, test_engine) -> None:
    user_id = _seed_user(test_engine)

    # Push bodyweight twice for the same key
    client.post(
        "/api/user-parameters",
        json=[
            {"user_id": user_id, "key": "bodyweight_kg", "value": "82.0"},
            {"user_id": user_id, "key": "bodyweight_kg", "value": "81.5"},
        ],
    )

    # Full history for that key
    response = client.get(f"/api/user-parameters?user_id={user_id}&key=bodyweight_kg")
    assert response.status_code == 200
    rows = response.json()
    assert len(rows) == 2
    assert {r["value"] for r in rows} == {"82.0", "81.5"}


def test_latest_per_key(client, test_engine) -> None:
    user_id = _seed_user(test_engine)

    client.post(
        "/api/user-parameters",
        json=[
            {
                "user_id": user_id,
                "key": "bodyweight_kg",
                "value": "82.0",
                "updated_at": "2026-04-10T00:00:00Z",
            },
            {
                "user_id": user_id,
                "key": "bodyweight_kg",
                "value": "81.5",
                "updated_at": "2026-04-17T00:00:00Z",
            },
            {
                "user_id": user_id,
                "key": "1rm_back_squat_kg",
                "value": "150",
                "updated_at": "2026-04-01T00:00:00Z",
            },
        ],
    )

    response = client.get(f"/api/user-parameters?user_id={user_id}&latest=true")
    assert response.status_code == 200
    rows = response.json()

    latest_by_key = {r["key"]: r["value"] for r in rows}
    assert latest_by_key == {"bodyweight_kg": "81.5", "1rm_back_squat_kg": "150"}


def test_post_rejects_unknown_user(client, test_engine) -> None:
    _seed_user(test_engine)  # a valid one, but we'll push with a different id
    response = client.post(
        "/api/user-parameters",
        json=[{"user_id": "unknown-user", "key": "bodyweight_kg", "value": "82"}],
    )
    assert response.status_code == 400
    assert "Unknown user_id" in response.json()["detail"]
