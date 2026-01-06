from __future__ import annotations

from datetime import date, time, timezone, datetime
from pathlib import Path
from typing import Any
from unittest.mock import Mock

from googleapiclient.errors import HttpError

from workoutdb.calendar_api import build_event_payload, list_calendars, upsert_events
from workoutdb.config import AppConfig, CalendarConfig, GoogleConfig, PathsConfig


def test_build_event_payload_duration() -> None:
    payload = build_event_payload(
        summary="Workout",
        workout_date=date(2026, 1, 6),
        start_time=time(7, 30),
        duration_min=60,
        description=None,
        tzinfo=timezone.utc,
    )
    start = datetime.fromisoformat(payload["start"]["dateTime"])
    end = datetime.fromisoformat(payload["end"]["dateTime"])
    assert (end - start).total_seconds() == 3600


def test_upsert_events_retries_on_missing_event(monkeypatch) -> None:
    class FakeResp:
        status = 404

    class FakeRequest:
        def __init__(self, payload: dict):
            self.payload = payload

        def execute(self) -> dict:
            return {"id": "evt-1", "htmlLink": "https://example.com"}

    class FakeEvents:
        def update(self, **_: Any) -> FakeRequest:
            raise HttpError(FakeResp(), b"not found")

        def insert(self, **_: Any) -> FakeRequest:
            return FakeRequest({})

    class FakeService:
        def events(self) -> FakeEvents:
            return FakeEvents()

    monkeypatch.setattr("workoutdb.calendar_api.get_credentials", Mock())
    monkeypatch.setattr("workoutdb.calendar_api.calendar_service", lambda _: FakeService())

    cfg = AppConfig(
        paths=PathsConfig(app_home=Path("/tmp")),
        google=GoogleConfig(
            client_secret_path=Path("/tmp/client.json"),
            token_path=Path("/tmp/token.json"),
        ),
        calendar=CalendarConfig(default_id="primary"),
    )

    results = upsert_events(
        cfg,
        calendar_id="primary",
        events=[
            {
                "planned_id": "planned-1",
                "event_id": "missing",
                "payload": {"summary": "Workout"},
            }
        ],
    )
    assert results[0]["status"] == "created"


def test_upsert_events_retries_on_gone_event(monkeypatch) -> None:
    class FakeResp:
        status = 410

    class FakeRequest:
        def execute(self) -> dict:
            return {"id": "evt-410", "htmlLink": "https://example.com"}

    class FakeEvents:
        def update(self, **_: Any) -> FakeRequest:
            raise HttpError(FakeResp(), b"gone")

        def insert(self, **_: Any) -> FakeRequest:
            return FakeRequest()

    class FakeService:
        def events(self) -> FakeEvents:
            return FakeEvents()

    monkeypatch.setattr("workoutdb.calendar_api.get_credentials", Mock())
    monkeypatch.setattr("workoutdb.calendar_api.calendar_service", lambda _: FakeService())

    cfg = AppConfig(
        paths=PathsConfig(app_home=Path("/tmp")),
        google=GoogleConfig(
            client_secret_path=Path("/tmp/client.json"),
            token_path=Path("/tmp/token.json"),
        ),
        calendar=CalendarConfig(default_id="primary"),
    )

    results = upsert_events(
        cfg,
        calendar_id="primary",
        events=[
            {
                "planned_id": "planned-1",
                "event_id": "gone",
                "payload": {"summary": "Workout"},
            }
        ],
    )
    assert results[0]["status"] == "created"


def test_upsert_events_failure_result(monkeypatch) -> None:
    class FakeEvents:
        def update(self, **_: Any) -> None:
            raise RuntimeError("boom")

    class FakeService:
        def events(self) -> FakeEvents:
            return FakeEvents()

    monkeypatch.setattr("workoutdb.calendar_api.get_credentials", Mock())
    monkeypatch.setattr("workoutdb.calendar_api.calendar_service", lambda _: FakeService())

    cfg = AppConfig(
        paths=PathsConfig(app_home=Path("/tmp")),
        google=GoogleConfig(
            client_secret_path=Path("/tmp/client.json"),
            token_path=Path("/tmp/token.json"),
        ),
        calendar=CalendarConfig(default_id="primary"),
    )

    results = upsert_events(
        cfg,
        calendar_id="primary",
        events=[
            {
                "planned_id": "planned-1",
                "event_id": "evt-1",
                "payload": {"summary": "Workout"},
            }
        ],
    )
    assert results[0]["status"] == "failed"
    assert "boom" in (results[0]["error"] or "")


def test_upsert_events_batch_partial(monkeypatch) -> None:
    class FakeResp:
        status = 404

    class FakeRequest:
        def __init__(self, event_id: str):
            self._event_id = event_id

        def execute(self) -> dict:
            return {"id": self._event_id, "htmlLink": "https://example.com"}

    class FakeEvents:
        def update(self, **kwargs: Any) -> FakeRequest:
            event_id = kwargs.get("eventId")
            if event_id == "missing":
                raise HttpError(FakeResp(), b"not found")
            return FakeRequest(event_id)

        def insert(self, **_: Any) -> FakeRequest:
            return FakeRequest("inserted")

    class FakeService:
        def events(self) -> FakeEvents:
            return FakeEvents()

    monkeypatch.setattr("workoutdb.calendar_api.get_credentials", Mock())
    monkeypatch.setattr("workoutdb.calendar_api.calendar_service", lambda _: FakeService())

    cfg = AppConfig(
        paths=PathsConfig(app_home=Path("/tmp")),
        google=GoogleConfig(
            client_secret_path=Path("/tmp/client.json"),
            token_path=Path("/tmp/token.json"),
        ),
        calendar=CalendarConfig(default_id="primary"),
    )

    results = upsert_events(
        cfg,
        calendar_id="primary",
        events=[
            {"planned_id": "planned-1", "event_id": "evt-1", "payload": {"summary": "A"}},
            {"planned_id": "planned-2", "event_id": "missing", "payload": {"summary": "B"}},
        ],
    )
    assert [r["status"] for r in results] == ["updated", "created"]


def test_list_calendars_pagination(monkeypatch) -> None:
    class FakeCalendarList:
        def __init__(self) -> None:
            self.calls = 0

        def list(self, pageToken=None):  # noqa: N802
            def execute():
                self.calls += 1
                if self.calls == 1:
                    return {"items": [{"id": "cal-1"}], "nextPageToken": "next"}
                return {"items": [{"id": "cal-2"}]}

            return Mock(execute=execute)

    class FakeService:
        def calendarList(self):  # noqa: N802
            return FakeCalendarList()

    monkeypatch.setattr("workoutdb.calendar_api.get_credentials", Mock())
    monkeypatch.setattr("workoutdb.calendar_api.calendar_service", lambda _: FakeService())

    cfg = AppConfig(
        paths=PathsConfig(app_home=Path("/tmp")),
        google=GoogleConfig(
            client_secret_path=Path("/tmp/client.json"),
            token_path=Path("/tmp/token.json"),
        ),
        calendar=CalendarConfig(default_id="primary"),
    )

    items = list_calendars(cfg)
    assert [item["id"] for item in items] == ["cal-1", "cal-2"]
