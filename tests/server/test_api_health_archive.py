"""HealthKit archive ingestion endpoint tests."""

from collections.abc import Iterator
from pathlib import Path

from fastapi.testclient import TestClient
from sqlalchemy import Engine, text
from sqlalchemy.orm import Session
from workoutdb_server.api.deps import get_db
from workoutdb_server.config import get_settings
from workoutdb_server.main import app


def _record_payload(record_id: str = "70000000-0000-4000-8000-000000000001") -> dict:
    return {
        "id": record_id,
        "external_id": "hk-sample-1",
        "descriptor_id": "HKQuantityTypeIdentifierHeartRate",
        "sample_kind": "quantity",
        "source_bundle_identifier": "com.apple.Health",
        "start_at": "2026-05-18T12:00:00Z",
        "end_at": "2026-05-18T12:01:00Z",
        "value": {
            "kind": "quantity",
            "quantity_value": 122,
            "unit": "count/min",
        },
        "metadata": {"device": "simulator"},
    }


def _upload_payload(**overrides) -> dict:
    payload = {
        "request_set_key": "server-a|all-supported|fp-1",
        "server_namespace": "server-a",
        "descriptor_fingerprint": "fp-1",
        "next_cursor": "cursor-1",
        "records": [_record_payload()],
        "tombstones": [
            {
                "id": "80000000-0000-4000-8000-000000000001",
                "descriptor_id": "HKQuantityTypeIdentifierHeartRate",
                "external_id": "hk-deleted-1",
                "observed_at": "2026-05-18T12:02:00Z",
            }
        ],
    }
    payload.update(overrides)
    return payload


def test_health_archive_upload_upserts_records_tombstones_and_acknowledges_cursor(
    client,
    test_engine,
) -> None:
    response = client.post("/api/health/archive", json=_upload_payload())

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["request_set_key"] == "server-a|all-supported|fp-1"
    assert body["acknowledged_cursor"] == "cursor-1"
    assert body["records_received"] == 1
    assert body["tombstones_received"] == 1

    with Session(test_engine) as session:
        record = session.execute(text("SELECT * FROM health_archive_record")).mappings().one()
        tombstone = session.execute(text("SELECT * FROM health_archive_tombstone")).mappings().one()
        request_set = (
            session.execute(text("SELECT * FROM health_archive_request_set")).mappings().one()
        )

    assert record["external_id"] == "hk-sample-1"
    assert record["unit"] == "count/min"
    assert '"quantity_value":122' in record["value_json"]
    assert tombstone["external_id"] == "hk-deleted-1"
    assert request_set["acknowledged_cursor"] == "cursor-1"
    assert request_set["records_received"] == 1
    assert request_set["tombstones_received"] == 1


def test_health_archive_upload_is_idempotent_by_external_identity(client, test_engine) -> None:
    first = client.post("/api/health/archive", json=_upload_payload(next_cursor="cursor-1"))
    assert first.status_code == 200, first.text
    second_payload = _upload_payload(
        next_cursor="cursor-2",
        records=[_record_payload("70000000-0000-4000-8000-000000000002")],
    )
    second_payload["records"][0]["value"]["quantity_value"] = 130

    second = client.post("/api/health/archive", json=second_payload)

    assert second.status_code == 200, second.text
    with Session(test_engine) as session:
        record_count = session.execute(
            text("SELECT COUNT(*) FROM health_archive_record")
        ).scalar_one()
        record = session.execute(text("SELECT * FROM health_archive_record")).mappings().one()
        request_set = (
            session.execute(text("SELECT * FROM health_archive_request_set")).mappings().one()
        )

    assert record_count == 1
    assert record["id"] == "70000000-0000-4000-8000-000000000001"
    assert '"quantity_value":130' in record["value_json"]
    assert request_set["acknowledged_cursor"] == "cursor-2"
    assert request_set["records_received"] == 1
    assert request_set["tombstones_received"] == 1


def test_health_archive_upload_rejects_request_set_metadata_mismatch(client) -> None:
    first = client.post("/api/health/archive", json=_upload_payload())
    assert first.status_code == 200, first.text

    changed_namespace = client.post(
        "/api/health/archive",
        json=_upload_payload(server_namespace="server-b"),
    )
    changed_fingerprint = client.post(
        "/api/health/archive",
        json=_upload_payload(descriptor_fingerprint="fp-2"),
    )

    assert changed_namespace.status_code == 409
    assert changed_fingerprint.status_code == 409


def test_health_archive_upload_is_user_scoped(client, test_engine, test_user_id) -> None:
    response = client.post("/api/health/archive", json=_upload_payload())
    assert response.status_code == 200, response.text

    with Session(test_engine) as session:
        rows = session.execute(text("SELECT user_id FROM health_archive_record")).fetchall()

    assert rows == [(test_user_id,)]


def test_health_archive_upload_requires_valid_bearer_token(
    test_engine: Engine,
    tmp_db_path: Path,
    monkeypatch,
) -> None:
    monkeypatch.setenv("WORKOUTDB_BEARER_TOKEN", "expected-token-123456")
    monkeypatch.setenv("WORKOUTDB_USER_ID", "11111111-1111-1111-1111-111111111111")
    monkeypatch.setenv("WORKOUTDB_DB_PATH", str(tmp_db_path))
    get_settings.cache_clear()

    def _override_db() -> Iterator[Session]:
        session = Session(test_engine)
        try:
            yield session
        finally:
            session.close()

    app.dependency_overrides[get_db] = _override_db
    try:
        with TestClient(app) as unauthenticated:
            missing = unauthenticated.post("/api/health/archive", json=_upload_payload())
            wrong = unauthenticated.post(
                "/api/health/archive",
                json=_upload_payload(),
                headers={"Authorization": "Bearer wrong-token"},
            )
    finally:
        app.dependency_overrides.clear()
        get_settings.cache_clear()

    assert missing.status_code == 401
    assert wrong.status_code == 401


def test_health_archive_rejects_invalid_value_shape(client) -> None:
    payload = _upload_payload()
    payload["records"][0]["value"] = {"kind": "quantity", "unit": "count/min"}

    response = client.post("/api/health/archive", json=payload)

    assert response.status_code == 422
    assert "quantity health archive values require quantity_value and unit" in response.text


def test_health_archive_rejects_sample_kind_value_kind_mismatch(client) -> None:
    payload = _upload_payload()
    payload["records"][0]["sample_kind"] = "quantity"
    payload["records"][0]["value"] = {
        "kind": "workout",
        "workout_activity_type": "37",
        "duration_seconds": 1200,
    }

    response = client.post("/api/health/archive", json=payload)

    assert response.status_code == 422
    assert "sample_kind must match health archive value kind" in response.text
