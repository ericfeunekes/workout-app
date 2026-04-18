"""Pydantic request/response schemas for the API.

Lives under api/ because these are the wire contract — the app consumes them, Claude
produces them. ORM models in workoutdb_server.models are separate and internal.

JSON blob fields (prescription_json, timing_config_json, tags_json, etc.) are
accepted/returned as strings on the wire. Validating the inner JSON shape against the
spec's documented structures is deferred until a concrete need arises — keeping it
stringly typed preserves the "new prescription shape doesn't require schema changes"
invariant.
"""

from __future__ import annotations

import json
import uuid as _uuid
from datetime import UTC, datetime
from typing import Annotated, Any, Literal

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    PlainSerializer,
    field_validator,
    model_validator,
)


def _serialize_utc(value: datetime) -> str:
    """Emit ISO-8601 with a Z suffix so the Swift decoder can parse it.

    SQLite strips timezone on write, so the ORM hands us naive datetimes even
    though `_utcnow()` returns UTC-aware. Without the Z suffix the app's
    `JSONDecoder.workoutDB()` rejects the value and bootstrap silently falls
    through to an empty cache (the "No workouts yet" screen after a successful
    pull). Keep this stable across every `datetime` field on the wire.
    """
    aware = value if value.tzinfo is not None else value.replace(tzinfo=UTC)
    iso = aware.astimezone(UTC).isoformat()
    # isoformat returns "...+00:00"; convert to "...Z" to match the rest of
    # the API surface (server_time already uses Z).
    return iso.replace("+00:00", "Z")


UtcDatetime = Annotated[datetime, PlainSerializer(_serialize_utc, return_type=str)]


class _UuidReadBase(BaseModel):
    """Lowercase every `id`/`*_id` field. Trust the DB — no format validation.

    Used on Read-side schemas (ORM → Pydantic via `from_attributes=True`).
    The DB is the source of truth: any row already persisted is considered
    valid by construction, so this base only canonicalizes case for wire
    output. Format enforcement belongs at ingest, not egress — a strict
    validator here would 500 `GET /api/sync/pull` the moment a legacy or
    seed row (e.g. `ex-0`) appears in the DB (bug-031).
    """

    @model_validator(mode="before")
    @classmethod
    def _lowercase_uuid_fields(cls, data: Any) -> Any:
        if not isinstance(data, dict):
            return data
        for key, value in list(data.items()):
            if not isinstance(value, str):
                continue
            if key == "id" or key.endswith("_id"):
                data[key] = value.lower()
        return data


class _UuidInputBase(BaseModel):
    """Lowercase AND validate UUID format on every `id`/`*_id` field.

    Used on input-side schemas (Create/Update/Upsert/sync payloads). This is
    the write-time contract: callers must supply real UUIDs or get a 422.

    Apple's `UUID.uuidString` returns UPPERCASE (Swift default), so lowercase
    first to match the SQLite TEXT PK case-sensitivity. Then validate format:
    without this, `"id": "not-a-uuid"` would lowercase cleanly and INSERT as
    a raw string primary key, silently corrupting the database (found
    2026-04-18 by ad-hoc QA; tracked as `bug-030`).

    Read-side schemas inherit from `_UuidReadBase` instead — the DB is
    already trusted. See bug-031 for why format validation on egress
    regresses sync_pull.
    """

    @model_validator(mode="before")
    @classmethod
    def _lowercase_and_validate_uuid_fields(cls, data: Any) -> Any:
        if not isinstance(data, dict):
            return data
        for key, value in list(data.items()):
            if not isinstance(value, str):
                continue
            if key == "id" or key.endswith("_id"):
                lowered = value.lower()
                try:
                    _uuid.UUID(lowered)
                except ValueError as exc:
                    raise ValueError(f"{key} is not a valid UUID: {value!r}") from exc
                data[key] = lowered
        return data


# ---------- Users ----------


class AppUserRead(_UuidReadBase):
    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    created_at: UtcDatetime


# ---------- Exercises ----------


class ExerciseUpsert(_UuidInputBase):
    """Claude owns the id. Upsert-by-id: same id updates, new id inserts."""

    id: str
    name: str
    notes: str | None = None
    demo_url: str | None = None
    # Smart defaults (ADR-2026-04-18). Library-level prescription fields and
    # alternatives that get merged into items referencing this exercise.
    default_prescription_json: str | None = None
    default_alternatives_json: str | None = None

    @field_validator("default_prescription_json", "default_alternatives_json")
    @classmethod
    def _defaults_must_be_valid_json(cls, value: str | None) -> str | None:
        """Reject malformed JSON at ingest (bug-032).

        `prescription_merge._load_or_empty` assumes these columns hold valid
        JSON; without this validator a bad string accepted here crashes every
        future `POST /api/workouts` referencing this exercise with a 500.
        Fail loudly at the write side so the invariant is enforced once,
        where the data enters the system.

        Deeper shape validation (object vs array, required keys) stays in
        the merge helpers — this only proves the blob is parseable.
        """
        if value is None:
            return value
        try:
            json.loads(value)
        except (json.JSONDecodeError, ValueError) as exc:
            raise ValueError(f"not valid JSON: {exc}") from exc
        return value


class ExerciseRead(_UuidReadBase):
    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    notes: str | None
    demo_url: str | None
    default_prescription_json: str | None = None
    default_alternatives_json: str | None = None


# ---------- Workout tree (nested create/read) ----------


class ExerciseAlternativeIn(_UuidInputBase):
    id: str | None = None
    exercise_id: str
    reason: str
    parameter_overrides_json: str | None = None


class ExerciseAlternativeRead(_UuidReadBase):
    model_config = ConfigDict(from_attributes=True)

    id: str
    exercise_id: str
    reason: str
    parameter_overrides_json: str | None


class WorkoutItemIn(_UuidInputBase):
    id: str | None = None
    position: int
    exercise_id: str
    prescription_json: str
    alternatives: list[ExerciseAlternativeIn] = Field(default_factory=list)


class WorkoutItemRead(_UuidReadBase):
    model_config = ConfigDict(from_attributes=True)

    id: str
    position: int
    exercise_id: str
    # Resolved form (library defaults merged in). Opaque.
    prescription_json: str
    # The original sparse payload the client sent. Null if the client sent
    # a fully-resolved prescription (no merge happened). See
    # docs/decisions/ADR-2026-04-18-smart-defaults.md.
    prescription_json_raw: str | None = None
    alternatives: list[ExerciseAlternativeRead]


class BlockIn(_UuidInputBase):
    id: str | None = None
    position: int
    parent_block_id: str | None = None
    name: str | None = None
    timing_mode: Literal[
        "straight_sets",
        "superset",
        "circuit",
        "emom",
        "amrap",
        "for_time",
        "intervals",
        "tabata",
        "continuous",
        "custom",
        "rest",
    ]
    timing_config_json: str
    rounds: int | None = None
    rounds_rep_scheme_json: str | None = None
    notes: str | None = None
    workout_items: list[WorkoutItemIn] = Field(default_factory=list)


class BlockRead(_UuidReadBase):
    model_config = ConfigDict(from_attributes=True)

    id: str
    position: int
    parent_block_id: str | None
    name: str | None
    timing_mode: str
    timing_config_json: str
    rounds: int | None
    rounds_rep_scheme_json: str | None
    notes: str | None
    workout_items: list[WorkoutItemRead]


class WorkoutCreate(_UuidInputBase):
    """Accepts a full workout tree (blocks → items → alternatives) in one request.

    user_id is resolved from the bearer token, not the body (ADR-2026-04-17).
    """

    id: str | None = None
    name: str
    scheduled_date: str | None = None
    status: Literal["planned", "active", "completed", "skipped"] = "planned"
    source: Literal["claude", "manual"] = "claude"
    notes: str | None = None
    tags_json: str | None = None
    blocks: list[BlockIn] = Field(default_factory=list)


class WorkoutUpdate(_UuidInputBase):
    """Partial update. Blocks, if present, replace the full tree (simpler than diff)."""

    name: str | None = None
    scheduled_date: str | None = None
    status: Literal["planned", "active", "completed", "skipped"] | None = None
    notes: str | None = None
    tags_json: str | None = None
    completed_at: datetime | None = None
    blocks: list[BlockIn] | None = None


class WorkoutRead(_UuidReadBase):
    model_config = ConfigDict(from_attributes=True)

    id: str
    user_id: str
    name: str
    scheduled_date: str | None
    status: str
    source: str
    notes: str | None
    tags_json: str | None
    created_at: UtcDatetime
    updated_at: UtcDatetime
    completed_at: UtcDatetime | None
    blocks: list[BlockRead]


# ---------- Set logs (app pushes these back) ----------


class SetLogIn(_UuidInputBase):
    # id is required — the app assigns a UUID when the set is logged (possibly offline).
    # Requiring it here makes sync/results genuinely idempotent per the spec: the same
    # SetLog pushed twice updates in place instead of inserting a duplicate.
    id: str
    workout_item_id: str
    performed_exercise_id: str | None = None
    set_index: int
    reps: int | None = None
    weight: float | None = None
    weight_unit: Literal["kg", "lb"] | None = None
    duration_sec: float | None = None
    distance_m: float | None = None
    rir: int | None = Field(default=None, ge=0, le=5)
    is_warmup: bool = False
    started_at: datetime | None = None
    completed_at: datetime
    hr_avg_bpm: int | None = None
    hr_max_bpm: int | None = None
    cadence_avg_spm: int | None = None
    motion_samples_ref: str | None = None
    notes: str | None = None


class SetLogRead(_UuidReadBase):
    model_config = ConfigDict(from_attributes=True)

    id: str
    workout_item_id: str
    performed_exercise_id: str | None
    set_index: int
    reps: int | None
    weight: float | None
    weight_unit: str | None
    duration_sec: float | None
    distance_m: float | None
    rir: int | None
    is_warmup: bool
    started_at: UtcDatetime | None
    completed_at: UtcDatetime
    hr_avg_bpm: int | None
    hr_max_bpm: int | None
    cadence_avg_spm: int | None
    motion_samples_ref: str | None
    notes: str | None


# ---------- User parameters (append-only) ----------


class UserParameterIn(_UuidInputBase):
    """user_id is resolved from the bearer token (ADR-2026-04-17)."""

    key: str
    value: str
    source: Literal["claude", "app_log", "manual"] = "claude"
    # updated_at optional on create; server stamps now if omitted.
    updated_at: datetime | None = None


class UserParameterRead(_UuidReadBase):
    model_config = ConfigDict(from_attributes=True)

    id: str
    user_id: str
    key: str
    value: str
    updated_at: UtcDatetime
    source: str


# ---------- Sync ----------


class WorkoutStatusUpdate(_UuidInputBase):
    """App tells server 'this workout transitioned to status X at time Y.'"""

    workout_id: str
    status: Literal["active", "completed", "skipped"]
    completed_at: datetime | None = None


class SyncResultsIn(_UuidInputBase):
    """App pushes this when a workout finishes (or on next connectivity)."""

    set_logs: list[SetLogIn] = Field(default_factory=list)
    status_updates: list[WorkoutStatusUpdate] = Field(default_factory=list)


class ExerciseLastPerformed(_UuidReadBase):
    """Inline history the app uses to show 'last time you did this exercise.'"""

    exercise_id: str
    last_set_logs: list[SetLogRead]
    prescription_json: str | None = None


class SyncPullOut(_UuidReadBase):
    workouts: list[WorkoutRead]
    exercises: list[ExerciseRead]
    user_parameters: list[UserParameterRead]
    last_performed: list[ExerciseLastPerformed]
    server_time: UtcDatetime


# ---------- Telemetry ----------


class TelemetryEventIn(_UuidInputBase):
    """One app-emitted telemetry event. See `server/db/migrations/005_event_log.sql`.

    `data_json` is a freeform string (not parsed) so new event shapes don't
    require schema changes. `workout_id` / `set_log_id` are nullable pointers
    for filtering; not FK-validated because the app may emit events that
    reference IDs from the same batch.
    """

    id: str
    timestamp: datetime
    session_id: str
    kind: str
    name: str
    data_json: str | None = None
    workout_id: str | None = None
    set_log_id: str | None = None


class TelemetryEventsPayload(_UuidInputBase):
    """Batch of telemetry events. POST /api/telemetry/events body shape.

    Per-request cap of 500 events (bug-033). The client-side ring buffer
    holds 10k events locally; the push queue drains them one event per
    `PushItem.Payload.events([Event])` entry in practice (see
    `docs/features/telemetry.md` § "What it deliberately doesn't do"), so
    500 per POST is generous — a misbehaving client that fans an entire
    10k buffer into one payload would be rejected before we touch the DB.
    Pydantic emits 422 on overflow, which the app retries on its next
    flush tick with a smaller batch.
    """

    events: list[TelemetryEventIn] = Field(default_factory=list, max_length=500)


# ---------- Version handshake ----------


class VersionInfo(_UuidReadBase):
    schema_version: str | None
    applied_migrations: list[str]
    server_version: str
