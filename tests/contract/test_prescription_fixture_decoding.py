"""Every prescription fixture must be more than valid JSON — it must be a valid prescription.

Chunk 2 landed 23 fixtures at `schema/fixtures/prescription_*.json` covering every shape in
`docs/prescription.md`. Chunk 3 turns those fixtures into an executable contract:

1. **Layer A — structural sanity.** Each fixture must carry the keys the shape's section in
   `docs/prescription.md` documents. The per-shape required-keys map lives below as a
   constant so the failure mode is "fixture X is missing key Y", not "pydantic said no".

2. **Layer B — Pydantic wire round-trip.** The fixtures hold `timing_config_json` /
   `prescription_json` as *dicts* (one level up from the wire) to stay readable. The wire
   contract stores them as strings. This test serializes those inner dicts to JSON strings
   and pushes them through `WorkoutItemIn` / `BlockIn` / `ExerciseAlternativeIn` so the
   fixtures are proven decodable once they're serialized the way the API actually expects.

Two conventions are in play in the fixtures:

- **Wrapped fixtures** (11 timing-mode shapes + `parameter_overrides`): top-level JSON
  carries block-level keys (`timing_mode`, `timing_config_json`, `prescription_json`, etc.).
- **Bare fixtures** (11 parametric shapes): top-level JSON *is* the `prescription_json`.

`parameter_overrides` is the odd one — it's an `exercise_alternative` row, not a
prescription. It's validated against `ExerciseAlternativeIn`.
"""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from typing import Any

import pytest
from pydantic import ValidationError
from workoutdb_server.api.schemas import (
    BlockIn,
    ExerciseAlternativeIn,
    WorkoutItemIn,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES_DIR = REPO_ROOT / "schema" / "fixtures"


def _load_expected_shapes() -> set[str]:
    """Re-use EXPECTED_SHAPES from the architecture parity test as the single source of truth.

    `tests/` isn't a Python package, so a plain `from tests.architecture...` import fails.
    Loading the module by file path keeps the two tests synced without a package rearrangement.
    """
    parity_path = (
        REPO_ROOT / "tests" / "architecture" / "test_prescription_shape_parity.py"
    )
    spec = importlib.util.spec_from_file_location(
        "_prescription_shape_parity", parity_path
    )
    assert spec is not None and spec.loader is not None, (
        f"Could not load {parity_path} to read EXPECTED_SHAPES."
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return set(module.EXPECTED_SHAPES)


EXPECTED_SHAPES: set[str] = _load_expected_shapes()

# ---------- Shape classification ----------
#
# Wrapped = block-level shape; top-level carries timing_mode and timing_config_json.
# Bare    = parametric shape; top-level IS the prescription_json.
# Alternative = parameter_overrides — special case, ExerciseAlternativeIn.
#
# The fixture filename convention is prescription_<shape>.json for every shape.

_WRAPPED_SHAPES: frozenset[str] = frozenset(
    {
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
    }
)
_BARE_SHAPES: frozenset[str] = frozenset(
    {
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
    }
)
_ALTERNATIVE_SHAPES: frozenset[str] = frozenset({"parameter_overrides"})

assert _WRAPPED_SHAPES | _BARE_SHAPES | _ALTERNATIVE_SHAPES == EXPECTED_SHAPES, (
    "Classification must cover exactly the shapes in EXPECTED_SHAPES — "
    "add the shape to one of _WRAPPED_SHAPES, _BARE_SHAPES, or _ALTERNATIVE_SHAPES."
)


# ---------- Per-shape required-keys map ----------
#
# Derived from `docs/prescription.md` § "Per-timing-mode prescription shapes" and
# § "Parametric prescription shapes". Each entry lists the keys that MUST be present
# at the designated level. Keys beyond these are allowed — we enforce a lower bound,
# not a schema.
#
# For wrapped shapes the map has two slots: "top" keys (block-level wrapper keys) and
# "prescription" keys (inner prescription_json keys). For bare shapes there's just one
# set (top-level keys, which is the prescription). For the alternative shape the keys
# are the ExerciseAlternative fields.

_WRAPPED_REQUIRED_KEYS: dict[str, dict[str, set[str]]] = {
    "straight_sets": {
        "top": {"timing_mode", "timing_config_json", "prescription_json"},
        "prescription": {"sets", "reps", "load_kg", "target_rir", "autoreg"},
    },
    "superset": {
        "top": {"timing_mode", "timing_config_json", "rounds", "prescription_json"},
        "prescription": {"reps", "load_kg", "target_rir", "autoreg"},
    },
    "circuit": {
        "top": {"timing_mode", "timing_config_json", "rounds", "prescription_json"},
        "prescription": {"reps", "load_kg"},
    },
    "emom": {
        "top": {"timing_mode", "timing_config_json", "prescription_json"},
        "prescription": {"reps", "load_kg"},
    },
    "amrap": {
        "top": {"timing_mode", "timing_config_json", "prescription_json"},
        "prescription": {"reps"},
    },
    "for_time": {
        "top": {
            "timing_mode",
            "timing_config_json",
            "rounds",
            "rounds_rep_scheme",
            "prescription_json",
        },
        # `for_time` items need at most a `load_kg`; many carry `{}`. No required keys.
        "prescription": set(),
    },
    "intervals": {
        "top": {"timing_mode", "timing_config_json", "prescription_json"},
        # intervals item prescription is typically `{}` — the work lives in timing_config.
        "prescription": set(),
    },
    "tabata": {
        "top": {"timing_mode", "timing_config_json", "prescription_json"},
        # 20/10/8 is the definition; timing_config is {}, prescription is {}.
        "prescription": set(),
    },
    "continuous": {
        "top": {"timing_mode", "timing_config_json", "prescription_json"},
        # prescription is typically `{}`; all the work is in timing_config.
        "prescription": set(),
    },
    "custom": {
        "top": {"timing_mode", "timing_config_json", "prescription_json"},
        "prescription": set(),
    },
    "rest_block": {
        "top": {"timing_mode", "timing_config_json", "prescription_json"},
        "prescription": set(),
    },
}

_BARE_REQUIRED_KEYS: dict[str, set[str]] = {
    # Doc minimum is `percent_1rm` + `sets`; the canonical example also has `reps` and
    # `target_rir`, so we enforce those here.
    "percent_1rm": {"sets", "reps", "percent_1rm", "target_rir"},
    "rep_range": {"sets", "reps_min", "reps_max", "load_kg"},
    "per_side": {"sets", "reps", "per_side", "load_kg"},
    "tempo": {"sets", "reps", "load_kg", "tempo"},
    "sets_detail": {"sets_detail"},
    "drop_set": {"sets_detail"},
    "cluster": {"sets", "reps", "load_kg", "sub_sets", "intra_set_rest_sec"},
    "amrap_token": {"reps"},
    "warmup": {"warmup", "sets", "reps"},
    "bodyweight": {"sets", "reps"},
    "weighted_bodyweight": {"sets", "reps", "load_kg"},
}

_ALTERNATIVE_REQUIRED_KEYS: dict[str, set[str]] = {
    "parameter_overrides": {"exercise_id", "reason", "parameter_overrides_json"},
}

# Sanity: every expected shape appears in exactly one required-keys map.
_ALL_SHAPES_IN_MAPS = (
    set(_WRAPPED_REQUIRED_KEYS) | set(_BARE_REQUIRED_KEYS) | set(_ALTERNATIVE_REQUIRED_KEYS)
)
assert _ALL_SHAPES_IN_MAPS == EXPECTED_SHAPES, (
    f"Required-keys maps must cover every shape in EXPECTED_SHAPES exactly once. "
    f"Missing: {EXPECTED_SHAPES - _ALL_SHAPES_IN_MAPS}. "
    f"Extra: {_ALL_SHAPES_IN_MAPS - EXPECTED_SHAPES}."
)


# ---------- Helpers ----------


def _fixture_payload(shape: str) -> dict[str, Any]:
    path = FIXTURES_DIR / f"prescription_{shape}.json"
    assert path.exists(), f"Missing fixture for shape '{shape}': {path}"
    payload = json.loads(path.read_text())
    assert isinstance(payload, dict), (
        f"Fixture {path.name} top-level must be a JSON object, got {type(payload).__name__}."
    )
    return payload


def _assert_required_keys(
    shape: str, payload: dict[str, Any], required: set[str], *, where: str
) -> None:
    missing = required - set(payload.keys())
    assert not missing, (
        f"Fixture '{shape}' is missing required key(s) at {where}: "
        f"{sorted(missing)}. Present keys: {sorted(payload.keys())}."
    )


# ---------- Layer A — structural sanity ----------


@pytest.mark.parametrize("shape", sorted(EXPECTED_SHAPES))
def test_fixture_shape(shape: str) -> None:
    """Fixture has the keys its shape section in docs/prescription.md requires."""
    payload = _fixture_payload(shape)

    if shape in _WRAPPED_SHAPES:
        spec = _WRAPPED_REQUIRED_KEYS[shape]
        _assert_required_keys(shape, payload, spec["top"], where="top-level")
        inner = payload.get("prescription_json")
        assert isinstance(inner, dict), (
            f"Fixture '{shape}' has non-dict prescription_json at top level "
            f"(got {type(inner).__name__}). Wrapped fixtures carry inner shapes as dicts."
        )
        _assert_required_keys(
            shape, inner, spec["prescription"], where="prescription_json"
        )
        tcfg = payload.get("timing_config_json")
        assert isinstance(tcfg, dict), (
            f"Fixture '{shape}' has non-dict timing_config_json at top level "
            f"(got {type(tcfg).__name__})."
        )
    elif shape in _BARE_SHAPES:
        _assert_required_keys(
            shape, payload, _BARE_REQUIRED_KEYS[shape], where="top-level"
        )
    elif shape in _ALTERNATIVE_SHAPES:
        _assert_required_keys(
            shape, payload, _ALTERNATIVE_REQUIRED_KEYS[shape], where="top-level"
        )
        overrides = payload.get("parameter_overrides_json")
        assert isinstance(overrides, dict), (
            f"Fixture '{shape}' has non-dict parameter_overrides_json "
            f"(got {type(overrides).__name__}). The fixture holds it as a dict for "
            f"readability; the wire serializes to a JSON string."
        )
    else:  # pragma: no cover — covered by the module-level assert
        raise AssertionError(f"Unclassified shape: {shape}")


# ---------- Layer B — Pydantic wire round-trip ----------


# Canonical test UUIDs. Per docs/specs/v2-architecture.md, all entity ids are UUIDs.
# Pydantic doesn't enforce the format here, but keeping fixtures UUID-shaped
# preserves the "UUIDs everywhere" invariant so downstream Swift mapping works.
_FIXTURE_ITEM_ID = "f0000001-0000-4000-8000-000000000001"
_FIXTURE_EXERCISE_ID = "f0000002-0000-4000-8000-000000000002"
_FIXTURE_BLOCK_ID = "f0000003-0000-4000-8000-000000000003"
_FIXTURE_ALT_ID = "f0000004-0000-4000-8000-000000000004"


def _build_workout_item(prescription: dict[str, Any]) -> WorkoutItemIn:
    """Wrap a prescription dict in a minimal WorkoutItemIn with placeholder fields."""
    return WorkoutItemIn(
        id=_FIXTURE_ITEM_ID,
        position=0,
        exercise_id=_FIXTURE_EXERCISE_ID,
        prescription_json=json.dumps(prescription),
    )


def _build_block(shape: str, payload: dict[str, Any]) -> BlockIn:
    """Wrap a wrapped-fixture payload in a minimal BlockIn for Pydantic validation."""
    timing_mode = payload["timing_mode"]
    timing_config = payload["timing_config_json"]
    kwargs: dict[str, Any] = {
        "id": _FIXTURE_BLOCK_ID,
        "position": 0,
        "timing_mode": timing_mode,
        "timing_config_json": json.dumps(timing_config),
    }
    if "rounds" in payload:
        kwargs["rounds"] = payload["rounds"]
    if "rounds_rep_scheme" in payload:
        kwargs["rounds_rep_scheme_json"] = json.dumps(payload["rounds_rep_scheme"])
    return BlockIn(**kwargs)


@pytest.mark.parametrize("shape", sorted(EXPECTED_SHAPES))
def test_fixture_pydantic_roundtrip(shape: str) -> None:
    """Fixture survives the wire contract once serialized the way the API expects.

    Inner dicts (`prescription_json`, `timing_config_json`, `rounds_rep_scheme`,
    `parameter_overrides_json`) are serialized to JSON strings before being fed to the
    Pydantic models. If Pydantic rejects, the assertion message includes the full
    validation error so fixing the fixture is mechanical.
    """
    payload = _fixture_payload(shape)

    try:
        if shape in _WRAPPED_SHAPES:
            # Validate the block wrapper (timing_mode + timing_config_json + optional
            # rounds / rounds_rep_scheme).
            _build_block(shape, payload)
            # Validate the inner prescription as a WorkoutItemIn — what the app pulls.
            _build_workout_item(payload["prescription_json"])
        elif shape in _BARE_SHAPES:
            # Bare fixture is itself the prescription_json payload.
            _build_workout_item(payload)
        elif shape in _ALTERNATIVE_SHAPES:
            ExerciseAlternativeIn(
                id=_FIXTURE_ALT_ID,
                exercise_id=payload["exercise_id"],
                reason=payload["reason"],
                parameter_overrides_json=json.dumps(payload["parameter_overrides_json"]),
            )
        else:  # pragma: no cover
            raise AssertionError(f"Unclassified shape: {shape}")
    except ValidationError as exc:
        pytest.fail(
            f"Fixture '{shape}' failed Pydantic round-trip. "
            f"Once the dict fields are serialized to JSON strings the API DTOs should "
            f"accept the fixture — they didn't. Validation error:\n{exc}"
        )
