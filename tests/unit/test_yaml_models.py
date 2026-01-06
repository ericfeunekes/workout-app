from __future__ import annotations

from datetime import date

import pytest
from pydantic import ValidationError

from workoutdb.yaml_models import PlanDay


def test_plan_day_requires_time_pair() -> None:
    with pytest.raises(ValidationError):
        PlanDay(date=date(2026, 1, 6), template="Day A", start_time="07:30")

    with pytest.raises(ValidationError):
        PlanDay(date=date(2026, 1, 6), template="Day A", duration_min=60)


def test_plan_day_rejects_times_on_rest() -> None:
    with pytest.raises(ValidationError):
        PlanDay(date=date(2026, 1, 6), rest=True, start_time="07:30", duration_min=60)
