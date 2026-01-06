from __future__ import annotations

from typer.testing import CliRunner

from workoutdb.cli import app


def test_cli_help_smoke() -> None:
    runner = CliRunner()
    result = runner.invoke(app, ["--help"])
    assert result.exit_code == 0
    assert "WorkoutDB" in result.output or "workoutdb" in result.output.lower()
