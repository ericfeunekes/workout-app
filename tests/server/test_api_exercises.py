"""/api/exercises — Claude-owned IDs, upsert by id."""


def test_upsert_creates_and_updates(client) -> None:
    # Create
    response = client.post(
        "/api/exercises",
        json=[
            {"id": "back-squat", "name": "Back Squat"},
            {"id": "front-squat", "name": "Front Squat", "notes": "keep elbows high"},
        ],
    )
    assert response.status_code == 200
    body = response.json()
    assert {e["id"] for e in body} == {"back-squat", "front-squat"}

    # Update by same id
    response = client.post(
        "/api/exercises",
        json=[{"id": "back-squat", "name": "Low-Bar Back Squat"}],
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
