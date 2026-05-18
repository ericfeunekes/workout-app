"""Workouts endpoints. Accepts/returns the full nested tree (blocks → items → alternatives)."""

import json
import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, HTTPException, Query, status
from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from workoutdb_server.api.deps import CurrentUserId, DbSession
from workoutdb_server.api.schemas import (
    PrimitiveBlockIn,
    WorkoutCreate,
    WorkoutRead,
    WorkoutUpdate,
)
from workoutdb_server.models import (
    Exercise,
    Workout,
)

router = APIRouter(prefix="/api/workouts", tags=["workouts"])


def workout_tree_loader():
    """Compatibility no-op for callers that still request a loader option."""
    return selectinload(Workout.blocks)


def read_workout_or_500(workout: Workout) -> WorkoutRead:
    """Validate persisted primitive workouts before returning them on the wire."""
    try:
        return WorkoutRead.model_validate(workout)
    except (TypeError, ValueError, ValidationError) as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Persisted primitive workout {workout.id} is invalid",
        ) from exc


def _new_id() -> str:
    return str(uuid.uuid4())


def _build_workout_tree(payload: WorkoutCreate, user_id: str, db: Session) -> Workout:
    _validate_primitive_exercises_exist(db, payload.primitive_blocks)
    workout = Workout(
        id=payload.id or _new_id(),
        user_id=user_id,
        name=payload.name,
        scheduled_date=payload.scheduled_date,
        status=payload.status,
        source=payload.source,
        notes=payload.notes,
        tags_json=payload.tags_json,
        primitive_blocks_json=_primitive_blocks_to_json(payload.primitive_blocks),
    )
    return workout


@router.post("", response_model=WorkoutRead)
def create_workout(payload: WorkoutCreate, db: DbSession, user_id: CurrentUserId) -> Workout:
    """Create a workout, or upsert-in-place if the caller supplied an `id` that
    already exists for this user.

    bug-041: prior to this change, a POST with an `id` that matched an existing
    row returned 500 (PK constraint violation). Seed scripts and any client
    that replays a POST with stable IDs hit that path. Single-user-cutover
    philosophy says "same id = upsert, not crash" — so we route an existing-id
    POST through the same tree-replace logic PUT uses. New-id POSTs take the
    plain insert path.
    """
    if payload.id is not None:
        existing = db.get(Workout, payload.id)
        if existing is not None:
            if existing.user_id != user_id:
                # Another user owns that id — respond as if it doesn't exist
                # (tenant isolation, same posture as GET / PUT).
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)
            _apply_workout_update(
                existing,
                name=payload.name,
                scheduled_date=payload.scheduled_date,
                status_=payload.status,
                notes=payload.notes,
                tags_json=payload.tags_json,
                completed_at=None,
                db=db,
                primitive_blocks_payload=payload.primitive_blocks,
            )
            db.commit()
            db.refresh(existing)
            return existing

    workout = _build_workout_tree(payload, user_id, db)
    db.add(workout)
    db.commit()
    db.refresh(workout)
    return workout


@router.put("/{workout_id}", response_model=WorkoutRead)
def update_workout(
    workout_id: str, payload: WorkoutUpdate, db: DbSession, user_id: CurrentUserId
) -> Workout:
    workout = db.get(Workout, workout_id)
    if workout is None or workout.user_id != user_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)

    _apply_workout_update(
        workout,
        name=payload.name,
        scheduled_date=payload.scheduled_date,
        status_=payload.status,
        notes=payload.notes,
        tags_json=payload.tags_json,
        completed_at=payload.completed_at,
        db=db,
        primitive_blocks_payload=payload.primitive_blocks,
    )

    db.commit()
    db.refresh(workout)
    return workout


def _apply_workout_update(
    workout: Workout,
    *,
    name: str | None,
    scheduled_date: str | None,
    status_: str | None,
    notes: str | None,
    tags_json: str | None,
    completed_at: datetime | None,
    db: Session,
    primitive_blocks_payload: list[PrimitiveBlockIn] | None = None,
) -> None:
    """Apply a partial update to an existing Workout. Shared by PUT and the
    upsert path in POST (bug-041).

    Scalar fields with value `None` are treated as "no change" (PUT semantics);
    callers wanting to blank a field must pass the empty string / equivalent.
    `blocks_payload is None` means "don't touch the tree". When it IS provided,
    the full blocks tree is replaced.

    Block-replace implementation note: `workout.blocks = [...]` on a relationship
    with `cascade="all, delete-orphan"` relies on SQLAlchemy's flush ordering to
    orphan-delete the old children before inserting the new ones. When new
    children carry the SAME primary keys as the old ones (common on re-seed),
    the flush order can leave some old rows stranded — a PUT returns 200 but a
    subsequent GET shows `blocks: []` for a fraction of workouts. Fix: clear
    the relationship, `db.flush()` to force orphan-cleanup to run, then assign
    the fresh list. bug-041 second half.
    """
    if name is not None:
        workout.name = name
    if scheduled_date is not None:
        workout.scheduled_date = scheduled_date
    if status_ is not None:
        workout.status = status_
    if notes is not None:
        workout.notes = notes
    if tags_json is not None:
        workout.tags_json = tags_json
    if completed_at is not None:
        workout.completed_at = completed_at

    if primitive_blocks_payload is not None:
        _validate_primitive_exercises_exist(db, primitive_blocks_payload)
        workout.blocks = []
        db.flush()
        workout.primitive_blocks_json = _primitive_blocks_to_json(primitive_blocks_payload)

    # Force updated_at to bump even when only nested blocks changed — SQLAlchemy's
    # onupdate fires on column changes, not relationship replacements.
    workout.updated_at = datetime.now(UTC)


def _primitive_blocks_to_json(blocks: list[PrimitiveBlockIn]) -> str:
    return json.dumps(
        [_primitive_dump(block.model_dump(mode="json", exclude_none=True)) for block in blocks],
        separators=(",", ":"),
    )


def _validate_primitive_exercises_exist(db: Session, blocks: list[PrimitiveBlockIn]) -> None:
    exercise_ids = {
        slot.exercise_id
        for block in blocks
        for primitive_set in block.sets
        for slot in primitive_set.slots
    }
    if not exercise_ids:
        return
    rows = db.execute(select(Exercise.id).where(Exercise.id.in_(exercise_ids))).scalars().all()
    missing = sorted(exercise_ids - set(rows))
    if missing:
        raise HTTPException(
            status_code=422,
            detail=f"primitive slot exercise_id not found: {', '.join(missing)}",
        )


def _primitive_dump(value):
    if isinstance(value, list):
        return [_primitive_dump(item) for item in value]
    if not isinstance(value, dict):
        return value
    dumped = {key: _primitive_dump(item) for key, item in value.items()}
    if (
        dumped.get("unit") == "bodyweight"
        and dumped.get("unit_type") == "implicit_bodyweight"
        and "value" not in dumped
    ):
        dumped["value"] = None
    return dumped


@router.get("", response_model=list[WorkoutRead])
def list_workouts(
    db: DbSession,
    user_id: CurrentUserId,
    status_filter: str | None = Query(None, alias="status"),
    after: str | None = Query(None, description="scheduled_date >= this (YYYY-MM-DD)."),
    tag: str | None = Query(None, description="Matches when tags_json contains this tag."),
    limit: int = Query(100, ge=1, le=500, description="Max rows to return."),
    offset: int = Query(0, ge=0, description="Rows to skip for pagination."),
) -> list[WorkoutRead]:
    stmt = select(Workout).options(workout_tree_loader()).where(Workout.user_id == user_id)
    if status_filter is not None:
        stmt = stmt.where(Workout.status == status_filter)
    if after is not None:
        stmt = stmt.where(Workout.scheduled_date >= after)
    stmt = stmt.order_by(Workout.scheduled_date, Workout.created_at)

    # Tag filter is a post-filter over the JSON blob, so pagination is applied after it.
    # For the expected volume this is fine; revisit if workout counts explode.
    if tag is not None:
        rows = list(db.execute(stmt).scalars().all())
        rows = [w for w in rows if _tags_contains(w.tags_json, tag)]
        return [read_workout_or_500(workout) for workout in rows[offset : offset + limit]]

    stmt = stmt.offset(offset).limit(limit)
    return [read_workout_or_500(workout) for workout in db.execute(stmt).scalars().all()]


@router.get("/{workout_id}", response_model=WorkoutRead)
def get_workout(workout_id: str, db: DbSession, user_id: CurrentUserId) -> WorkoutRead:
    stmt = (
        select(Workout)
        .options(workout_tree_loader())
        .where(Workout.id == workout_id, Workout.user_id == user_id)
    )
    workout = db.execute(stmt).scalar_one_or_none()
    if workout is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)
    return read_workout_or_500(workout)


def _tags_contains(tags_json: str | None, tag: str) -> bool:
    if not tags_json:
        return False
    try:
        tags = json.loads(tags_json)
    except (json.JSONDecodeError, TypeError):
        return False
    return isinstance(tags, list) and tag in tags
