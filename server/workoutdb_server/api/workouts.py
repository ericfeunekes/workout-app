"""Workouts endpoints. Accepts/returns the full nested tree (blocks → items → alternatives)."""

import json
import uuid

from fastapi import APIRouter, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from workoutdb_server.api.deps import Auth, DbSession
from workoutdb_server.api.schemas import (
    BlockIn,
    ExerciseAlternativeIn,
    WorkoutCreate,
    WorkoutItemIn,
    WorkoutRead,
    WorkoutUpdate,
)
from workoutdb_server.models import (
    AppUser,
    Block,
    ExerciseAlternative,
    Workout,
    WorkoutItem,
)

router = APIRouter(prefix="/api/workouts", tags=["workouts"])


def workout_tree_loader():
    """Eager-load blocks → items → alternatives in one go to avoid lazy-load N+1.

    Importable by other routers (sync) that return workout trees.
    """
    return (
        selectinload(Workout.blocks)
        .selectinload(Block.workout_items)
        .selectinload(WorkoutItem.alternatives)
    )


def _new_id() -> str:
    return str(uuid.uuid4())


def _build_workout_tree(payload: WorkoutCreate) -> Workout:
    workout = Workout(
        id=payload.id or _new_id(),
        user_id=payload.user_id,
        name=payload.name,
        scheduled_date=payload.scheduled_date,
        status=payload.status,
        source=payload.source,
        notes=payload.notes,
        tags_json=payload.tags_json,
    )
    workout.blocks = [_build_block(b) for b in payload.blocks]
    return workout


def _build_block(payload: BlockIn) -> Block:
    block = Block(
        id=payload.id or _new_id(),
        parent_block_id=payload.parent_block_id,
        position=payload.position,
        name=payload.name,
        timing_mode=payload.timing_mode,
        timing_config_json=payload.timing_config_json,
        rounds=payload.rounds,
        rounds_rep_scheme_json=payload.rounds_rep_scheme_json,
        notes=payload.notes,
    )
    block.workout_items = [_build_item(i) for i in payload.workout_items]
    return block


def _build_item(payload: WorkoutItemIn) -> WorkoutItem:
    item = WorkoutItem(
        id=payload.id or _new_id(),
        position=payload.position,
        exercise_id=payload.exercise_id,
        prescription_json=payload.prescription_json,
    )
    item.alternatives = [_build_alt(a) for a in payload.alternatives]
    return item


def _build_alt(payload: ExerciseAlternativeIn) -> ExerciseAlternative:
    return ExerciseAlternative(
        id=payload.id or _new_id(),
        exercise_id=payload.exercise_id,
        reason=payload.reason,
        parameter_overrides_json=payload.parameter_overrides_json,
    )


@router.post("", response_model=WorkoutRead, dependencies=[Auth])
def create_workout(payload: WorkoutCreate, db: DbSession) -> Workout:
    if db.get(AppUser, payload.user_id) is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"user_id {payload.user_id!r} does not exist",
        )
    workout = _build_workout_tree(payload)
    db.add(workout)
    db.commit()
    db.refresh(workout)
    return workout


@router.put("/{workout_id}", response_model=WorkoutRead, dependencies=[Auth])
def update_workout(workout_id: str, payload: WorkoutUpdate, db: DbSession) -> Workout:
    workout = db.get(Workout, workout_id)
    if workout is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)

    for field in ("name", "scheduled_date", "status", "notes", "tags_json", "completed_at"):
        value = getattr(payload, field)
        if value is not None:
            setattr(workout, field, value)

    # Blocks, if provided, replace the full tree. Simpler than diffing.
    if payload.blocks is not None:
        workout.blocks = [_build_block(b) for b in payload.blocks]

    db.commit()
    db.refresh(workout)
    return workout


@router.get("", response_model=list[WorkoutRead], dependencies=[Auth])
def list_workouts(
    db: DbSession,
    user_id: str = Query(..., description="Required — scopes the query to one user."),
    status_filter: str | None = Query(None, alias="status"),
    after: str | None = Query(None, description="scheduled_date >= this (YYYY-MM-DD)."),
    tag: str | None = Query(None, description="Matches when tags_json contains this tag."),
    limit: int = Query(100, ge=1, le=500, description="Max rows to return."),
    offset: int = Query(0, ge=0, description="Rows to skip for pagination."),
) -> list[Workout]:
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
        return rows[offset : offset + limit]

    stmt = stmt.offset(offset).limit(limit)
    return list(db.execute(stmt).scalars().all())


@router.get("/{workout_id}", response_model=WorkoutRead, dependencies=[Auth])
def get_workout(workout_id: str, db: DbSession) -> Workout:
    stmt = select(Workout).options(workout_tree_loader()).where(Workout.id == workout_id)
    workout = db.execute(stmt).scalar_one_or_none()
    if workout is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)
    return workout


def _tags_contains(tags_json: str | None, tag: str) -> bool:
    if not tags_json:
        return False
    try:
        tags = json.loads(tags_json)
    except (json.JSONDecodeError, TypeError):
        return False
    return isinstance(tags, list) and tag in tags
