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
    BeforeValidator,
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


def _require_z_suffix(value: Any) -> Any:
    """Reject incoming datetime strings that don't end with a literal `Z`.

    Session invariant: every datetime on the wire carries a `Z` suffix. The
    Swift encoder emits `Z`; Pydantic's default datetime parser is lax and
    accepts `+00:00`, `+0000`, naive, etc., so without this guard a client
    that drifted from the contract would still be silently accepted and
    stored. Failing loudly at ingest keeps the wire format one-way.

    Non-string values pass through untouched — Pydantic still gets to run
    its normal datetime coercion for programmatic callers (tests that pass
    `datetime` instances directly, ORM round-trips via `from_attributes`).
    `None` also passes through so the Optional-field machinery keeps
    working; the real parser enforces non-null separately.
    """
    if isinstance(value, str) and not value.endswith("Z"):
        raise ValueError(f"datetime must end with 'Z' (literal UTC), got {value!r}")
    return value


UtcDatetime = Annotated[datetime, PlainSerializer(_serialize_utc, return_type=str)]

# Input-side datetime: validate the `Z` suffix before Pydantic parses. Used
# on every Create/Update/Upsert schema so a misbehaving client can't slip
# `+00:00` through. Read-side (`UtcDatetime`) doesn't need the validator —
# the serializer produces `Z` by construction.
UtcDatetimeIn = Annotated[datetime, BeforeValidator(_require_z_suffix)]


def _walk_uuid_fields(data: Any, *, validate: bool = False) -> Any:
    """Walk `id`/`*_id` string fields on a dict, lowercase them, optionally validate.

    Shared helper for `_UuidReadBase` (lowercase only — DB is trusted) and
    `_UuidInputBase` (lowercase + UUID format validation — write-time contract).
    Non-dict values pass through untouched so Pydantic can still run its normal
    coercion pipeline (e.g. ORM objects flowing through `from_attributes=True`).

    When `validate=True`, a non-UUID string raises `ValueError` — Pydantic
    translates that into a 422 at the request boundary. See `_UuidInputBase`
    for the invariant this enforces (bug-030) and `_UuidReadBase` for why
    egress deliberately skips validation (bug-031).
    """
    if not isinstance(data, dict):
        return data
    for key, value in list(data.items()):
        if not isinstance(value, str):
            continue
        if key == "id" or key.endswith("_id"):
            lowered = value.lower()
            if validate:
                try:
                    _uuid.UUID(lowered)
                except ValueError as exc:
                    raise ValueError(f"{key} is not a valid UUID: {value!r}") from exc
            data[key] = lowered
    return data


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
        return _walk_uuid_fields(data, validate=False)


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
        return _walk_uuid_fields(data, validate=True)


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

    @field_validator("default_prescription_json")
    @classmethod
    def _default_prescription_must_be_json_object(cls, value: str | None) -> str | None:
        """Reject malformed or non-object `default_prescription_json` at ingest.

        bug-032: `prescription_merge._load_or_empty` assumes this column holds
        a JSON *object*; without this validator a bad value here crashed every
        future `POST /api/workouts` referencing this exercise with a 500.

        bug-035: extended from "valid JSON" to "JSON object". An array or
        scalar parses cleanly but still blows up in the merge helper, which
        means the validation is load-bearing at the shape level, not just
        parseability. Fail once, at ingest, where the data enters the system.
        """
        if value is None:
            return value
        try:
            parsed = json.loads(value)
        except (json.JSONDecodeError, ValueError) as exc:
            raise ValueError(f"not valid JSON: {exc}") from exc
        if not isinstance(parsed, dict):
            raise ValueError(
                f"default_prescription_json must be a JSON object, got {type(parsed).__name__}"
            )
        return value

    @field_validator("default_alternatives_json")
    @classmethod
    def _default_alternatives_must_be_json_array(cls, value: str | None) -> str | None:
        """Reject malformed or non-array `default_alternatives_json` at ingest.

        Same class of fix as `default_prescription_json` (bug-032, bug-035):
        `merge_alternatives` expects a JSON array. Any other shape crashes the
        merge at workout POST time with a 500. Shape-check at write time.
        """
        if value is None:
            return value
        try:
            parsed = json.loads(value)
        except (json.JSONDecodeError, ValueError) as exc:
            raise ValueError(f"not valid JSON: {exc}") from exc
        if not isinstance(parsed, list):
            raise ValueError(
                f"default_alternatives_json must be a JSON array, got {type(parsed).__name__}"
            )
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
        "accumulate",
        "custom",
        "rest",
    ]
    timing_config_json: str
    rounds: int | None = None
    rounds_rep_scheme_json: str | None = None
    notes: str | None = None
    intent: str | None = None
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
    intent: str | None
    workout_items: list[WorkoutItemRead]


class PrimitiveWorkTargetIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    metric: Literal["reps", "duration", "distance", "rounds", "completion", "load_carried"]
    value_form: Literal["single", "range", "open"]
    value: float | None = None
    role: Literal["completion", "observation"]

    @model_validator(mode="after")
    def _value_matches_form(self) -> "PrimitiveWorkTargetIn":
        if self.value_form == "open" and self.value is not None:
            raise ValueError("open work_target values must be null")
        if self.value_form == "single" and self.value is None:
            raise ValueError("single work_target values require a number")
        return self


class PrimitiveLoadIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    value: float | None = None
    unit: Literal["kg", "lb", "1rm", "bodyweight"]
    unit_type: Literal["absolute", "relative", "implicit_bodyweight"]

    @model_validator(mode="after")
    def _load_shape_matches_unit_type(self) -> "PrimitiveLoadIn":
        if self.unit_type == "absolute" and self.unit not in {"kg", "lb"}:
            raise ValueError("absolute primitive loads require kg or lb units")
        if self.unit_type == "absolute" and self.value is None:
            raise ValueError("absolute primitive loads require a number")
        if self.unit_type == "relative" and self.unit not in {"1rm", "bodyweight"}:
            raise ValueError("relative primitive loads require 1rm or bodyweight units")
        if self.unit_type == "relative" and self.value is None:
            raise ValueError("relative primitive loads require a number")
        if self.unit_type == "implicit_bodyweight":
            if self.unit != "bodyweight" or self.value is not None:
                raise ValueError(
                    "implicit_bodyweight primitive loads require bodyweight and null value"
                )
        return self


class PrimitiveStimulusIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    type: Literal["rir", "hr_zone"]
    target: float | None = None


class PrimitiveTimingIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    mode: Literal["set_bounded", "time_bounded", "cap_bounded", "target_bounded"]
    interval_sec: int | None = None
    rounds: int | None = None
    cap_sec: int | None = None

    @model_validator(mode="after")
    def _required_params(self) -> "PrimitiveTimingIn":
        if self.mode == "time_bounded" and (self.interval_sec is None or self.rounds is None):
            raise ValueError("time_bounded timing requires interval_sec and rounds")
        if self.mode == "cap_bounded" and self.cap_sec is None:
            raise ValueError("cap_bounded timing requires cap_sec")
        return self


class PrimitiveSlotIn(_UuidInputBase):
    model_config = ConfigDict(extra="forbid")

    id: str
    exercise_id: str
    work_target: list[PrimitiveWorkTargetIn] = Field(default_factory=list)
    load: PrimitiveLoadIn | None = None
    stimuli: list[PrimitiveStimulusIn] = Field(default_factory=list)
    post_rest_sec: int = 0
    is_warmup: bool = False

    @model_validator(mode="after")
    def _completion_target_is_unambiguous(self) -> "PrimitiveSlotIn":
        completion_count = sum(1 for target in self.work_target if target.role == "completion")
        if completion_count > 1:
            raise ValueError("primitive slots may not define multiple completion work_targets")
        return self


class PrimitiveSetIn(_UuidInputBase):
    model_config = ConfigDict(extra="forbid")

    id: str
    title: str | None = None
    timing: PrimitiveTimingIn
    traversal: Literal["sequential", "round_robin", "amrap"] = "sequential"
    repeat: int = Field(default=1, ge=1)
    work_target: list[PrimitiveWorkTargetIn] = Field(default_factory=list)
    slots: list[PrimitiveSlotIn] = Field(default_factory=list)

    @model_validator(mode="after")
    def _legal_runtime_cell(self) -> "PrimitiveSetIn":
        if self.traversal == "amrap" and self.timing.mode in {"set_bounded", "target_bounded"}:
            raise ValueError(f"{self.timing.mode} x amrap is not a legal primitive runtime cell")
        if not self.slots:
            raise ValueError("primitive sets require at least one slot")
        if self.timing.mode == "cap_bounded" and self.traversal == "amrap":
            has_rounds = any(
                target.metric == "rounds" and target.role == "observation"
                for target in self.work_target
            )
            if not has_rounds:
                raise ValueError(
                    "cap_bounded x amrap requires a set-level rounds observation work_target"
                )
        if self.timing.mode == "cap_bounded" and self.traversal != "amrap" and self.slots:
            has_duration = any(
                target.role == "observation" and target.metric == "duration"
                for target in self.work_target
            )
            if not has_duration:
                raise ValueError(
                    "cap_bounded x sequential/round_robin requires a set-level duration work_target"
                )
        return self

    def has_aggregate_observation(self) -> bool:
        return any(
            target.role == "observation" and target.metric in {"rounds", "duration"}
            for target in self.work_target
        )


class PrimitiveBlockIn(_UuidInputBase):
    model_config = ConfigDict(extra="forbid")

    id: str
    title: str | None = None
    repeat: int = Field(default=1, ge=1)
    work_target: list[PrimitiveWorkTargetIn] = Field(default_factory=list)
    sets: list[PrimitiveSetIn]

    @model_validator(mode="after")
    def _contains_executable_work(self) -> "PrimitiveBlockIn":
        if not any(set_.slots for set_ in self.sets):
            raise ValueError("primitive blocks require at least one slot-backed executable set")
        return self


class WorkoutCreate(_UuidInputBase):
    """Accepts a full primitive workout tree (blocks → sets → slots) in one request.

    user_id is resolved from the bearer token, not the body (ADR-2026-04-17).
    """

    model_config = ConfigDict(extra="forbid")

    id: str | None = None
    name: str
    scheduled_date: str | None = None
    status: Literal["planned", "active", "completed", "skipped"] = "planned"
    source: Literal["claude", "manual"] = "claude"
    notes: str | None = None
    tags_json: str | None = None
    primitive_blocks: list[PrimitiveBlockIn] = Field(min_length=1)


class WorkoutUpdate(_UuidInputBase):
    """Partial update. Blocks, if present, replace the full tree (simpler than diff)."""

    model_config = ConfigDict(extra="forbid")

    name: str | None = None
    scheduled_date: str | None = None
    status: Literal["planned", "active", "completed", "skipped"] | None = None
    notes: str | None = None
    tags_json: str | None = None
    completed_at: UtcDatetimeIn | None = None
    primitive_blocks: list[PrimitiveBlockIn] | None = Field(default=None, min_length=1)


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
    primitive_blocks: list[PrimitiveBlockIn] = Field(min_length=1)


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
    skipped: bool = False
    side: Literal["left", "right", "bilateral"] = "bilateral"
    started_at: UtcDatetimeIn | None = None
    completed_at: UtcDatetimeIn
    hr_avg_bpm: int | None = None
    hr_max_bpm: int | None = None
    cadence_avg_spm: int | None = None
    motion_samples_ref: str | None = None
    notes: str | None = None


class PrimitiveSetLogIn(_UuidInputBase):
    model_config = ConfigDict(
        extra="forbid",
        json_schema_extra={
            "description": (
                "Primitive result row. The role selects the coordinate grammar: "
                "slot rows identify block/set/slot and must include set_index "
                "as the slot ordinal within the authored set; set_result rows "
                "identify block/set, use set_index 0 as their aggregate "
                "sentinel, and cannot carry slot or exercise ids; block_result "
                "rows identify block, use set_index and set_repeat_index 0 as "
                "aggregate sentinels, and cannot carry set, slot, or exercise "
                "ids. Runtime validation also verifies the coordinates against "
                "the persisted primitive workout tree."
            ),
            "oneOf": [
                {
                    "required": ["slot_id", "set_id", "block_id", "set_index"],
                    "properties": {"role": {"const": "slot"}},
                },
                {
                    "required": ["role", "set_id", "block_id"],
                    "properties": {
                        "role": {"const": "set_result"},
                        "set_index": {"const": 0},
                    },
                    "not": {
                        "anyOf": [
                            {"required": ["slot_id"]},
                            {"required": ["planned_exercise_id"]},
                            {"required": ["performed_exercise_id"]},
                        ],
                    },
                },
                {
                    "required": ["role", "block_id"],
                    "properties": {
                        "role": {"const": "block_result"},
                        "set_index": {"const": 0},
                        "set_repeat_index": {"const": 0},
                    },
                    "not": {
                        "anyOf": [
                            {"required": ["slot_id"]},
                            {"required": ["set_id"]},
                            {"required": ["planned_exercise_id"]},
                            {"required": ["performed_exercise_id"]},
                        ],
                    },
                },
            ],
        },
    )

    id: str
    role: Literal["slot", "set_result", "block_result"] = "slot"
    slot_id: str | None = None
    set_id: str | None = None
    block_id: str | None = None
    workout_id: str
    planned_exercise_id: str | None = None
    performed_exercise_id: str | None = None
    set_index: int = Field(default=0, ge=0)
    set_repeat_index: int = Field(default=0, ge=0)
    block_repeat_index: int = Field(default=0, ge=0)
    reps: int | None = None
    weight: float | None = None
    weight_unit: Literal["kg", "lb"] | None = None
    duration_sec: float | None = None
    distance_m: float | None = None
    rounds: int | None = None
    rir: int | None = Field(default=None, ge=0, le=5)
    is_warmup: bool = False
    completed_at: UtcDatetimeIn

    @model_validator(mode="after")
    def _role_scope_is_valid(self) -> "PrimitiveSetLogIn":
        if self.workout_id is None:
            raise ValueError("primitive log rows require workout_id")
        if self.role == "slot":
            self._validate_slot_scope()
        elif self.role == "set_result":
            self._validate_set_result_scope()
        elif self.role == "block_result":
            self._validate_block_result_scope()
        return self

    def _validate_slot_scope(self) -> None:
        if "set_index" not in self.model_fields_set:
            raise ValueError("slot primitive log rows require set_index")
        if self.slot_id is None or self.set_id is None or self.block_id is None:
            raise ValueError("slot primitive log rows require slot_id, set_id, and block_id")

    def _validate_set_result_scope(self) -> None:
        if self.set_id is None or self.block_id is None or "slot_id" in self.model_fields_set:
            raise ValueError(
                "set_result rows require set_id and block_id and no slot or exercise ids"
            )
        if {"planned_exercise_id", "performed_exercise_id"} & self.model_fields_set:
            raise ValueError("set_result rows cannot carry exercise ids")

    def _validate_block_result_scope(self) -> None:
        if self.block_id is None or {"slot_id", "set_id"} & self.model_fields_set:
            raise ValueError(
                "block_result rows require block_id only and cannot carry set, slot, "
                "or exercise ids"
            )
        if {"planned_exercise_id", "performed_exercise_id"} & self.model_fields_set:
            raise ValueError("block_result rows cannot carry exercise ids")


class PrimitiveSetLogRead(_UuidReadBase):
    model_config = ConfigDict(from_attributes=True)

    id: str
    role: str
    slot_id: str | None
    set_id: str | None
    block_id: str | None
    workout_id: str
    planned_exercise_id: str | None
    performed_exercise_id: str | None
    set_index: int
    set_repeat_index: int
    block_repeat_index: int
    reps: int | None
    weight: float | None
    weight_unit: str | None
    duration_sec: float | None
    distance_m: float | None
    rounds: int | None
    rir: int | None
    is_warmup: bool
    completed_at: UtcDatetime


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
    skipped: bool
    side: str
    started_at: UtcDatetime | None
    completed_at: UtcDatetime
    hr_avg_bpm: int | None
    hr_max_bpm: int | None
    cadence_avg_spm: int | None
    motion_samples_ref: str | None
    notes: str | None


# ---------- User parameters (append-only) ----------


class UserParameterIn(_UuidInputBase):
    """user_id is resolved from the bearer token (ADR-2026-04-17).

    `id` is client-owned when the caller is the iOS app: the app derives
    a deterministic UUID from `(userID, key, updated_at)` so a replayed
    push (crash between commit and queue-remove) upserts on id instead
    of inserting a duplicate row. `user_parameters` is append-only on
    read, so a duplicate row would live forever. When `id` is omitted
    (Claude's bulk imports), the server falls back to generating a
    fresh UUID — Claude's pushes aren't retried client-side.
    """

    id: str | None = None
    key: str
    value: str
    source: Literal["claude", "app_log", "manual"] = "claude"
    # updated_at optional on create; server stamps now if omitted.
    updated_at: UtcDatetimeIn | None = None


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
    """App tells server 'this workout transitioned to status X at time Y.'

    `notes` is optional: the app carries the user's post-workout note as
    part of the terminal status push so the server is authoritative for
    the value. Without this, the local cache held the note but the next
    `sync/pull` overwrote it with the server's stale value (bug: post-
    completion notes disappeared on next pull). Sending `None` leaves
    the existing server-side `notes` untouched — only a non-None value
    updates the row.
    """

    workout_id: str
    status: Literal["active", "completed", "skipped"]
    completed_at: UtcDatetimeIn | None = None
    notes: str | None = None


class WorkoutReset(_UuidInputBase):
    """App tells server to erase same-day execution data for a workout.

    This is the inverse of a completed-workout push: delete the primitive_set_logs
    tied to the workout tree and put the workout back into `planned` so a subsequent
    pull does not resurrect a locally reset History row.
    """

    workout_id: str


class SyncResultsIn(_UuidInputBase):
    """App pushes this when a workout finishes (or on next connectivity)."""

    model_config = ConfigDict(extra="forbid")

    primitive_set_logs: list[PrimitiveSetLogIn] = Field(default_factory=list)
    status_updates: list[WorkoutStatusUpdate] = Field(default_factory=list)
    workout_resets: list[WorkoutReset] = Field(default_factory=list)


class SyncResultsOut(_UuidReadBase):
    primitive_set_logs_received: int
    status_updates_received: int
    workout_resets_received: int


class ExerciseLastPerformed(_UuidReadBase):
    """Inline history the app uses to show 'last time you did this exercise.'"""

    exercise_id: str
    last_set_logs: list[PrimitiveSetLogRead]


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
    timestamp: UtcDatetimeIn
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
