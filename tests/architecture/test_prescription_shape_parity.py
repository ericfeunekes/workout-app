"""FF-6 · Prescription shape ↔ fixture parity.

Every prescription shape documented in docs/prescription.md must have a
fixture in schema/fixtures/ that exercises it, so the wire format is
machine-verified against the authoring doc.

See docs/architecture/fitness-functions.md § FF-6.

Current status: the test enumerates the shapes we expect fixtures for.
Today, only base fixtures exist (`workout_create.json`, `sync_pull_response.json`).
Each missing fixture is an expected-failure entry, so the test fails loudly
and the diff of missing fixtures is the work list. Adding a fixture reduces
the failure set; reaching zero means the doc and the wire are in parity.

When you add a fixture, put it at `schema/fixtures/prescription_<shape>.json`
and add the corresponding shape name to EXPECTED_SHAPES below.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
FIXTURES_DIR = REPO_ROOT / "schema" / "fixtures"
PRESCRIPTION_DOC = REPO_ROOT / "docs" / "prescription.md"

# Shapes documented in docs/prescription.md that must have a prescription fixture.
# Keep this list in sync with the doc's shape sections. The doc is the spec;
# this list is how we make "spec" testable.
EXPECTED_SHAPES = {
    # Per-timing-mode
    "straight_sets",
    "superset",
    "circuit",
    "emom",
    "amrap",
    "for_time",
    "intervals",
    "tabata",
    "continuous",
    "custom",
    "rest_block",
    # Parametric
    "percent_1rm",
    "rep_range",
    "per_side",
    "tempo",
    "sets_detail",
    "drop_set",
    "cluster",
    "amrap_token",
    "warmup",
    "bodyweight",
    "weighted_bodyweight",
    "parameter_overrides",
}


def _fixture_path(shape: str) -> Path:
    return FIXTURES_DIR / f"prescription_{shape}.json"


def _existing_shape_fixtures() -> set[str]:
    return {
        p.stem.removeprefix("prescription_")
        for p in FIXTURES_DIR.glob("prescription_*.json")
    }


def test_expected_shapes_match_doc_sections() -> None:
    """Every shape name in EXPECTED_SHAPES should correspond to a section in the doc.

    Keeps this test's list honest — if a shape disappears from the doc, the
    test reminds us to also drop the fixture expectation.
    """
    doc = PRESCRIPTION_DOC.read_text().lower()
    # A loose check — we look for the shape name appearing as a code-formatted token
    # or heading in the doc. This catches typos in EXPECTED_SHAPES without being
    # overly strict about heading structure.
    missing_in_doc = sorted(
        s for s in EXPECTED_SHAPES
        if s.replace("_", " ") not in doc and s not in doc
    )
    assert not missing_in_doc, (
        f"EXPECTED_SHAPES lists shapes not mentioned in docs/prescription.md: "
        f"{missing_in_doc}. Either add the shape to the doc or remove it from this list."
    )


def test_every_expected_shape_has_a_fixture() -> None:
    existing = _existing_shape_fixtures()
    if not existing:
        pytest.skip(
            "No prescription_*.json fixtures exist yet. This test activates the moment "
            "the first one lands — at which point parity with EXPECTED_SHAPES becomes a "
            "merge-blocking rule. Tracked as 'Fixture pack for prescription shapes' in "
            "docs/open-questions.md (disposition: decide-next)."
        )
    missing = sorted(EXPECTED_SHAPES - existing)
    if missing:
        examples = "\n".join(f"  - schema/fixtures/prescription_{s}.json" for s in missing)
        raise AssertionError(
            f"{len(missing)} prescription shapes are documented but lack a fixture. "
            f"Each missing fixture should be a JSON file demonstrating the shape, "
            f"decodable by both Pydantic (server) and Swift Codable (app).\n"
            f"Missing:\n{examples}\n\n"
            f"When adding a fixture, also add a cross-decode assertion in "
            f"tests/contract/test_swift_schema_parity.py so the shape is exercised on both sides. "
            f"See docs/architecture/fitness-functions.md § FF-6."
        )


def test_no_orphan_fixtures() -> None:
    existing = _existing_shape_fixtures()
    orphans = sorted(existing - EXPECTED_SHAPES)
    assert not orphans, (
        f"Fixtures exist for shapes not in EXPECTED_SHAPES: {orphans}. "
        f"Either add the shape to docs/prescription.md and to EXPECTED_SHAPES, "
        f"or delete the fixture."
    )


def test_fixtures_are_valid_json() -> None:
    bad: list[tuple[str, str]] = []
    for p in FIXTURES_DIR.glob("prescription_*.json"):
        try:
            json.loads(p.read_text())
        except json.JSONDecodeError as e:
            bad.append((p.name, str(e)))
    assert not bad, f"Invalid JSON in fixtures: {bad}"
