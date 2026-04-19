"""Workouts endpoints. Accepts/returns the full nested tree (blocks → items → alternatives)."""

import json
import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from workoutdb_server.api.deps import CurrentUserId, DbSession
from workoutdb_server.api.schemas import (
    BlockIn,
    ExerciseAlternativeIn,
    WorkoutCreate,
    WorkoutItemIn,
    WorkoutRead,
    WorkoutUpdate,
)
from workoutdb_server.models import (
    Block,
    Exercise,
    ExerciseAlternative,
    Workout,
    WorkoutItem,
)
from workoutdb_server.sync.prescription_merge import (
    canonicalize,
    merge_alternatives,
    merge_prescriptions,
)
from workoutdb_server.sync.prescription_validate import validate_resolved_prescription

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


def _build_workout_tree(payload: WorkoutCreate, user_id: str, db: Session) -> Workout:
    workout = Workout(
        id=payload.id or _new_id(),
        user_id=user_id,
        name=payload.name,
        scheduled_date=payload.scheduled_date,
        status=payload.status,
        source=payload.source,
        notes=payload.notes,
        tags_json=payload.tags_json,
    )
    workout.blocks = [_build_block(b, db) for b in payload.blocks]
    return workout


def _build_block(payload: BlockIn, db: Session) -> Block:
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
    block.workout_items = [
        _build_item(i, db, block_position=payload.position) for i in payload.workout_items
    ]
    return block


def _build_item(
    payload: WorkoutItemIn, db: Session, *, block_position: int
) -> WorkoutItem:
    """Resolve library defaults into the workout_item's stored prescription.

    Looks up the referenced exercise's default_prescription_json / default_
    alternatives_json, merges them with what the client sent, and stores the
    resolved form. The original sparse payload is preserved in
    prescription_json_raw when the merge changed something; otherwise the raw
    column is null (saves bytes + makes re-pushes visibly idempotent).

    bug-036: prevalidate that `exercise_id` resolves to a real exercise row.
    Without this check, a missing / unknown exercise_id falls through to the
    FK constraint on `workout_items.exercise_id` at commit time and bubbles
    a generic 500. Fail fast here with a specific 422 so the client can
    react.
    """
    exercise = db.get(Exercise, payload.exercise_id)
    if exercise is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=f"exercise_id {payload.exercise_id} not found",
        )
    default_prescription = exercise.default_prescription_json
    default_alternatives = exercise.default_alternatives_json

    resolved_prescription = merge_prescriptions(default_prescription, payload.prescription_json)

    # qa-017: enforce the v1-shipped subset of autoreg after the merge — catches
    # both client-authored violations and library-default-induced ones in one
    # place. Runs before any DB writes so a 422 leaves no partial rows behind.
    validate_resolved_prescription(
        resolved_prescription,
        item_position=payload.position,
        block_position=block_position,
    )

    raw_canonical = canonicalize(payload.prescription_json)
    prescription_raw = payload.prescription_json if resolved_prescription != raw_canonical else None

    item_alts_dicts = [_alt_to_dict(a) for a in payload.alternatives]
    resolved_alts_dicts = merge_alternatives(default_alternatives, item_alts_dicts)

    # bug-R2.3 follow-up: prevalidate each resolved alternative's exercise_id
    # against the Exercise table. Without this check, an unknown exercise_id
    # (from either the client payload or a stale library default) falls
    # through to the FK on `exercise_alternative.exercise_id` at commit time
    # and bubbles a generic 500. Run BEFORE any DB writes so the 422 path
    # leaves no partial rows behind.
    for alt in resolved_alts_dicts:
        alt_ex = db.get(Exercise, alt["exercise_id"])
        if alt_ex is None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail=f"alternative exercise_id {alt['exercise_id']} not found",
            )

    item = WorkoutItem(
        id=payload.id or _new_id(),
        position=payload.position,
        exercise_id=payload.exercise_id,
        prescription_json=resolved_prescription,
        prescription_json_raw=prescription_raw,
    )
    item.alternatives = [_alt_from_dict(a) for a in resolved_alts_dicts]
    return item


def _alt_to_dict(payload: ExerciseAlternativeIn) -> dict:
    """Serialize an incoming alternative payload to the dict shape merge_alternatives expects."""
    return {
        "id": payload.id,
        "exercise_id": payload.exercise_id,
        "reason": payload.reason,
        "parameter_overrides_json": payload.parameter_overrides_json,
    }


def _alt_from_dict(data: dict) -> ExerciseAlternative:
    """Materialize a resolved alternative dict (from either the client or the library default)."""
    return ExerciseAlternative(
        id=data.get("id") or _new_id(),
        exercise_id=data["exercise_id"],
        reason=data["reason"],
        parameter_overrides_json=data.get("parameter_overrides_json"),
    )


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
                blocks_payload=payload.blocks,
                db=db,
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
        blocks_payload=payload.blocks,
        db=db,
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
    blocks_payload: list[BlockIn] | None,
    db: Session,
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

    if blocks_payload is not None:
        # Force orphan-cleanup before inserting the new tree. Without the
        # explicit flush, same-PK re-inserts race with the cascade delete and
        # some new rows land with detached / empty children. See docstring.
        workout.blocks = []
        db.flush()
        workout.blocks = [_build_block(b, db) for b in blocks_payload]

    # Force updated_at to bump even when only nested blocks changed — SQLAlchemy's
    # onupdate fires on column changes, not relationship replacements.
    workout.updated_at = datetime.now(UTC)


@router.get("", response_model=list[WorkoutRead])
def list_workouts(
    db: DbSession,
    user_id: CurrentUserId,
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


@router.get("/{workout_id}", response_model=WorkoutRead)
def get_workout(workout_id: str, db: DbSession, user_id: CurrentUserId) -> Workout:
    stmt = (
        select(Workout)
        .options(workout_tree_loader())
        .where(Workout.id == workout_id, Workout.user_id == user_id)
    )
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
