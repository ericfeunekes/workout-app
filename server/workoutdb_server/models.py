"""SQLAlchemy ORM models. Mirrors the SwiftData schema in app/.

Data layer — may depend on config; must not depend on api or sync.

Keeps the JSON-blob fields (`timing_config_json`, `prescription_json`,
`tags_json`, `rounds_rep_scheme_json`, `parameter_overrides_json`,
`motion_samples_ref`) as plain strings at this layer. The API/Pydantic layer
is responsible for validating shape against the spec's documented structures.
"""

from __future__ import annotations

import json
import uuid
from datetime import UTC, datetime
from typing import TYPE_CHECKING

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    text,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship

if TYPE_CHECKING:
    pass


class Base(DeclarativeBase):
    pass


def new_uuid() -> str:
    return str(uuid.uuid4())


def _utcnow() -> datetime:
    """Timezone-aware UTC now. Stored as naive ISO string by SQLAlchemy's DateTime on SQLite."""
    return datetime.now(UTC)


# ---------- Users ----------


class AppUser(Base):
    __tablename__ = "app_user"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=new_uuid)
    name: Mapped[str] = mapped_column(String, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=_utcnow)

    workouts: Mapped[list[Workout]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    user_parameters: Mapped[list[UserParameter]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )


# ---------- Exercises (Claude-owned IDs; no canonicalization on name) ----------


class Exercise(Base):
    __tablename__ = "exercise"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    name: Mapped[str] = mapped_column(String, nullable=False)
    notes: Mapped[str | None] = mapped_column(String)
    demo_url: Mapped[str | None] = mapped_column(String)
    # Library-level defaults merged into each workout_item's prescription on
    # ingest. See docs/decisions/ADR-2026-04-18-smart-defaults.md.
    default_prescription_json: Mapped[str | None] = mapped_column(String)
    default_alternatives_json: Mapped[str | None] = mapped_column(String)


# ---------- Workouts → Blocks → Items → Set Logs ----------


class Workout(Base):
    __tablename__ = "workout"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(
        String, ForeignKey("app_user.id", ondelete="CASCADE"), nullable=False
    )
    name: Mapped[str] = mapped_column(String, nullable=False)
    scheduled_date: Mapped[str | None] = mapped_column(String)  # date-only, ISO "YYYY-MM-DD"
    status: Mapped[str] = mapped_column(String, nullable=False)
    source: Mapped[str] = mapped_column(String, nullable=False)
    notes: Mapped[str | None] = mapped_column(String)
    tags_json: Mapped[str | None] = mapped_column(String)
    primitive_blocks_json: Mapped[str] = mapped_column(String, nullable=False, default="[]")
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=_utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, default=_utcnow, onupdate=_utcnow
    )
    completed_at: Mapped[datetime | None] = mapped_column(DateTime)

    user: Mapped[AppUser] = relationship(back_populates="workouts")
    blocks: Mapped[list[Block]] = relationship(
        back_populates="workout",
        cascade="all, delete-orphan",
        order_by="Block.position",
    )

    @property
    def primitive_blocks(self) -> list[dict]:
        return json.loads(self.primitive_blocks_json or "[]")

    __table_args__ = (
        CheckConstraint(
            "status IN ('planned', 'active', 'completed', 'skipped')",
            name="workout_status_check",
        ),
        CheckConstraint("source IN ('claude', 'manual')", name="workout_source_check"),
        Index("idx_workout_user_scheduled", "user_id", "scheduled_date"),
        Index("idx_workout_user_status", "user_id", "status"),
        Index("idx_workout_user_completed", "user_id", "completed_at"),
        Index("idx_workout_user_updated", "user_id", "updated_at"),
    )


class Block(Base):
    __tablename__ = "block"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=new_uuid)
    workout_id: Mapped[str] = mapped_column(
        String, ForeignKey("workout.id", ondelete="CASCADE"), nullable=False
    )
    parent_block_id: Mapped[str | None] = mapped_column(
        String, ForeignKey("block.id", ondelete="CASCADE")
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    name: Mapped[str | None] = mapped_column(String)
    timing_mode: Mapped[str] = mapped_column(String, nullable=False)
    timing_config_json: Mapped[str] = mapped_column(String, nullable=False)
    rounds: Mapped[int | None] = mapped_column(Integer)
    rounds_rep_scheme_json: Mapped[str | None] = mapped_column(String)
    notes: Mapped[str | None] = mapped_column(String)
    intent: Mapped[str | None] = mapped_column(String)

    workout: Mapped[Workout] = relationship(back_populates="blocks")
    parent: Mapped[Block | None] = relationship(back_populates="children", remote_side="Block.id")
    children: Mapped[list[Block]] = relationship(
        back_populates="parent", cascade="all, delete-orphan"
    )
    workout_items: Mapped[list[WorkoutItem]] = relationship(
        back_populates="block",
        cascade="all, delete-orphan",
        order_by="WorkoutItem.position",
    )

    __table_args__ = (
        CheckConstraint(
            "timing_mode IN ('straight_sets', 'superset', 'circuit', 'emom', 'amrap', "
            "'for_time', 'intervals', 'tabata', 'continuous', 'accumulate', 'custom', 'rest')",
            name="block_timing_mode_check",
        ),
        Index("idx_block_workout", "workout_id"),
        Index("idx_block_parent", "parent_block_id"),
    )


class WorkoutItem(Base):
    __tablename__ = "workout_item"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=new_uuid)
    block_id: Mapped[str] = mapped_column(
        String, ForeignKey("block.id", ondelete="CASCADE"), nullable=False
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    exercise_id: Mapped[str] = mapped_column(String, ForeignKey("exercise.id"), nullable=False)
    # Always the *resolved* form (library defaults merged in). Immutable once
    # stored — library mutations don't retro-edit historical workouts.
    prescription_json: Mapped[str] = mapped_column(String, nullable=False)
    # The client's original sparse payload. Null when the client sent a fully-
    # resolved prescription (i.e. the merge was a no-op).
    prescription_json_raw: Mapped[str | None] = mapped_column(String)

    block: Mapped[Block] = relationship(back_populates="workout_items")
    exercise: Mapped[Exercise] = relationship()
    alternatives: Mapped[list[ExerciseAlternative]] = relationship(
        back_populates="workout_item", cascade="all, delete-orphan"
    )
    set_logs: Mapped[list[SetLog]] = relationship(
        back_populates="workout_item",
        cascade="all, delete-orphan",
        order_by="SetLog.set_index",
    )

    __table_args__ = (
        Index("idx_workout_item_block", "block_id"),
        Index("idx_workout_item_exercise", "exercise_id"),
    )


class ExerciseAlternative(Base):
    __tablename__ = "exercise_alternative"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=new_uuid)
    workout_item_id: Mapped[str] = mapped_column(
        String, ForeignKey("workout_item.id", ondelete="CASCADE"), nullable=False
    )
    exercise_id: Mapped[str] = mapped_column(String, ForeignKey("exercise.id"), nullable=False)
    reason: Mapped[str] = mapped_column(String, nullable=False)
    parameter_overrides_json: Mapped[str | None] = mapped_column(String)

    workout_item: Mapped[WorkoutItem] = relationship(back_populates="alternatives")
    exercise: Mapped[Exercise] = relationship()

    __table_args__ = (Index("idx_exercise_alt_item", "workout_item_id"),)


class SetLog(Base):
    __tablename__ = "set_log"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=new_uuid)
    workout_item_id: Mapped[str] = mapped_column(
        String, ForeignKey("workout_item.id", ondelete="CASCADE"), nullable=False
    )
    performed_exercise_id: Mapped[str | None] = mapped_column(
        String, ForeignKey("exercise.id"), nullable=True
    )
    set_index: Mapped[int] = mapped_column(Integer, nullable=False)
    reps: Mapped[int | None] = mapped_column(Integer)
    weight: Mapped[float | None] = mapped_column(Float)
    weight_unit: Mapped[str | None] = mapped_column(String)
    duration_sec: Mapped[float | None] = mapped_column(Float)
    distance_m: Mapped[float | None] = mapped_column(Float)
    rir: Mapped[int | None] = mapped_column(Integer)
    is_warmup: Mapped[bool] = mapped_column(Integer, nullable=False, default=0)
    skipped: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    side: Mapped[str] = mapped_column(String, nullable=False, default="bilateral")
    started_at: Mapped[datetime | None] = mapped_column(DateTime)
    completed_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    hr_avg_bpm: Mapped[int | None] = mapped_column(Integer)
    hr_max_bpm: Mapped[int | None] = mapped_column(Integer)
    cadence_avg_spm: Mapped[int | None] = mapped_column(Integer)
    motion_samples_ref: Mapped[str | None] = mapped_column(String)
    notes: Mapped[str | None] = mapped_column(String)

    workout_item: Mapped[WorkoutItem] = relationship(back_populates="set_logs")

    __table_args__ = (
        CheckConstraint("weight_unit IN ('kg', 'lb') OR weight_unit IS NULL"),
        CheckConstraint("is_warmup IN (0, 1)"),
        CheckConstraint("skipped IN (0, 1)"),
        CheckConstraint("side IN ('left', 'right', 'bilateral')", name="set_log_side_check"),
        CheckConstraint("rir IS NULL OR (rir >= 0 AND rir <= 5)"),
        Index("idx_set_log_item", "workout_item_id"),
        Index(
            "idx_set_log_performed_exercise",
            "performed_exercise_id",
            sqlite_where=text("performed_exercise_id IS NOT NULL"),
        ),
    )


class PrimitiveSetLog(Base):
    __tablename__ = "primitive_set_log"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    role: Mapped[str] = mapped_column(String, nullable=False)
    slot_id: Mapped[str | None] = mapped_column(String)
    set_id: Mapped[str | None] = mapped_column(String)
    block_id: Mapped[str | None] = mapped_column(String)
    workout_id: Mapped[str] = mapped_column(
        String, ForeignKey("workout.id", ondelete="CASCADE"), nullable=False
    )
    planned_exercise_id: Mapped[str | None] = mapped_column(String, ForeignKey("exercise.id"))
    performed_exercise_id: Mapped[str | None] = mapped_column(String, ForeignKey("exercise.id"))
    set_index: Mapped[int] = mapped_column(Integer, nullable=False)
    set_repeat_index: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    block_repeat_index: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    reps: Mapped[int | None] = mapped_column(Integer)
    weight: Mapped[float | None] = mapped_column(Float)
    weight_unit: Mapped[str | None] = mapped_column(String)
    duration_sec: Mapped[float | None] = mapped_column(Float)
    distance_m: Mapped[float | None] = mapped_column(Float)
    rounds: Mapped[int | None] = mapped_column(Integer)
    rir: Mapped[int | None] = mapped_column(Integer)
    is_warmup: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    completed_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)

    __table_args__ = (
        CheckConstraint("role IN ('slot', 'set_result', 'block_result')"),
        CheckConstraint("weight_unit IN ('kg', 'lb') OR weight_unit IS NULL"),
        CheckConstraint("rir IS NULL OR (rir >= 0 AND rir <= 5)"),
        Index("idx_primitive_set_log_workout", "workout_id"),
        Index("idx_primitive_set_log_set", "set_id"),
        Index("idx_primitive_set_log_slot", "slot_id"),
    )


# ---------- User parameters (append-only log) ----------


class UserParameter(Base):
    """Append-only log. Latest value for a key is MAX(updated_at) WHERE user_id=? AND key=?.

    Multiple rows per (user_id, key) over time is the intended design — it preserves history
    for trend analysis. Do NOT add a unique constraint on (user_id, key).
    """

    __tablename__ = "user_parameters"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(
        String, ForeignKey("app_user.id", ondelete="CASCADE"), nullable=False
    )
    key: Mapped[str] = mapped_column(String, nullable=False)
    value: Mapped[str] = mapped_column(String, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=_utcnow)
    source: Mapped[str] = mapped_column(String, nullable=False)

    user: Mapped[AppUser] = relationship(back_populates="user_parameters")

    __table_args__ = (
        CheckConstraint(
            "source IN ('claude', 'app_log', 'manual')", name="user_param_source_check"
        ),
        Index("idx_user_param_latest", "user_id", "key", "updated_at"),
    )


# ---------- Telemetry event log ----------


class EventLog(Base):
    """Durable trail of app-side events. Permissive by design.

    `data_json` is a freeform string — the server never cracks it, so new
    event shapes don't require migrations. `workout_id` / `set_log_id` are
    nullable pointers for convenient filtering; intentionally NOT FKs because
    the app may emit events against IDs that haven't synced yet.

    `ts` is the device-side timestamp (when the event happened). `received_at`
    is the server-side insert time — the gap tells us how long the device
    was offline.
    """

    __tablename__ = "event_log"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    user_id: Mapped[str] = mapped_column(
        String, ForeignKey("app_user.id", ondelete="CASCADE"), nullable=False
    )
    ts: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    session_id: Mapped[str] = mapped_column(String, nullable=False)
    kind: Mapped[str] = mapped_column(String, nullable=False)
    name: Mapped[str] = mapped_column(String, nullable=False)
    data_json: Mapped[str | None] = mapped_column(String)
    workout_id: Mapped[str | None] = mapped_column(String)
    set_log_id: Mapped[str | None] = mapped_column(String)
    received_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=_utcnow)

    __table_args__ = (Index("idx_event_log_user_ts", "user_id", "ts"),)
