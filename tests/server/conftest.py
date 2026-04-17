"""Test fixtures for API tests: per-test SQLite DB, env-provided settings, TestClient."""

from collections.abc import Iterator
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import Engine, create_engine, event
from sqlalchemy.orm import Session

from workoutdb_server.api.deps import get_db, verify_bearer
from workoutdb_server.config import get_settings
from workoutdb_server.main import app
from workoutdb_server.migrations import apply_migrations

_TEST_TOKEN = "test-token-1234567890"


@pytest.fixture
def tmp_db_path(tmp_path: Path) -> Path:
    return tmp_path / "test.db"


@pytest.fixture
def test_engine(tmp_db_path: Path) -> Iterator[Engine]:
    engine = create_engine(f"sqlite:///{tmp_db_path}", future=True)

    @event.listens_for(engine, "connect")
    def _pragma(dbapi_conn, _record):
        cursor = dbapi_conn.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()

    apply_migrations(engine)
    yield engine
    engine.dispose()


@pytest.fixture
def client(
    test_engine: Engine,
    tmp_db_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> Iterator[TestClient]:
    """Settings-authed client with auth + db overrides for ergonomic testing."""
    monkeypatch.setenv("WORKOUTDB_BEARER_TOKEN", _TEST_TOKEN)
    monkeypatch.setenv("WORKOUTDB_DB_PATH", str(tmp_db_path))
    get_settings.cache_clear()

    def _override_db() -> Iterator[Session]:
        session = Session(test_engine)
        try:
            yield session
        finally:
            session.close()

    def _override_auth() -> None:
        return None

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[verify_bearer] = _override_auth
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()
    get_settings.cache_clear()
