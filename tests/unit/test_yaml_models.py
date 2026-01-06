from __future__ import annotations

from datetime import date

import pytest
from pydantic import ValidationError

from workoutdb.yaml_models import LibraryYaml, Plan, PlanDay


def test_plan_day_requires_time_pair() -> None:
    with pytest.raises(ValidationError):
        PlanDay(date=date(2026, 1, 6), template="Day A", start_time="07:30")

    with pytest.raises(ValidationError):
        PlanDay(date=date(2026, 1, 6), template="Day A", duration_min=60)


def test_plan_day_rejects_times_on_rest() -> None:
    with pytest.raises(ValidationError):
        PlanDay(date=date(2026, 1, 6), rest=True, start_time="07:30", duration_min=60)


def _minimal_template() -> dict:
    return {
        "name": "Template A",
        "blocks": [
            {
                "block_type": "strength",
                "structure_type": "straight_sets",
                "items": [{"exercise": "Back Squat"}],
            }
        ],
    }


def test_plan_rejects_duplicate_dates() -> None:
    with pytest.raises(ValidationError):
        Plan(
            user="Alice",
            days=[
                PlanDay(date=date(2026, 1, 6), template="Template A"),
                PlanDay(date=date(2026, 1, 6), template="Template A"),
            ],
        )


def test_library_rejects_duplicate_users() -> None:
    with pytest.raises(ValidationError):
        LibraryYaml.model_validate(
            {
                "version": 1,
                "users": [{"name": "Alice"}, {"name": "Alice"}],
                "templates": [_minimal_template()],
            }
        )


def test_library_rejects_duplicate_intents() -> None:
    with pytest.raises(ValidationError):
        LibraryYaml.model_validate(
            {
                "version": 1,
                "intents": [{"name": "strength"}, {"name": "strength"}],
                "templates": [_minimal_template()],
            }
        )


def test_library_rejects_duplicate_templates() -> None:
    with pytest.raises(ValidationError):
        LibraryYaml.model_validate(
            {
                "version": 1,
                "templates": [_minimal_template(), _minimal_template()],
            }
        )
