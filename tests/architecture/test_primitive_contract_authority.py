"""Primitive contract authority stays outside route modules."""

from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def test_primitive_contract_module_has_no_fastapi_or_sqlalchemy_boundary() -> None:
    source = (REPO_ROOT / "server/workoutdb_server/primitive/contract.py").read_text()

    assert "fastapi" not in source
    assert "sqlalchemy" not in source
    assert "HTTPException" not in source


def test_sync_route_delegates_primitive_tree_validation_to_contract_module() -> None:
    source = (REPO_ROOT / "server/workoutdb_server/api/sync.py").read_text()

    assert "validate_primitive_log_references" in source
    assert "class PrimitiveLogTreeIndex" not in source
    assert "def _validate_block_result_log" not in source
    assert "def _validate_slot_log" not in source


def test_active_docs_route_primitive_authoring_to_primitive_spec() -> None:
    navigator = (REPO_ROOT / "docs/AGENTS.md").read_text()
    workout_generation = (REPO_ROOT / "docs/workout-generation.md").read_text()

    assert "`specs/primitives-data-model.md` — **active primitive contract**" in navigator
    assert "workout-generation.md` — legacy bridge authoring guide" in navigator
    assert "not the active primitive authoring contract" in workout_generation
    assert "docs/specs/primitives-data-model.md" in workout_generation
    assert "Do not use this as the top-level entry point" in workout_generation


def test_primitives_contract_keeps_adapter_specific_fields_out_of_primitive_nodes() -> None:
    primitive_docs = (REPO_ROOT / "docs/specs/primitives-data-model.md").read_text().lower()
    server_schemas = (REPO_ROOT / "server/workoutdb_server/api/schemas.py").read_text().lower()

    assert "adapter-specific export fields" in primitive_docs
    assert "vendor-neutral" in primitive_docs
    primitive_schema_section = server_schemas[
        server_schemas.index("class primitiveworktargetin") : server_schemas.index(
            "class workoutcreate"
        )
    ]
    assert "workoutkit" not in primitive_schema_section
    assert "healthkit" not in primitive_schema_section
    assert "strava" not in primitive_schema_section


def test_hotspot_doc_names_current_and_incremental_primitive_authorities() -> None:
    hotspots = (REPO_ROOT / "docs/architecture/hotspots.md").read_text()

    assert "Primitive result-row tree/reference validation lives" in hotspots
    assert "Primitive authoring shape and input-field legality still live in Pydantic" in hotspots
    assert "primitive result tree/reference validation out of `api/sync.py`" in hotspots
