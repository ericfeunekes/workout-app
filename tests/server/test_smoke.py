"""Smoke tests: prove the package installs and the FastAPI app boots."""

from fastapi.testclient import TestClient

import workoutdb_server
from workoutdb_server.main import app


def test_package_version() -> None:
    assert workoutdb_server.__version__


def test_health_endpoint() -> None:
    client = TestClient(app)
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
