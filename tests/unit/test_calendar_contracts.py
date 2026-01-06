from __future__ import annotations

import json
from pathlib import Path

import yaml


def _load_cassette() -> list[dict]:
    cassette = Path("/Users/ericfeunekes/coding/ai-assistant/tests/cassettes/calendar_full_flow.yaml")
    if not cassette.exists():
        raise AssertionError(f"Missing VCR cassette: {cassette}")
    data = yaml.safe_load(cassette.read_text())
    return data.get("http_interactions", data.get("interactions", []))


def _responses_for_uri(interactions: list[dict], uri_substr: str) -> list[dict]:
    matches = []
    for item in interactions:
        uri = item.get("request", {}).get("uri", "")
        if uri_substr in uri:
            matches.append(item.get("response", {}))
    return matches


def test_calendar_list_response_shape() -> None:
    interactions = _load_cassette()
    responses = _responses_for_uri(interactions, "/calendar/v3/users/me/calendarList")
    assert responses, "Expected calendarList response in cassette"
    body = responses[0].get("body", {}).get("string", "")
    payload = json.loads(body)
    assert payload.get("kind") == "calendar#calendarList"
    items = payload.get("items")
    assert isinstance(items, list) and items
    sample = items[0]
    assert "id" in sample
    assert "summary" in sample


def test_calendar_events_list_response_shape() -> None:
    interactions = _load_cassette()
    responses = _responses_for_uri(interactions, "/calendar/v3/calendars/")
    assert responses, "Expected calendar events response in cassette"
    body = responses[0].get("body", {}).get("string", "")
    payload = json.loads(body)
    assert payload.get("kind") == "calendar#events"
    items = payload.get("items")
    assert isinstance(items, list)
    if items:
        sample = items[0]
        assert "id" in sample
        assert "htmlLink" in sample
        assert "start" in sample and "end" in sample


def test_calendar_event_upsert_response_shape() -> None:
    interactions = _load_cassette()
    responses = _responses_for_uri(interactions, "/calendar/v3/calendars/")
    event_responses = []
    for response in responses:
        body = response.get("body", {}).get("string", "")
        payload = json.loads(body)
        if payload.get("kind") == "calendar#event":
            event_responses.append(payload)
    assert event_responses, "Expected calendar event response in cassette"
    sample = event_responses[0]
    assert "id" in sample
    assert "htmlLink" in sample
