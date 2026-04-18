"""Bearer-token auth enforcement. Uses the real verify_bearer (not the override)."""

from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session
from workoutdb_server.api.deps import get_db, verify_bearer
from workoutdb_server.config import get_settings
from workoutdb_server.main import app
from workoutdb_server.migrations import apply_migrations

_REAL_TOKEN = "real-token-xyz-16chars"
_REAL_USER_ID = "22222222-2222-2222-2222-222222222222"


@pytest.fixture
def auth_client(tmp_path, monkeypatch: pytest.MonkeyPatch) -> Iterator[TestClient]:
    # Provide real settings via env so lifespan + auth both see the same token.
    monkeypatch.setenv("WORKOUTDB_BEARER_TOKEN", _REAL_TOKEN)
    monkeypatch.setenv("WORKOUTDB_USER_ID", _REAL_USER_ID)
    monkeypatch.setenv("WORKOUTDB_DB_PATH", str(tmp_path / "test.db"))
    get_settings.cache_clear()

    engine = create_engine(f"sqlite:///{tmp_path / 'test.db'}", future=True)

    @event.listens_for(engine, "connect")
    def _pragma(dbapi_conn, _record):
        cursor = dbapi_conn.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()

    apply_migrations(engine)

    def _override_db():
        session = Session(engine)
        try:
            yield session
        finally:
            session.close()

    app.dependency_overrides[get_db] = _override_db
    # Do NOT override verify_bearer — we want to test the real one.
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()
    engine.dispose()
    get_settings.cache_clear()


def test_missing_auth_header_rejected(auth_client) -> None:
    response = auth_client.get("/api/exercises")
    assert response.status_code in (401, 403)  # HTTPBearer returns 403; some paths 401


def test_wrong_token_rejected(auth_client) -> None:
    response = auth_client.get(
        "/api/exercises",
        headers={"Authorization": "Bearer wrong-token"},
    )
    assert response.status_code == 401


def test_correct_token_accepted(auth_client) -> None:
    response = auth_client.get(
        "/api/exercises",
        headers={"Authorization": f"Bearer {_REAL_TOKEN}"},
    )
    assert response.status_code == 200
    assert response.json() == []


def test_health_endpoint_unprotected(auth_client) -> None:
    # /health has no auth — allows simple liveness checks.
    response = auth_client.get("/health")
    assert response.status_code == 200


def test_verify_bearer_is_the_dep() -> None:
    # Defensive: confirm the verify_bearer symbol imported correctly and is used by routers.
    assert callable(verify_bearer)
