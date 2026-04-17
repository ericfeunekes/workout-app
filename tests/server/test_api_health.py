"""/health and /health/ready — liveness + readiness probes."""


def test_health_liveness(client) -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_health_ready_reports_schema_version(client) -> None:
    response = client.get("/health/ready")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["applied_migrations"]
    assert body["schema_version"] == body["applied_migrations"][-1]
    assert "001_initial.sql" in body["applied_migrations"]


def test_request_id_header_present(client) -> None:
    response = client.get("/health")
    assert "x-request-id" in {k.lower() for k in response.headers.keys()}


def test_respects_provided_request_id(client) -> None:
    response = client.get("/health", headers={"X-Request-ID": "my-correlation-id"})
    assert response.headers["X-Request-ID"] == "my-correlation-id"
