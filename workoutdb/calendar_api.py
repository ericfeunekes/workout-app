from __future__ import annotations

from datetime import date, datetime, time, timedelta
from typing import Iterable, Literal, TypedDict

from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

from .config import AppConfig
from .google_auth import get_credentials

CALENDAR_SCOPES = ["https://www.googleapis.com/auth/calendar"]


def calendar_service(creds):
    return build("calendar", "v3", credentials=creds, cache_discovery=False)


def list_calendars(cfg: AppConfig) -> list[dict]:
    creds = get_credentials(
        cfg.google.client_secret_path,
        cfg.google.token_path,
        CALENDAR_SCOPES,
    )
    service = calendar_service(creds)
    items: list[dict] = []
    page_token = None
    while True:
        resp = service.calendarList().list(pageToken=page_token).execute()
        items.extend(resp.get("items", []))
        page_token = resp.get("nextPageToken")
        if not page_token:
            break
    return items


def build_event_payload(
    *,
    summary: str,
    workout_date: date,
    start_time: time,
    duration_min: int,
    description: str | None,
    tzinfo,
) -> dict:
    start_dt = datetime.combine(workout_date, start_time, tzinfo=tzinfo)
    end_dt = start_dt + timedelta(minutes=duration_min)
    payload = {
        "summary": summary,
        "start": {"dateTime": start_dt.isoformat()},
        "end": {"dateTime": end_dt.isoformat()},
    }
    if description:
        payload["description"] = description
    return payload


class CalendarUpsertItem(TypedDict):
    payload: dict
    event_id: str | None
    planned_id: str | None


class CalendarUpsertResult(TypedDict):
    planned_id: str | None
    event_id: str | None
    status: Literal["created", "updated", "failed"]
    error: str | None
    response: dict | None


def upsert_events(
    cfg: AppConfig,
    *,
    calendar_id: str,
    events: Iterable[CalendarUpsertItem],
) -> list[CalendarUpsertResult]:
    creds = get_credentials(
        cfg.google.client_secret_path,
        cfg.google.token_path,
        CALENDAR_SCOPES,
    )
    service = calendar_service(creds)
    results: list[CalendarUpsertResult] = []
    for event in events:
        event_id = event.get("event_id")
        payload = event["payload"]
        try:
            if event_id:
                try:
                    created = service.events().update(
                        calendarId=calendar_id,
                        eventId=event_id,
                        body=payload,
                    ).execute()
                    status: Literal["created", "updated"] = "updated"
                except HttpError as exc:
                    status_code = getattr(getattr(exc, "resp", None), "status", None)
                    if isinstance(status_code, str) and status_code.isdigit():
                        status_code = int(status_code)
                    if status_code in (404, 410):
                        created = service.events().insert(
                            calendarId=calendar_id,
                            body=payload,
                        ).execute()
                        status = "created"
                    else:
                        raise
            else:
                created = service.events().insert(
                    calendarId=calendar_id,
                    body=payload,
                ).execute()
                status = "created"
            results.append(
                {
                    "planned_id": event.get("planned_id"),
                    "event_id": created.get("id"),
                    "status": status,
                    "error": None,
                    "response": created,
                }
            )
        except Exception as exc:  # noqa: BLE001
            results.append(
                {
                    "planned_id": event.get("planned_id"),
                    "event_id": event_id,
                    "status": "failed",
                    "error": str(exc),
                    "response": None,
                }
            )
    return results
