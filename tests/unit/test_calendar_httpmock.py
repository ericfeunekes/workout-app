from __future__ import annotations

import json
from pathlib import Path

import pytest
from googleapiclient.discovery import build_from_document
from googleapiclient.http import HttpMock

from workoutdb.calendar_api import upsert_events
from workoutdb.config import AppConfig, CalendarConfig, GoogleConfig, PathsConfig


def _calendar_discovery_doc() -> str:
    return json.dumps(
        {
            "kind": "discovery#restDescription",
            "name": "calendar",
            "version": "v3",
            "rootUrl": "https://www.googleapis.com/",
            "servicePath": "calendar/v3/",
            "baseUrl": "https://www.googleapis.com/calendar/v3/",
            "batchPath": "batch",
            "resources": {
                "events": {
                    "methods": {
                        "update": {
                            "id": "calendar.events.update",
                            "path": "calendars/{calendarId}/events/{eventId}",
                            "httpMethod": "PUT",
                            "parameters": {
                                "calendarId": {
                                    "type": "string",
                                    "location": "path",
                                    "required": True,
                                },
                                "eventId": {
                                    "type": "string",
                                    "location": "path",
                                    "required": True,
                                },
                            },
                            "request": {"$ref": "Event"},
                            "response": {"$ref": "Event"},
                        },
                        "insert": {
                            "id": "calendar.events.insert",
                            "path": "calendars/{calendarId}/events",
                            "httpMethod": "POST",
                            "parameters": {
                                "calendarId": {
                                    "type": "string",
                                    "location": "path",
                                    "required": True,
                                }
                            },
                            "request": {"$ref": "Event"},
                            "response": {"$ref": "Event"},
                        },
                    }
                }
            },
            "schemas": {
                "Event": {
                    "id": "Event",
                    "type": "object",
                }
            },
        }
    )


def _build_service(tmp_path: Path, response_payload: dict) -> object:
    response_path = tmp_path / "response.json"
    response_path.write_text(json.dumps(response_payload))
    http = HttpMock(response_path, {"status": "200"})
    return build_from_document(_calendar_discovery_doc(), http=http)


@pytest.fixture()
def cfg(tmp_path: Path) -> AppConfig:
    return AppConfig(
        paths=PathsConfig(app_home=tmp_path),
        google=GoogleConfig(
            client_secret_path=tmp_path / "client.json",
            token_path=tmp_path / "token.json",
        ),
        calendar=CalendarConfig(default_id="primary"),
    )


def test_upsert_events_update_with_httpmock(monkeypatch, tmp_path: Path, cfg: AppConfig) -> None:
    service = _build_service(
        tmp_path,
        {"kind": "calendar#event", "id": "evt-update", "htmlLink": "https://example.com"},
    )
    monkeypatch.setattr("workoutdb.calendar_api.get_credentials", lambda *_, **__: object())
    monkeypatch.setattr("workoutdb.calendar_api.calendar_service", lambda _: service)

    results = upsert_events(
        cfg,
        calendar_id="primary",
        events=[
            {
                "planned_id": "planned-1",
                "event_id": "evt-update",
                "payload": {"summary": "Workout"},
            }
        ],
    )
    assert results[0]["status"] == "updated"
    assert results[0]["event_id"] == "evt-update"


def test_upsert_events_insert_with_httpmock(monkeypatch, tmp_path: Path, cfg: AppConfig) -> None:
    service = _build_service(
        tmp_path,
        {"kind": "calendar#event", "id": "evt-insert", "htmlLink": "https://example.com"},
    )
    monkeypatch.setattr("workoutdb.calendar_api.get_credentials", lambda *_, **__: object())
    monkeypatch.setattr("workoutdb.calendar_api.calendar_service", lambda _: service)

    results = upsert_events(
        cfg,
        calendar_id="primary",
        events=[
            {
                "planned_id": "planned-1",
                "event_id": None,
                "payload": {"summary": "Workout"},
            }
        ],
    )
    assert results[0]["status"] == "created"
    assert results[0]["event_id"] == "evt-insert"
