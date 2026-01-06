from __future__ import annotations

from pathlib import Path

from typer.testing import CliRunner

from workoutdb.cli import app


def test_plan_show_rejects_reverse_range(db_path: Path) -> None:
    runner = CliRunner()
    result = runner.invoke(
        app,
        [
            "plan",
            "show",
            "--db",
            str(db_path),
            "--user",
            "Alice",
            "--from",
            "2026-01-10T00:00:00",
            "--to",
            "2026-01-01T00:00:00",
        ],
    )
    assert result.exit_code != 0
    assert "date range invalid" in (result.stdout + result.stderr)


def test_plan_push_calendar_rejects_reverse_range(db_path: Path) -> None:
    runner = CliRunner()
    result = runner.invoke(
        app,
        [
            "plan",
            "push-calendar",
            "--db",
            str(db_path),
            "--user",
            "Alice",
            "--from",
            "2026-01-10T00:00:00",
            "--to",
            "2026-01-01T00:00:00",
        ],
    )
    assert result.exit_code != 0
    assert "date range invalid" in (result.stdout + result.stderr)
