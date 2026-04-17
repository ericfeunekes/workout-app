"""Exercises endpoints. Claude owns the id namespace — server does not canonicalize on name."""

from fastapi import APIRouter

from workoutdb_server.api.deps import Auth, DbSession
from workoutdb_server.api.schemas import ExerciseRead, ExerciseUpsert
from workoutdb_server.models import Exercise

router = APIRouter(prefix="/api/exercises", tags=["exercises"])


@router.get(
    "",
    response_model=list[ExerciseRead],
    dependencies=[Auth],
    summary="List all exercises",
)
def list_exercises(db: DbSession) -> list[Exercise]:
    return list(db.query(Exercise).order_by(Exercise.name).all())


@router.post(
    "",
    response_model=list[ExerciseRead],
    dependencies=[Auth],
    summary="Upsert exercises (batch)",
)
def upsert_exercises(payload: list[ExerciseUpsert], db: DbSession) -> list[Exercise]:
    """Upsert by id. Batch accepted so Claude can push an exercise library in one call."""
    result: list[Exercise] = []
    for item in payload:
        existing = db.get(Exercise, item.id)
        if existing is None:
            existing = Exercise(
                id=item.id, name=item.name, notes=item.notes, demo_url=item.demo_url
            )
            db.add(existing)
        else:
            existing.name = item.name
            existing.notes = item.notes
            existing.demo_url = item.demo_url
        result.append(existing)
    db.commit()
    for e in result:
        db.refresh(e)
    return result
