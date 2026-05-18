"""Sync endpoints.

- GET /api/sync/pull?since=... — server → app. Workouts, exercises, user_parameters
  modified after `since`, plus a `last_performed` snapshot per exercise in the pulled workouts.
- POST /api/sync/results — app → server. Batch of set_logs + workout status transitions.

The caller's user_id is resolved from the bearer token (ADR-2026-04-17). Direction-based;
no conflict resolution. See docs/specs/v2-architecture.md § "Sync model".
"""

from datetime import UTC, datetime

from fastapi import APIRouter, HTTPException, Query, status
from sqlalchemy import func, select

from workoutdb_server.api.deps import CurrentUserId, DbSession
from workoutdb_server.api.schemas import (
    ExerciseLastPerformed,
    PrimitiveSetLogIn,
    PrimitiveSetLogRead,
    SyncPullOut,
    SyncResultsIn,
    SyncResultsOut,
    UserParameterRead,
    WorkoutReset,
)
from workoutdb_server.api.workouts import workout_tree_loader
from workoutdb_server.models import (
    Exercise,
    PrimitiveSetLog,
    UserParameter,
    Workout,
)

router = APIRouter(prefix="/api/sync", tags=["sync"])


@router.get("/pull", response_model=SyncPullOut)
def sync_pull(
    db: DbSession,
    user_id: CurrentUserId,
    since: datetime | None = Query(
        None,
        description="Return rows updated after this timestamp. Omit for full pull.",
    ),
) -> SyncPullOut:
    workouts_stmt = select(Workout).options(workout_tree_loader()).where(Workout.user_id == user_id)
    if since is not None:
        # updated_at catches both creation and post-create edits; filtering on
        # created_at would silently miss PUT /api/workouts/:id changes.
        workouts_stmt = workouts_stmt.where(Workout.updated_at > since)
    workouts_stmt = workouts_stmt.order_by(Workout.scheduled_date, Workout.created_at)
    workouts = list(db.execute(workouts_stmt).scalars().all())

    # Exercise library is shared — pull all of them; volume is small.
    exercises = list(db.execute(select(Exercise).order_by(Exercise.name)).scalars().all())

    # Latest-per-key user parameters (what the app needs to resolve prescriptions).
    # When `since` is set, skip keys whose latest row predates it — the app already has them.
    latest_subq = (
        select(UserParameter.key, func.max(UserParameter.updated_at).label("ts"))
        .where(UserParameter.user_id == user_id)
        .group_by(UserParameter.key)
        .subquery()
    )
    params_stmt = (
        select(UserParameter)
        .join(
            latest_subq,
            (UserParameter.key == latest_subq.c.key)
            & (UserParameter.updated_at == latest_subq.c.ts),
        )
        .where(UserParameter.user_id == user_id)
    )
    if since is not None:
        params_stmt = params_stmt.where(latest_subq.c.ts > since)
    user_parameters = list(db.execute(params_stmt).scalars().all())

    last_performed = _build_last_performed(db, user_id)

    return SyncPullOut(
        workouts=workouts,  # type: ignore[arg-type]
        exercises=exercises,  # type: ignore[arg-type]
        user_parameters=[UserParameterRead.model_validate(p) for p in user_parameters],
        last_performed=last_performed,
        server_time=datetime.now(UTC),
    )


def _build_last_performed(
    db: DbSession,
    user_id: str,
) -> list[ExerciseLastPerformed]:
    """Build last-performed chips from primitive slot-result logs only."""
    rows = (
        db.execute(
            select(PrimitiveSetLog)
            .join(Workout, Workout.id == PrimitiveSetLog.workout_id)
            .where(Workout.user_id == user_id)
            .where(Workout.status == "completed")
            .where(PrimitiveSetLog.role == "slot")
            .order_by(
                Workout.completed_at.desc(),
                PrimitiveSetLog.completed_at.desc(),
            )
        )
        .scalars()
        .all()
    )
    latest_workout_by_exercise: dict[str, str] = {}
    logs_by_exercise: dict[str, list[PrimitiveSetLog]] = {}
    for row in rows:
        exercise_id = row.performed_exercise_id or row.planned_exercise_id
        if exercise_id is None:
            continue
        latest_workout_id = latest_workout_by_exercise.setdefault(exercise_id, row.workout_id)
        if row.workout_id != latest_workout_id:
            continue
        logs_by_exercise.setdefault(exercise_id, []).append(row)
    return [
        ExerciseLastPerformed(
            exercise_id=exercise_id,
            last_set_logs=[
                PrimitiveSetLogRead.model_validate(log)
                for log in sorted(
                    logs,
                    key=lambda log: (
                        log.block_repeat_index,
                        log.set_repeat_index,
                        log.set_index,
                        log.completed_at,
                    ),
                )[:10]
            ],
        )
        for exercise_id, logs in logs_by_exercise.items()
    ]


@router.post("/results", response_model=SyncResultsOut)
def sync_results(payload: SyncResultsIn, db: DbSession, user_id: CurrentUserId) -> SyncResultsOut:
    """App pushes completed workout data. Idempotent — UUIDs prevent duplicates.

    Every set_log and status update is scoped to the authenticated user. Set logs
    for workout_items belonging to another user are rejected; status updates for
    another user's workouts 404.
    """
    _upsert_primitive_set_logs(db, payload.primitive_set_logs, user_id)

    for update in payload.status_updates:
        workout = db.get(Workout, update.workout_id)
        if workout is None or workout.user_id != user_id:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Workout {update.workout_id} not found",
            )
        workout.status = update.status
        if update.completed_at is not None:
            workout.completed_at = update.completed_at
        # `notes` is opt-in: a push that omits it (or sends None) leaves
        # the existing server-side value alone. The app sends the post-
        # workout note as part of the terminal push so the server becomes
        # authoritative — without this the next `sync/pull` would
        # overwrite the freshly-typed note with the server's old value.
        if update.notes is not None:
            workout.notes = update.notes

    for reset in payload.workout_resets:
        _reset_workout(db, reset, user_id)

    db.commit()
    return SyncResultsOut(
        primitive_set_logs_received=len(payload.primitive_set_logs),
        status_updates_received=len(payload.status_updates),
        workout_resets_received=len(payload.workout_resets),
    )


def _upsert_primitive_set_logs(db: DbSession, logs: list[PrimitiveSetLogIn], user_id: str) -> None:
    referenced_workout_ids = {log.workout_id for log in logs}
    if referenced_workout_ids:
        workouts = (
            db.execute(select(Workout).where(Workout.id.in_(referenced_workout_ids)))
            .scalars()
            .all()
        )
        workout_by_id: dict[str, Workout] = {workout.id: workout for workout in workouts}
    else:
        workout_by_id = {}

    for log in logs:
        workout = workout_by_id.get(log.workout_id)
        if workout is None or workout.user_id != user_id:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Workout {log.workout_id} not found",
            )
        _validate_primitive_log_references(log, workout)
        _upsert_primitive_set_log(db, log)


def _validate_primitive_log_references(log: PrimitiveSetLogIn, workout: Workout) -> None:
    block_ids: set[str] = set()
    set_to_block: dict[str, str] = {}
    slot_to_set: dict[str, str] = {}
    slot_to_exercise: dict[str, str] = {}
    for block in workout.primitive_blocks:
        block_id = block["id"]
        block_ids.add(block_id)
        for primitive_set in block.get("sets", []):
            set_id = primitive_set["id"]
            set_to_block[set_id] = block_id
            for slot in primitive_set.get("slots", []):
                slot_id = slot["id"]
                slot_to_set[slot_id] = set_id
                slot_to_exercise[slot_id] = slot["exercise_id"]

    if log.role == "block_result":
        if log.block_id not in block_ids:
            _raise_invalid_primitive_log("block_id", log)
        return

    if log.set_id is None or set_to_block.get(log.set_id) != log.block_id:
        _raise_invalid_primitive_log("set_id", log)

    if log.role == "set_result":
        return

    if log.slot_id is None or slot_to_set.get(log.slot_id) != log.set_id:
        _raise_invalid_primitive_log("slot_id", log)
    if (
        log.planned_exercise_id is not None
        and slot_to_exercise.get(log.slot_id) != log.planned_exercise_id
    ):
        _raise_invalid_primitive_log("planned_exercise_id", log)


def _raise_invalid_primitive_log(field: str, log: PrimitiveSetLogIn) -> None:
    raise HTTPException(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
        detail=(
            f"primitive log {log.id} has {field} outside workout {log.workout_id}'s primitive tree"
        ),
    )


def _reset_workout(db: DbSession, payload: WorkoutReset, user_id: str) -> None:
    workout = db.get(Workout, payload.workout_id)
    if workout is None or workout.user_id != user_id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Workout {payload.workout_id} not found",
        )

    primitive_logs = (
        db.execute(select(PrimitiveSetLog).where(PrimitiveSetLog.workout_id == workout.id))
        .scalars()
        .all()
    )
    for log in primitive_logs:
        db.delete(log)

    workout.status = "planned"
    workout.completed_at = None
    # Explicit bump keeps incremental pulls honest even if no scalar
    # value other than status/completed_at changed under SQLAlchemy's
    # onupdate machinery.
    workout.updated_at = datetime.now(UTC)


def _upsert_primitive_set_log(db: DbSession, payload: PrimitiveSetLogIn) -> PrimitiveSetLog:
    row = db.get(PrimitiveSetLog, payload.id)
    if row is None:
        row = PrimitiveSetLog(id=payload.id)
        db.add(row)
    for field in (
        "role",
        "slot_id",
        "set_id",
        "block_id",
        "workout_id",
        "planned_exercise_id",
        "performed_exercise_id",
        "set_index",
        "set_repeat_index",
        "block_repeat_index",
        "reps",
        "weight",
        "weight_unit",
        "duration_sec",
        "distance_m",
        "rounds",
        "rir",
        "is_warmup",
        "completed_at",
    ):
        setattr(row, field, getattr(payload, field))
    return row
