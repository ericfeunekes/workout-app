"""Retention sweep for `event_log` — prunes rows older than N days.

See `workoutdb_server.sync.event_log_retention`. The sweep runs at startup
and then on a daily timer; these tests exercise the underlying
`prune_event_log` function directly plus the lifespan hooks that wire it
into the FastAPI app.
"""

import asyncio
import logging
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
from workoutdb_server import main as server_main
from workoutdb_server.config import get_settings
from workoutdb_server.main import app
from workoutdb_server.models import EventLog
from workoutdb_server.sync.event_log_retention import prune_event_log

_SESSION_ID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"


def _seed_event(
    session: Session,
    *,
    event_id: str,
    user_id: str,
    age_days: float,
    now: datetime | None = None,
) -> None:
    """Insert one event whose `ts` is `age_days` behind `now`.

    We store naive datetimes (stripped tzinfo) because SQLite's DateTime
    column holds naive values — mirrors production inserts in `telemetry.py`.
    """
    base = now or datetime.now(UTC)
    ts = (base - timedelta(days=age_days)).replace(tzinfo=None)
    session.add(
        EventLog(
            id=event_id,
            user_id=user_id,
            ts=ts,
            session_id=_SESSION_ID,
            kind="interaction",
            name="today.start_tap",
            data_json=None,
            workout_id=None,
            set_log_id=None,
            received_at=ts,
        )
    )


@pytest.fixture
def seeded_db(test_engine, test_user_id) -> Session:
    """Three events at T-10d, T-80d, T-95d under the auth'd user."""
    session = Session(test_engine)
    _seed_event(
        session, event_id="11111111-1111-4111-8111-111111111111", user_id=test_user_id, age_days=10
    )
    _seed_event(
        session, event_id="22222222-2222-4222-8222-222222222222", user_id=test_user_id, age_days=80
    )
    _seed_event(
        session, event_id="33333333-3333-4333-8333-333333333333", user_id=test_user_id, age_days=95
    )
    session.commit()
    try:
        yield session
    finally:
        session.close()


def test_prune_event_log_deletes_rows_older_than_threshold(seeded_db: Session) -> None:
    """90-day threshold keeps T-10d + T-80d, drops T-95d."""
    deleted = prune_event_log(seeded_db, older_than_days=90)
    assert deleted == 1

    ids = {row.id for row in seeded_db.query(EventLog).all()}
    assert ids == {
        "11111111-1111-4111-8111-111111111111",
        "22222222-2222-4222-8222-222222222222",
    }


def test_prune_event_log_returns_correct_count(seeded_db: Session) -> None:
    """Return value equals the number of rows actually removed."""
    # Tighter threshold → two rows deleted (T-80d and T-95d).
    deleted = prune_event_log(seeded_db, older_than_days=30)
    assert deleted == 2
    assert seeded_db.query(EventLog).count() == 1


def test_prune_event_log_threshold_zero_deletes_all(seeded_db: Session) -> None:
    """Threshold 0 collapses cutoff to "now" — every row is older, so all go."""
    deleted = prune_event_log(seeded_db, older_than_days=0)
    assert deleted == 3
    assert seeded_db.query(EventLog).count() == 0


def test_prune_event_log_no_rows_is_noop(test_engine) -> None:
    """Empty table returns 0 without raising."""
    with Session(test_engine) as session:
        deleted = prune_event_log(session, older_than_days=90)
        assert deleted == 0


def test_prune_event_log_keeps_recent_rows_on_large_threshold(seeded_db: Session) -> None:
    """A threshold larger than any row's age leaves the table untouched."""
    deleted = prune_event_log(seeded_db, older_than_days=365)
    assert deleted == 0
    assert seeded_db.query(EventLog).count() == 3


def test_prune_event_log_negative_days_treated_as_zero(seeded_db: Session) -> None:
    """Defensive: negative retention is clamped to 0 (delete everything)."""
    deleted = prune_event_log(seeded_db, older_than_days=-5)
    assert deleted == 3
    assert seeded_db.query(EventLog).count() == 0


def test_prune_event_log_commits_so_changes_are_visible_in_new_session(
    test_engine,
    test_user_id,
) -> None:
    """Integration: prune commits; a fresh session sees the deletion."""
    with Session(test_engine) as session:
        _seed_event(
            session,
            event_id="44444444-4444-4444-8444-444444444444",
            user_id=test_user_id,
            age_days=200,
        )
        session.commit()

    with Session(test_engine) as session:
        deleted = prune_event_log(session, older_than_days=90)
        assert deleted == 1

    # A separate session sees an empty table — the first session committed.
    with Session(test_engine) as session:
        assert session.query(EventLog).count() == 0


# ---------------------------------------------------------------------------
# Lifespan integration: sweep failures must not abort startup, and the
# periodic sweep task must actually run on its interval.
# ---------------------------------------------------------------------------

_TEST_TOKEN = "test-token-1234567890"
_TEST_USER_ID = "11111111-1111-1111-1111-111111111111"


@pytest.fixture
def lifespan_env(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """Wire env vars so `main.app`'s lifespan sees an isolated SQLite DB."""
    db_path = tmp_path / "lifespan.db"
    monkeypatch.setenv("WORKOUTDB_BEARER_TOKEN", _TEST_TOKEN)
    monkeypatch.setenv("WORKOUTDB_USER_ID", _TEST_USER_ID)
    monkeypatch.setenv("WORKOUTDB_DB_PATH", str(db_path))
    get_settings.cache_clear()
    yield db_path
    get_settings.cache_clear()


def test_sweep_failure_does_not_abort_startup(
    lifespan_env: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Regression: a raising prune must NOT crash the FastAPI lifespan.

    Retention is maintenance, not a prerequisite — the server has to come
    up and serve /api/version even when the sweep blows up.
    """

    def _boom(*_args, **_kwargs) -> int:
        raise RuntimeError("simulated sqlite failure during prune")

    # Patch both import sites: main imports the symbol by name at module load.
    monkeypatch.setattr("workoutdb_server.main.prune_event_log", _boom)
    monkeypatch.setattr("workoutdb_server.sync.event_log_retention.prune_event_log", _boom)

    # Attach a capture handler directly to the main logger — the app's
    # `configure_logging` strips caplog's handlers off the root during
    # startup, so we can't rely on the standard caplog fixture.
    records: list[logging.LogRecord] = []

    class _Capture(logging.Handler):
        def emit(self, record: logging.LogRecord) -> None:
            records.append(record)

    handler = _Capture(level=logging.WARNING)
    main_logger = logging.getLogger("workoutdb_server.main")
    main_logger.addHandler(handler)
    try:
        # TestClient as a context manager drives the lifespan start/stop.
        with TestClient(app) as client:
            # /health doesn't require auth and proves the app booted.
            health = client.get("/health")
            assert health.status_code == 200
            # /api/version confirms routers + DB session deps are wired too.
            response = client.get(
                "/api/version",
                headers={"Authorization": f"Bearer {_TEST_TOKEN}"},
            )
            assert response.status_code == 200
            body = response.json()
            assert body["applied_migrations"], "server should be fully up"
    finally:
        main_logger.removeHandler(handler)

    assert any("startup event_log sweep failed" in record.getMessage() for record in records), (
        "the swallowed exception must be logged at WARNING"
    )


def test_periodic_sweep_runs_at_interval(
    lifespan_env: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The daily sweep task actually invokes prune on each tick.

    We stub the `asyncio` module that `main` imported so the loop advances
    immediately, count how many times `_sweep_event_log` is called across a
    few ticks, and cancel by raising `CancelledError` from the stub once the
    target tick count is reached.
    """
    calls: list[int] = []

    def _fake_sweep(_engine, _settings) -> None:
        calls.append(1)

    sleep_count = 0
    target_ticks = 3

    async def _fake_sleep(interval: float) -> None:
        nonlocal sleep_count
        # The periodic task's first action is `await asyncio.sleep(INTERVAL)`.
        # Validate the interval, then raise Cancelled after `target_ticks`
        # iterations so the `while True` unwinds cleanly.
        assert interval == server_main._PERIODIC_SWEEP_INTERVAL_SEC
        sleep_count += 1
        if sleep_count > target_ticks:
            raise asyncio.CancelledError

    # Replace ONLY the `asyncio` that main.py sees — not the real module, so
    # the test harness still has a working `asyncio.sleep(0)` to yield with.
    class _FakeAsyncio:
        sleep = staticmethod(_fake_sleep)
        CancelledError = asyncio.CancelledError
        create_task = staticmethod(asyncio.create_task)

    monkeypatch.setattr(server_main, "_sweep_event_log", _fake_sweep)
    monkeypatch.setattr(server_main, "asyncio", _FakeAsyncio)

    async def _drive() -> None:
        # engine/settings aren't touched by the fakes, so passing None is safe.
        task = asyncio.create_task(server_main._periodic_sweep(None, None))
        # Wait for cancellation to propagate.
        with pytest.raises(asyncio.CancelledError):
            await task

    asyncio.run(_drive())

    # Exactly `target_ticks` sweeps should have fired — sleep runs first,
    # then sweep, and the (target_ticks+1)-th sleep raises before sweep.
    assert len(calls) == target_ticks, f"expected {target_ticks} sweeps, got {len(calls)}"
