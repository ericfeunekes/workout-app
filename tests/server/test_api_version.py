"""/api/version — schema handshake."""


def test_version_returns_applied_migrations(client) -> None:
    response = client.get("/api/version")
    assert response.status_code == 200

    body = response.json()
    assert body["applied_migrations"]
    # Schema version is the last applied migration (head).
    assert body["schema_version"] == body["applied_migrations"][-1]
    assert "001_initial.sql" in body["applied_migrations"]
    assert body["server_version"]
