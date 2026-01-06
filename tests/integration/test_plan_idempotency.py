from __future__ import annotations
import pytest
from pathlib import Path
from workoutdb.db import connect, query
from workoutdb.yaml_import import import_yaml

def test_plan_import_idempotency(db_path: Path) -> None:
    yaml_content = """
version: 1
users:
  - name: "Alice"
templates:
  - name: "Day A"
    blocks:
      - block_type: "strength"
        structure_type: "straight_sets"
        items:
          - exercise: "Back Squat"
            prescription:
              sets: 3
              reps_target: 5
plans:
  - name: "My Plan"
    user: "Alice"
    days:
      - date: 2026-01-06
        template: "Day A"
    meta:
      version: 1
"""
    yaml_path = db_path.parent / "test_idempotency.yaml"
    yaml_path.write_text(yaml_content)

    # First import
    import_yaml(db_path, yaml_path)
    
    with connect(db_path) as conn:
        plans = query(conn, "SELECT plan_id, name FROM plan")
        assert len(plans) == 1
        plan_id_1 = plans[0]["plan_id"]
        
        workouts = query(conn, "SELECT planned_id, plan_id FROM planned_workout")
        assert len(workouts) == 1
        assert workouts[0]["plan_id"] == plan_id_1

    # Second import
    import_yaml(db_path, yaml_path)

    with connect(db_path) as conn:
        plans = query(conn, "SELECT plan_id, name FROM plan")
        # If not idempotent, this will be 2
        assert len(plans) == 1, f"Expected 1 plan, found {len(plans)}"
        assert plans[0]["plan_id"] == plan_id_1
