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
from workoutdb_server.models import AppUser

_TEST_TOKEN = "test-token-1234567890"
_TEST_USER_ID = "11111111-1111-1111-1111-111111111111"


@pytest.fixture
def tmp_db_path(tmp_path: Path) -> Path:
    return tmp_path / "test.db"


@pytest.fixture
def test_user_id() -> str:
    """The user_id the auth override resolves to. Matches the row test_engine seeds."""
    return _TEST_USER_ID


@pytest.fixture
def test_engine(tmp_db_path: Path) -> Iterator[Engine]:
    engine = create_engine(f"sqlite:///{tmp_db_path}", future=True)

    @event.listens_for(engine, "connect")
    def _pragma(dbapi_conn, _record):
        cursor = dbapi_conn.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()

    apply_migrations(engine)
    # Seed the auth'd user; production does this in main.py's lifespan.
    with Session(engine) as session:
        session.add(AppUser(id=_TEST_USER_ID, name="Eric"))
        session.commit()
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
    monkeypatch.setenv("WORKOUTDB_USER_ID", _TEST_USER_ID)
    monkeypatch.setenv("WORKOUTDB_DB_PATH", str(tmp_db_path))
    get_settings.cache_clear()

    def _override_db() -> Iterator[Session]:
        session = Session(test_engine)
        try:
            yield session
        finally:
            session.close()

    def _override_auth() -> str:
        return _TEST_USER_ID

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[verify_bearer] = _override_auth
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()
    get_settings.cache_clear()
