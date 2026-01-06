from __future__ import annotations

from pathlib import Path
import pytest
from typer.testing import CliRunner

from workoutdb.cli import app
from workoutdb.db import connect, query

runner = CliRunner()

@pytest.fixture
def db_file(tmp_path):
    db = tmp_path / "test.db"
    # Init DB
    result = runner.invoke(app, ["init-db", "--db", str(db)])
    assert result.exit_code == 0
    return db

def test_intent_lifecycle(db_file: Path, tmp_path: Path):
    # 1. List empty intents
    result = runner.invoke(app, ["intent", "list", "--db", str(db_file)])
    assert result.exit_code == 0
    assert "No intents found" in result.stdout

    # 2. Seed intents
    intents_yaml = tmp_path / "intents.yaml"
    intents_yaml.write_text("""
version: 1
intents:
  - name: strength
    description: High force production
  - name: hypertrophy
    description: Muscle growth
    parent: strength
""")
    
    result = runner.invoke(app, ["intent", "seed", "--db", str(db_file), str(intents_yaml)])
    assert result.exit_code == 0
    assert "Intents created: 2" in result.stdout

    # 3. List intents again
    result = runner.invoke(app, ["intent", "list", "--db", str(db_file)])
    assert result.exit_code == 0
    assert "- strength" in result.stdout
    assert "High force production" in result.stdout
    assert "  - hypertrophy" in result.stdout
    assert "    Muscle growth" in result.stdout

    # 4. Seed same intents (should not create more)
    result = runner.invoke(app, ["intent", "seed", "--db", str(db_file), str(intents_yaml)])
    assert result.exit_code == 0
    assert "Intents created: 0" in result.stdout
