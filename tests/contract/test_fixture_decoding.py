"""The same fixtures the Swift tests decode must also validate against Pydantic schemas.

If either stack rejects a fixture, the wire format drifted and the fixtures must be
regenerated (or the schemas fixed).
"""

import json
from pathlib import Path

import pytest
from workoutdb_server.api.schemas import ExerciseRead, SyncPullOut, WorkoutRead

_FIXTURE_ROOT = Path(__file__).resolve().parents[2] / "schema" / "fixtures"


@pytest.mark.parametrize(
    "fixture,model",
    [
        ("workout_create.json", WorkoutRead),
        ("sync_pull_response.json", SyncPullOut),
        ("exercise_with_defaults.json", ExerciseRead),
    ],
)
def test_fixture_validates(fixture: str, model) -> None:
    path = _FIXTURE_ROOT / fixture
    assert path.exists(), f"Missing fixture: {path}"
    payload = json.loads(path.read_text())
    model.model_validate(payload)  # raises on validation failure
