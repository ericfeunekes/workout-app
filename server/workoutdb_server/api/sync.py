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
    SetLogIn,
    SetLogRead,
    SyncPullOut,
    SyncResultsIn,
    UserParameterRead,
    WorkoutReset,
)
from workoutdb_server.api.workouts import workout_tree_loader
from workoutdb_server.models import (
    Block,
    Exercise,
    PrimitiveSetLog,
    SetLog,
    UserParameter,
    Workout,
    WorkoutItem,
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
    """For every exercise present in any of the user's workouts, attach the user's most
    recent set_logs.

    The snapshot is authoritative: the app overwrites its local chip map with whatever this
    returns, so an incremental pull (with `since`) must still cover every exercise the UI needs
    to render, not just those touched by the delta.

    qa-001 regression: earlier versions scoped exercise_ids to the `pulled_workouts` list
    (the same delta used for the `workouts` response); when the delta was empty (nothing
    changed since last sync) the snapshot came back `[]` and the app cheerfully overwrote
    its store with nothing, erasing every "LAST · …" chip on next launch. Scoping the
    exercise set to the full user catalog fixes that without changing the incremental
    workouts-delta behaviour.

    Two queries total regardless of exercise count:
      1. A ranked join finds the latest completed workout_item per exercise_id.
      2. A single IN query fetches all relevant set_logs.
    """
    # Include exercises referenced both directly and via alternatives — the app must
    # be able to display history for any exercise the user can swap to mid-workout.
    # Scope to every user workout regardless of status: the client overwrites its
    # chip map with whatever we return, so a pull right after the user's only planned
    # workout is completed (no more planned/active rows, but the just-written history
    # is still interesting) must still produce a non-empty snapshot. The ranked join
    # below already filters set_logs to completed workouts only.
    all_workouts_stmt = (
        select(Workout).options(workout_tree_loader()).where(Workout.user_id == user_id)
    )
    all_workouts = list(db.execute(all_workouts_stmt).scalars().all())

    exercise_ids: set[str] = set()
    for workout in all_workouts:
        for block in workout.blocks:
            for item in block.workout_items:
                exercise_ids.add(item.exercise_id)
                for alt in item.alternatives:
                    exercise_ids.add(alt.exercise_id)

    if not exercise_ids:
        return []

    # Query 1: latest WorkoutItem per exercise_id via ROW_NUMBER window.
    ranked = (
        select(
            WorkoutItem.id.label("item_id"),
            WorkoutItem.exercise_id.label("exercise_id"),
            WorkoutItem.prescription_json.label("prescription_json"),
            func.row_number()
            .over(
                partition_by=WorkoutItem.exercise_id,
                order_by=Workout.completed_at.desc(),
            )
            .label("rn"),
        )
        .join(Block, Block.id == WorkoutItem.block_id)
        .join(Workout, Workout.id == Block.workout_id)
        .where(Workout.user_id == user_id)
        .where(Workout.status == "completed")
        .where(WorkoutItem.exercise_id.in_(exercise_ids))
        .subquery()
    )
    latest = list(db.execute(select(ranked).where(ranked.c.rn == 1)).all())
    if not latest:
        return []

    item_to_exercise = {row.item_id: row.exercise_id for row in latest}
    item_to_prescription = {row.item_id: row.prescription_json for row in latest}

    # Query 2: all set_logs for those items in one shot.
    set_logs = (
        db.execute(
            select(SetLog)
            .where(SetLog.workout_item_id.in_(item_to_exercise.keys()))
            .order_by(SetLog.workout_item_id, SetLog.set_index)
        )
        .scalars()
        .all()
    )

    logs_by_item: dict[str, list[SetLog]] = {}
    for log in set_logs:
        logs_by_item.setdefault(log.workout_item_id, []).append(log)

    return [
        ExerciseLastPerformed(
            exercise_id=exercise_id,
            last_set_logs=[SetLogRead.model_validate(log) for log in logs_by_item.get(item_id, [])],
            prescription_json=item_to_prescription[item_id],
        )
        for item_id, exercise_id in item_to_exercise.items()
    ]


@router.post("/results", response_model=dict)
def sync_results(payload: SyncResultsIn, db: DbSession, user_id: CurrentUserId) -> dict:
    """App pushes completed workout data. Idempotent — UUIDs prevent duplicates.

    Every set_log and status update is scoped to the authenticated user. Set logs
    for workout_items belonging to another user are rejected; status updates for
    another user's workouts 404.
    """
    # Resolve every referenced workout_item's owner in a single query instead of
    # one `db.get(WorkoutItem, ...)` per set_log (which also lazy-loaded
    # Block.workout per row). For a 50-set_log payload that's 50+ extra
    # roundtrips; with this map it stays at one SELECT regardless of batch size.
    referenced_item_ids = {log.workout_item_id for log in payload.set_logs}
    if referenced_item_ids:
        ownership_rows = db.execute(
            select(WorkoutItem.id, Workout.user_id)
            .join(Block, Block.id == WorkoutItem.block_id)
            .join(Workout, Workout.id == Block.workout_id)
            .where(WorkoutItem.id.in_(referenced_item_ids))
        ).all()
        item_owner_by_id: dict[str, str] = {row[0]: row[1] for row in ownership_rows}
    else:
        item_owner_by_id = {}

    for log in payload.set_logs:
        owner = item_owner_by_id.get(log.workout_item_id)
        if owner is None or owner != user_id:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"workout_item {log.workout_item_id} not found",
            )
        _upsert_set_log(db, log)

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
    return {
        "set_logs_received": len(payload.set_logs),
        "primitive_set_logs_received": len(payload.primitive_set_logs),
        "status_updates_received": len(payload.status_updates),
        "workout_resets_received": len(payload.workout_resets),
    }


def _upsert_primitive_set_logs(db: DbSession, logs: list[PrimitiveSetLogIn], user_id: str) -> None:
    referenced_workout_ids = {log.workout_id for log in logs}
    if referenced_workout_ids:
        owner_rows = db.execute(
            select(Workout.id, Workout.user_id).where(Workout.id.in_(referenced_workout_ids))
        ).all()
        owner_by_workout: dict[str, str] = {row[0]: row[1] for row in owner_rows}
    else:
        owner_by_workout = {}

    for log in logs:
        owner = owner_by_workout.get(log.workout_id)
        if owner is None or owner != user_id:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Workout {log.workout_id} not found",
            )
        _upsert_primitive_set_log(db, log)


def _reset_workout(db: DbSession, payload: WorkoutReset, user_id: str) -> None:
    workout = db.get(Workout, payload.workout_id)
    if workout is None or workout.user_id != user_id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Workout {payload.workout_id} not found",
        )

    item_ids = (
        db.execute(
            select(WorkoutItem.id)
            .join(Block, Block.id == WorkoutItem.block_id)
            .where(Block.workout_id == workout.id)
        )
        .scalars()
        .all()
    )
    if item_ids:
        logs = (
            db.execute(select(SetLog).where(SetLog.workout_item_id.in_(item_ids))).scalars().all()
        )
        for log in logs:
            db.delete(log)
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


def _upsert_set_log(db: DbSession, payload: SetLogIn) -> SetLog:
    row = db.get(SetLog, payload.id)
    if row is None:
        row = SetLog(
            id=payload.id,
            workout_item_id=payload.workout_item_id,
            performed_exercise_id=payload.performed_exercise_id,
            set_index=payload.set_index,
            reps=payload.reps,
            weight=payload.weight,
            weight_unit=payload.weight_unit,
            duration_sec=payload.duration_sec,
            distance_m=payload.distance_m,
            rir=payload.rir,
            is_warmup=payload.is_warmup,
            skipped=payload.skipped,
            side=payload.side,
            started_at=payload.started_at,
            completed_at=payload.completed_at,
            hr_avg_bpm=payload.hr_avg_bpm,
            hr_max_bpm=payload.hr_max_bpm,
            cadence_avg_spm=payload.cadence_avg_spm,
            motion_samples_ref=payload.motion_samples_ref,
            notes=payload.notes,
        )
        db.add(row)
    else:
        for field in (
            "performed_exercise_id",
            "set_index",
            "reps",
            "weight",
            "weight_unit",
            "duration_sec",
            "distance_m",
            "rir",
            "is_warmup",
            "skipped",
            "side",
            "started_at",
            "completed_at",
            "hr_avg_bpm",
            "hr_max_bpm",
            "cadence_avg_spm",
            "motion_samples_ref",
            "notes",
        ):
            setattr(row, field, getattr(payload, field))
    return row


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
