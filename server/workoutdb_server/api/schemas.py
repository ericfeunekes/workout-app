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

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

# ---------- Users ----------


class AppUserRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    created_at: datetime


# ---------- Exercises ----------


class ExerciseUpsert(BaseModel):
    """Claude owns the id. Upsert-by-id: same id updates, new id inserts."""

    id: str
    name: str
    notes: str | None = None
    demo_url: str | None = None


class ExerciseRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    notes: str | None
    demo_url: str | None


# ---------- Workout tree (nested create/read) ----------


class ExerciseAlternativeIn(BaseModel):
    id: str | None = None
    exercise_id: str
    reason: str
    parameter_overrides_json: str | None = None


class ExerciseAlternativeRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    exercise_id: str
    reason: str
    parameter_overrides_json: str | None


class WorkoutItemIn(BaseModel):
    id: str | None = None
    position: int
    exercise_id: str
    prescription_json: str
    alternatives: list[ExerciseAlternativeIn] = Field(default_factory=list)


class WorkoutItemRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    position: int
    exercise_id: str
    prescription_json: str
    alternatives: list[ExerciseAlternativeRead]


class BlockIn(BaseModel):
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


class BlockRead(BaseModel):
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


class WorkoutCreate(BaseModel):
    """Accepts a full workout tree (blocks → items → alternatives) in one request."""

    id: str | None = None
    user_id: str
    name: str
    scheduled_date: str | None = None
    status: Literal["planned", "active", "completed", "skipped"] = "planned"
    source: Literal["claude", "manual"] = "claude"
    notes: str | None = None
    tags_json: str | None = None
    blocks: list[BlockIn] = Field(default_factory=list)


class WorkoutUpdate(BaseModel):
    """Partial update. Blocks, if present, replace the full tree (simpler than diff)."""

    name: str | None = None
    scheduled_date: str | None = None
    status: Literal["planned", "active", "completed", "skipped"] | None = None
    notes: str | None = None
    tags_json: str | None = None
    completed_at: datetime | None = None
    blocks: list[BlockIn] | None = None


class WorkoutRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    user_id: str
    name: str
    scheduled_date: str | None
    status: str
    source: str
    notes: str | None
    tags_json: str | None
    created_at: datetime
    completed_at: datetime | None
    blocks: list[BlockRead]


# ---------- Set logs (app pushes these back) ----------


class SetLogIn(BaseModel):
    id: str | None = None
    workout_item_id: str
    set_index: int
    reps: int | None = None
    weight: float | None = None
    weight_unit: Literal["kg", "lb"] | None = None
    duration_sec: float | None = None
    distance_m: float | None = None
    rpe: float | None = None
    is_warmup: bool = False
    started_at: datetime | None = None
    completed_at: datetime
    hr_avg_bpm: int | None = None
    hr_max_bpm: int | None = None
    cadence_avg_spm: int | None = None
    motion_samples_ref: str | None = None
    notes: str | None = None


class SetLogRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    workout_item_id: str
    set_index: int
    reps: int | None
    weight: float | None
    weight_unit: str | None
    duration_sec: float | None
    distance_m: float | None
    rpe: float | None
    is_warmup: bool
    started_at: datetime | None
    completed_at: datetime
    hr_avg_bpm: int | None
    hr_max_bpm: int | None
    cadence_avg_spm: int | None
    motion_samples_ref: str | None
    notes: str | None


# ---------- User parameters (append-only) ----------


class UserParameterIn(BaseModel):
    user_id: str
    key: str
    value: str
    source: Literal["claude", "app_log", "manual"] = "claude"
    # updated_at optional on create; server stamps now if omitted.
    updated_at: datetime | None = None


class UserParameterRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    user_id: str
    key: str
    value: str
    updated_at: datetime
    source: str


# ---------- Sync ----------


class WorkoutStatusUpdate(BaseModel):
    """App tells server 'this workout transitioned to status X at time Y.'"""

    workout_id: str
    status: Literal["active", "completed", "skipped"]
    completed_at: datetime | None = None


class SyncResultsIn(BaseModel):
    """App pushes this when a workout finishes (or on next connectivity)."""

    set_logs: list[SetLogIn] = Field(default_factory=list)
    status_updates: list[WorkoutStatusUpdate] = Field(default_factory=list)


class ExerciseLastPerformed(BaseModel):
    """Inline history the app uses to show 'last time you did this exercise.'"""

    exercise_id: str
    last_set_logs: list[SetLogRead]
    prescription_json: str | None = None


class SyncPullOut(BaseModel):
    workouts: list[WorkoutRead]
    exercises: list[ExerciseRead]
    user_parameters: list[UserParameterRead]
    last_performed: list[ExerciseLastPerformed]
    server_time: datetime


# ---------- Version handshake ----------


class VersionInfo(BaseModel):
    schema_version: str | None
    applied_migrations: list[str]
    server_version: str
