from __future__ import annotations

from pathlib import Path

from typer.testing import CliRunner

from workoutdb.cli import app


def test_intent_seed_and_list(db_path: Path) -> None:
    runner = CliRunner()
    result = runner.invoke(app, ["intent", "seed", "--db", str(db_path)])
    assert result.exit_code == 0
    assert "Intents created: 14" in result.output

    result = runner.invoke(app, ["intent", "list", "--db", str(db_path)])
    assert result.exit_code == 0
    # Check for some known hierarchical structure
    assert "- strength" in result.output
    assert "  Primary strength intent" in result.output
    assert "  - max_strength" in result.output
    assert "    High load, low reps" in result.output
    assert "- hypertrophy" in result.output
    assert "  - pump" in result.output

