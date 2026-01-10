from __future__ import annotations

from pathlib import Path

from workoutdb.db import connect, query
from workoutdb.extracted_json_import import import_extracted_json_dir


def test_import_extracted_json_creates_source_raw_and_templates(db_path: Path) -> None:
    fixture_dir = Path(__file__).resolve().parent.parent / "fixtures" / "extracted-json"
    result = import_extracted_json_dir(
        db_path=db_path,
        input_dir=fixture_dir,
        source_title="STC workouts 2025",
        source_author="Synergy Training Centre",
    )

    assert result.pages_seen == 1
    assert result.pages_invalid == 0
    assert result.workouts_seen == 2
    assert result.raw_workouts_created == 2
    assert result.templates_created == 2
    assert result.blocks_created == 2
    assert result.items_created == 2

    with connect(db_path) as conn:
        source_rows = query(conn, "SELECT title, author FROM workout_source WHERE deleted = 0")
        assert len(source_rows) == 1
        assert source_rows[0]["title"] == "STC workouts 2025"
        assert source_rows[0]["author"] == "Synergy Training Centre"

        raw_rows = query(conn, "SELECT external_ref, parse_status FROM raw_workout WHERE deleted = 0")
        assert {r["external_ref"] for r in raw_rows} == {"test-page#day-1", "test-page#day-2"}
        assert {r["parse_status"] for r in raw_rows} == {"parsed"}

        templates = query(conn, "SELECT name FROM workout_template WHERE deleted = 0")
        assert len(templates) == 2

        # Reps list should become per-set prescriptions.
        item_rows = query(
            conn,
            """
            SELECT wi.item_id, wi.sets, wi.reps_target, wi.prescription_type
            FROM workout_item wi
            JOIN exercise e ON e.exercise_id = wi.exercise_id
            WHERE e.name = 'Deadlift'
            """,
        )
        assert len(item_rows) == 1
        assert item_rows[0]["sets"] == 4
        assert item_rows[0]["reps_target"] is None
        assert item_rows[0]["prescription_type"] == "reps"

        set_rows = query(
            conn,
            """
            SELECT set_index, reps_target
            FROM workout_item_set_prescription
            WHERE item_id = ?
            ORDER BY set_index
            """,
            (item_rows[0]["item_id"],),
        )
        assert [(r["set_index"], r["reps_target"]) for r in set_rows] == [
            (1, 10),
            (2, 8),
            (3, 6),
            (4, 4),
        ]

