from __future__ import annotations

from pathlib import Path
import re
import pytest
from typer.testing import CliRunner

from workoutdb.cli import app

runner = CliRunner()

@pytest.fixture
def db_file(tmp_path):
    db = tmp_path / "test.db"
    result = runner.invoke(app, ["init-db", "--db", str(db)])
    assert result.exit_code == 0
    return db

def test_intent_deep_nesting(db_file: Path, tmp_path: Path):
    intents_yaml = tmp_path / "intents.yaml"
    intents_yaml.write_text("""
version: 1
intents:
  - name: root
    description: Level 0
  - name: child
    description: Level 1
    parent: root
  - name: grandchild
    description: Level 2
    parent: child
""")
    
    result = runner.invoke(app, ["intent", "seed", "--db", str(db_file), str(intents_yaml)])
    assert result.exit_code == 0
    assert "Intents created: 3" in result.stdout

    result = runner.invoke(app, ["intent", "list", "--db", str(db_file)])
    assert result.exit_code == 0
    
    expected = [
        "- root",
        "  Level 0",
        "  - child",
        "    Level 1",
        "    - grandchild",
        "      Level 2"
    ]
    for line in expected:
        assert line in result.stdout

def test_intent_seed_invalid_parent(db_file: Path, tmp_path: Path):
    intents_yaml = tmp_path / "intents.yaml"
    intents_yaml.write_text("""
version: 1
intents:
  - name: child
    parent: non_existent
""")
    
    result = runner.invoke(app, ["intent", "seed", "--db", str(db_file), str(intents_yaml)])
    assert result.exit_code != 0
    assert "Intent parents not found: non_existent" in result.stderr

def test_intent_seed_cycle(db_file: Path, tmp_path: Path):
    intents_yaml = tmp_path / "intents.yaml"
    intents_yaml.write_text("""
version: 1
intents:
  - name: a
    parent: b
  - name: b
    parent: a
""")
    
    result = runner.invoke(app, ["intent", "seed", "--db", str(db_file), str(intents_yaml)])
    assert result.exit_code != 0
    assert "Intent parent cycle detected: a, b" in result.stderr

def test_intent_seed_default_idempotency(db_file: Path):
    # First seed
    result = runner.invoke(app, ["intent", "seed", "--db", str(db_file)])
    assert result.exit_code == 0
    match = re.search(r"Intents created: (\d+)", result.stdout)
    assert match
    assert int(match.group(1)) > 0

    # Second seed
    result = runner.invoke(app, ["intent", "seed", "--db", str(db_file)])
    assert result.exit_code == 0
    assert "Intents created: 0" in result.stdout
