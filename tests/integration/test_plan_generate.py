from __future__ import annotations

from pathlib import Path

from typer.testing import CliRunner

from workoutdb.cli import app
from workoutdb.db import connect, query


def test_plan_generate_preserves_times(db_path: Path) -> None:
    with connect(db_path) as conn:
        user_id = "user-1"
        template_id = "tpl-1"
        conn.execute("INSERT INTO app_user (user_id, name) VALUES (?, ?)", (user_id, "Athlete"))
        conn.execute(
            "INSERT INTO workout_template (template_id, name) VALUES (?, ?)",
            (template_id, "Day A"),
        )
        conn.execute(
            """
            INSERT INTO planned_workout (
                planned_id, user_id, date, template_id, status, generated_by,
                start_time, duration_min
            ) VALUES (?, ?, ?, ?, 'planned', 'manual_yaml', ?, ?)
            """,
            ("planned-1", user_id, "2026-01-05", template_id, "06:00:00", 45),
        )

    runner = CliRunner()
    result = runner.invoke(
        app,
        [
            "plan",
            "generate",
            "--db",
            str(db_path),
            "--user",
            "Athlete",
            "--weeks",
            "1",
            "--start",
            "2026-01-05T00:00:00",
            "--sessions-per-week",
            "1",
        ],
    )
    assert result.exit_code == 0

    with connect(db_path) as conn:
        rows = query(
            conn,
            "SELECT start_time, duration_min FROM planned_workout WHERE date = ?",
            ("2026-01-05",),
        )
    assert rows[0]["start_time"] == "06:00:00"
    assert rows[0]["duration_min"] == 45
