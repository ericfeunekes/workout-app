"""Telemetry events endpoint.

POST /api/telemetry/events — app → server. Batch of structured events that
durable-log app behaviour (interactions, state transitions, network calls,
timer ticks, errors). Idempotent upsert by id: retrying a batch is safe.

Per ADR-2026-04-17, the caller's user_id is resolved from the bearer token,
not accepted in the body. Events stamped with another user's id would be
normalised to the authenticated user anyway — we store `user_id` from auth.
"""

from datetime import UTC, datetime

from fastapi import APIRouter

from workoutdb_server.api.deps import CurrentUserId, DbSession
from workoutdb_server.api.schemas import TelemetryEventIn, TelemetryEventsPayload
from workoutdb_server.models import EventLog

router = APIRouter(prefix="/api/telemetry", tags=["telemetry"])


@router.post("/events", response_model=dict)
def push_events(
    payload: TelemetryEventsPayload,
    db: DbSession,
    user_id: CurrentUserId,
) -> dict:
    """Upsert a batch of telemetry events.

    Tenant isolation: `user_id` is always taken from the bearer token, never
    the body. If a row with the same id already exists under another user,
    we treat it as a no-op — a user cannot overwrite another user's events.
    """
    received_at = datetime.now(UTC)
    accepted = 0
    for event in payload.events:
        _upsert_event(db, event, user_id=user_id, received_at=received_at)
        accepted += 1
    db.commit()
    return {"events_received": accepted}


def _upsert_event(
    db: DbSession,
    payload: TelemetryEventIn,
    *,
    user_id: str,
    received_at: datetime,
) -> None:
    row = db.get(EventLog, payload.id)
    if row is None:
        db.add(
            EventLog(
                id=payload.id,
                user_id=user_id,
                ts=payload.timestamp,
                session_id=payload.session_id,
                kind=payload.kind,
                name=payload.name,
                data_json=payload.data_json,
                workout_id=payload.workout_id,
                set_log_id=payload.set_log_id,
                received_at=received_at,
            )
        )
        return
    # Cross-tenant guard: if a row with this id belongs to another user,
    # skip silently. The app assigns UUIDs so collisions are only reachable
    # via a misbehaving client; we don't want to leak existence either way.
    if row.user_id != user_id:
        return
    row.ts = payload.timestamp
    row.session_id = payload.session_id
    row.kind = payload.kind
    row.name = payload.name
    row.data_json = payload.data_json
    row.workout_id = payload.workout_id
    row.set_log_id = payload.set_log_id
