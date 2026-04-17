"""Sync endpoints.

- GET /api/sync/pull?user_id=...&since=... — server → app. Workouts, exercises, user_parameters
  modified after `since`, plus a `last_performed` snapshot per exercise in the pulled workouts.
- POST /api/sync/results — app → server. Batch of set_logs + workout status transitions.

Direction-based; no conflict resolution. See docs/specs/v2-architecture.md § "Sync model".
"""

from datetime import UTC, datetime

from fastapi import APIRouter, HTTPException, Query, status
from sqlalchemy import func, select

from workoutdb_server.api.deps import Auth, DbSession
from workoutdb_server.api.workouts import workout_tree_loader
from workoutdb_server.api.schemas import (
    ExerciseLastPerformed,
    SetLogIn,
    SetLogRead,
    SyncPullOut,
    SyncResultsIn,
    UserParameterRead,
)
from workoutdb_server.models import (
    Block,
    Exercise,
    SetLog,
    UserParameter,
    Workout,
    WorkoutItem,
)

router = APIRouter(prefix="/api/sync", tags=["sync"])


@router.get("/pull", response_model=SyncPullOut, dependencies=[Auth])
def sync_pull(
    db: DbSession,
    user_id: str = Query(...),
    since: datetime | None = Query(
        None,
        description="Return rows updated after this timestamp. Omit for full pull.",
    ),
) -> SyncPullOut:
    workouts_stmt = select(Workout).options(workout_tree_loader()).where(Workout.user_id == user_id)
    if since is not None:
        workouts_stmt = workouts_stmt.where(Workout.created_at > since)
    workouts_stmt = workouts_stmt.order_by(Workout.scheduled_date, Workout.created_at)
    workouts = list(db.execute(workouts_stmt).scalars().all())

    # Exercise library is shared — pull all of them; volume is small.
    exercises = list(db.execute(select(Exercise).order_by(Exercise.name)).scalars().all())

    # Latest-per-key user parameters (what the app needs to resolve prescriptions).
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
    user_parameters = list(db.execute(params_stmt).scalars().all())

    last_performed = _build_last_performed(db, user_id, workouts)

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
    pulled_workouts: list[Workout],
) -> list[ExerciseLastPerformed]:
    """For every exercise present in the pulled workouts, attach the user's most recent set_logs.

    Two queries total regardless of exercise count:
      1. A ranked join finds the latest completed workout_item per exercise_id.
      2. A single IN query fetches all relevant set_logs.
    """
    exercise_ids: set[str] = set()
    for workout in pulled_workouts:
        for block in workout.blocks:
            for item in block.workout_items:
                exercise_ids.add(item.exercise_id)

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


@router.post("/results", response_model=dict, dependencies=[Auth])
def sync_results(payload: SyncResultsIn, db: DbSession) -> dict:
    """App pushes completed workout data. Idempotent — UUIDs prevent duplicates."""
    for log in payload.set_logs:
        _upsert_set_log(db, log)

    for update in payload.status_updates:
        workout = db.get(Workout, update.workout_id)
        if workout is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Workout {update.workout_id} not found",
            )
        workout.status = update.status
        if update.completed_at is not None:
            workout.completed_at = update.completed_at

    db.commit()
    return {
        "set_logs_received": len(payload.set_logs),
        "status_updates_received": len(payload.status_updates),
    }


def _upsert_set_log(db: DbSession, payload: SetLogIn) -> SetLog:
    row = db.get(SetLog, payload.id) if payload.id else None
    if row is None:
        row = SetLog(
            id=payload.id or None,  # let ORM default generate if missing
            workout_item_id=payload.workout_item_id,
            set_index=payload.set_index,
            reps=payload.reps,
            weight=payload.weight,
            weight_unit=payload.weight_unit,
            duration_sec=payload.duration_sec,
            distance_m=payload.distance_m,
            rpe=payload.rpe,
            is_warmup=payload.is_warmup,
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
            "set_index",
            "reps",
            "weight",
            "weight_unit",
            "duration_sec",
            "distance_m",
            "rpe",
            "is_warmup",
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
