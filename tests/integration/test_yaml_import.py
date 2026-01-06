from __future__ import annotations

from pathlib import Path

from workoutdb.db import connect, query
from workoutdb.yaml_import import import_yaml


def test_import_yaml_sets_schedule_fields(db_path: Path) -> None:
    fixture = Path(__file__).resolve().parent.parent / "fixtures" / "library.yaml"
    result = import_yaml(db_path, fixture)
    assert result.planned_workouts_created == 1

    with connect(db_path) as conn:
        rows = query(
            conn,
            "SELECT start_time, duration_min FROM planned_workout",
        )
    assert rows[0]["start_time"] == "07:30:00"
    assert rows[0]["duration_min"] == 60
