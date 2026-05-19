"""HealthKit personal archive ingestion endpoint."""

from __future__ import annotations

import json
from datetime import UTC, datetime

from fastapi import APIRouter
from sqlalchemy import select

from workoutdb_server.api.deps import CurrentUserId, DbSession
from workoutdb_server.api.schemas import HealthArchiveUploadIn, HealthArchiveUploadOut
from workoutdb_server.models import (
    HealthArchiveRecord,
    HealthArchiveRequestSet,
    HealthArchiveTombstone,
)

router = APIRouter(prefix="/api/health", tags=["health-archive"])


@router.post("/archive", response_model=HealthArchiveUploadOut)
def upload_health_archive(
    payload: HealthArchiveUploadIn,
    db: DbSession,
    user_id: CurrentUserId,
) -> HealthArchiveUploadOut:
    now = datetime.now(UTC)
    for record in payload.records:
        _upsert_record(db, user_id, record, now)
    for tombstone in payload.tombstones:
        _upsert_tombstone(db, user_id, tombstone)
    _upsert_request_set(db, user_id, payload, now)
    db.commit()
    return HealthArchiveUploadOut(
        request_set_key=payload.request_set_key,
        acknowledged_cursor=payload.next_cursor,
        records_received=len(payload.records),
        tombstones_received=len(payload.tombstones),
        server_time=now,
    )


def _upsert_record(db: DbSession, user_id: str, record, now: datetime) -> None:
    existing = (
        db.execute(
            select(HealthArchiveRecord)
            .where(HealthArchiveRecord.user_id == user_id)
            .where(HealthArchiveRecord.descriptor_id == record.descriptor_id)
            .where(HealthArchiveRecord.external_id == record.external_id)
        )
        .scalars()
        .first()
    )
    row = existing or HealthArchiveRecord(
        id=record.id,
        user_id=user_id,
        external_id=record.external_id,
        descriptor_id=record.descriptor_id,
        first_seen_at=now,
    )
    if existing is None:
        db.add(row)
    row.sample_kind = record.sample_kind
    row.source_bundle_identifier = record.source_bundle_identifier
    row.start_at = record.start_at
    row.end_at = record.end_at
    row.unit = record.value.unit
    row.value_json = record.value.model_dump_json(exclude_none=True)
    row.metadata_json = json.dumps(record.metadata, sort_keys=True)
    row.last_seen_at = now


def _upsert_tombstone(db: DbSession, user_id: str, tombstone) -> None:
    existing = (
        db.execute(
            select(HealthArchiveTombstone)
            .where(HealthArchiveTombstone.user_id == user_id)
            .where(HealthArchiveTombstone.descriptor_id == tombstone.descriptor_id)
            .where(HealthArchiveTombstone.external_id == tombstone.external_id)
        )
        .scalars()
        .first()
    )
    if existing is None:
        db.add(
            HealthArchiveTombstone(
                id=tombstone.id,
                user_id=user_id,
                descriptor_id=tombstone.descriptor_id,
                external_id=tombstone.external_id,
                observed_at=tombstone.observed_at,
            )
        )
    else:
        existing.observed_at = tombstone.observed_at


def _upsert_request_set(
    db: DbSession,
    user_id: str,
    payload: HealthArchiveUploadIn,
    now: datetime,
) -> None:
    row = (
        db.execute(
            select(HealthArchiveRequestSet)
            .where(HealthArchiveRequestSet.user_id == user_id)
            .where(HealthArchiveRequestSet.request_set_key == payload.request_set_key)
        )
        .scalars()
        .first()
    )
    if row is None:
        row = HealthArchiveRequestSet(
            user_id=user_id,
            request_set_key=payload.request_set_key,
            records_received=0,
            tombstones_received=0,
        )
        db.add(row)
    row.server_namespace = payload.server_namespace
    row.descriptor_fingerprint = payload.descriptor_fingerprint
    row.acknowledged_cursor = payload.next_cursor
    row.records_received += len(payload.records)
    row.tombstones_received += len(payload.tombstones)
    row.last_uploaded_at = now
