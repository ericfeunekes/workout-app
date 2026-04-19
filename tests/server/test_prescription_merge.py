"""Unit tests for the prescription/alternatives merge helpers.

See docs/decisions/ADR-2026-04-18-smart-defaults.md.
"""

import json

import pytest
from workoutdb_server.sync.prescription_merge import (
    canonicalize,
    merge_alternatives,
    merge_prescriptions,
)


def _parse(raw: str) -> dict:
    return json.loads(raw)


# ---------- merge_prescriptions ----------


def test_library_only_fills_in_missing_keys() -> None:
    """Item omits scalar + autoreg keys; library default lands wholesale."""
    library = json.dumps(
        {
            "target_rir": 2,
            "autoreg": {
                "overshoot_at": 2,
                "overshoot_step_kg": 2.5,
                "undershoot_at": 2,
                "undershoot_step_kg": 2.5,
                "apply_to": "remaining",
            },
        }
    )
    item = json.dumps({"sets": 4, "reps": 5, "load_kg": 102.5})

    resolved = _parse(merge_prescriptions(library, item))

    assert resolved["sets"] == 4
    assert resolved["reps"] == 5
    assert resolved["load_kg"] == 102.5
    assert resolved["target_rir"] == 2
    assert resolved["autoreg"]["overshoot_step_kg"] == 2.5
    assert resolved["autoreg"]["apply_to"] == "remaining"
    # R2.10: neither side declared a unit → server stamps the pound
    # default so the client sees a canonical shape.
    assert resolved["weight_unit"] == "lb"


def test_item_only_when_library_null() -> None:
    """No library default → item is returned with R2.10 `weight_unit` default."""
    item = json.dumps({"sets": 3, "reps": 10, "load_kg": 20})

    resolved = _parse(merge_prescriptions(None, item))

    assert resolved == {"sets": 3, "reps": 10, "load_kg": 20, "weight_unit": "lb"}


def test_item_scalar_wins_on_conflict() -> None:
    """When both sides set the same top-level scalar, item wins."""
    library = json.dumps({"target_rir": 2, "load_kg": 50})
    item = json.dumps({"sets": 4, "reps": 5, "load_kg": 102.5, "target_rir": 1})

    resolved = _parse(merge_prescriptions(library, item))

    assert resolved["target_rir"] == 1  # item's value wins
    assert resolved["load_kg"] == 102.5  # item's value wins
    assert resolved["sets"] == 4


def test_autoreg_nested_per_field_merge() -> None:
    """When both sides provide autoreg, each field merges independently."""
    library = json.dumps(
        {
            "target_rir": 2,
            "autoreg": {
                "overshoot_at": 2,
                "overshoot_step_kg": 2.5,
                "undershoot_at": 2,
                "undershoot_step_kg": 2.5,
                "apply_to": "remaining",
            },
        }
    )
    item = json.dumps(
        {
            "sets": 4,
            "reps": 5,
            "load_kg": 50,
            "autoreg": {"overshoot_step_kg": 1.0, "undershoot_step_kg": 1.0},
        }
    )

    resolved = _parse(merge_prescriptions(library, item))

    # Item's step_kg values win.
    assert resolved["autoreg"]["overshoot_step_kg"] == 1.0
    assert resolved["autoreg"]["undershoot_step_kg"] == 1.0
    # Library's other autoreg fields filled in.
    assert resolved["autoreg"]["overshoot_at"] == 2
    assert resolved["autoreg"]["undershoot_at"] == 2
    assert resolved["autoreg"]["apply_to"] == "remaining"


def test_autoreg_library_only_used_wholesale() -> None:
    """Item omits autoreg entirely → library's autoreg block is preserved."""
    library = json.dumps({"autoreg": {"overshoot_step_kg": 2.5, "apply_to": "remaining"}})
    item = json.dumps({"sets": 4, "reps": 5})

    resolved = _parse(merge_prescriptions(library, item))

    assert resolved["autoreg"] == {"overshoot_step_kg": 2.5, "apply_to": "remaining"}


def test_empty_both_yields_empty_object() -> None:
    """Neither side has anything → empty resolved payload."""
    assert merge_prescriptions(None, "{}") == "{}"


def test_output_is_stable_sorted() -> None:
    """sort_keys=True so equality checks across calls are deterministic."""
    library = json.dumps({"z": 1, "a": 2})
    item = json.dumps({"m": 3})

    resolved = merge_prescriptions(library, item)

    # Keys appear in alphabetical order — stable across invocations.
    # R2.10: `weight_unit: "lb"` also lands here because the merge didn't
    # see one from either side.
    assert resolved == '{"a":2,"m":3,"weight_unit":"lb","z":1}'


def test_merge_defaults_weight_unit_to_lb() -> None:
    """R2.10: neither side declares weight_unit → server stamps "lb"."""
    resolved = _parse(merge_prescriptions(None, json.dumps({"sets": 3, "reps": 5, "load_kg": 100})))
    assert resolved["weight_unit"] == "lb"


def test_merge_respects_explicit_weight_unit_on_item() -> None:
    """R2.10: explicit weight_unit on the item wins over the default."""
    resolved = _parse(
        merge_prescriptions(
            None, json.dumps({"sets": 3, "reps": 5, "load_kg": 100, "weight_unit": "kg"})
        )
    )
    assert resolved["weight_unit"] == "kg"


def test_merge_respects_explicit_weight_unit_on_library_default() -> None:
    """R2.10: library default carries weight_unit → item inherits (no override)."""
    library = json.dumps({"weight_unit": "kg", "target_rir": 2})
    item = json.dumps({"sets": 3, "reps": 5, "load_kg": 100})
    resolved = _parse(merge_prescriptions(library, item))
    assert resolved["weight_unit"] == "kg"


def test_merge_empty_item_with_empty_library_stays_empty() -> None:
    """Empty `{}` is preserved — conditioning items don't need a unit."""
    assert merge_prescriptions(None, "{}") == "{}"


def test_malformed_library_raises() -> None:
    with pytest.raises(ValueError):
        merge_prescriptions(json.dumps([1, 2, 3]), "{}")


# ---------- merge_alternatives ----------


def test_alternatives_library_fallback_when_item_empty() -> None:
    library = json.dumps(
        [{"exercise_id": "abc", "reason": "bar taken", "parameter_overrides_json": None}]
    )
    resolved = merge_alternatives(library, [])

    assert len(resolved) == 1
    assert resolved[0]["exercise_id"] == "abc"


def test_alternatives_item_replaces_library_wholesale() -> None:
    library = json.dumps([{"exercise_id": "abc", "reason": "bar taken"}])
    item = [{"exercise_id": "xyz", "reason": "different reason"}]

    resolved = merge_alternatives(library, item)

    assert len(resolved) == 1
    assert resolved[0]["exercise_id"] == "xyz"


def test_alternatives_both_empty_yields_empty_list() -> None:
    assert merge_alternatives(None, []) == []
    assert merge_alternatives("", []) == []


def test_alternatives_malformed_library_raises() -> None:
    with pytest.raises(ValueError):
        merge_alternatives(json.dumps({"not": "a list"}), [])


def test_alternatives_library_default_id_is_stripped() -> None:
    """bug-034: library defaults are templates. Any `id` on the library blob
    is stripped when the default falls through to an item with no alternatives,
    so the caller can mint a fresh UUID per materialization. Without this,
    two workouts pulling the same library default UNIQUE-crash on
    `exercise_alternatives.id`.
    """
    library = json.dumps(
        [
            {
                "id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                "exercise_id": "xyz",
                "reason": "bar taken",
                "parameter_overrides_json": None,
            }
        ]
    )
    resolved = merge_alternatives(library, [])

    assert len(resolved) == 1
    assert "id" not in resolved[0]
    assert resolved[0]["exercise_id"] == "xyz"
    assert resolved[0]["reason"] == "bar taken"


# ---------- canonicalize ----------


def test_canonicalize_preserves_values_ignores_whitespace() -> None:
    raw = '{"sets": 4, "reps":  5 }'
    assert canonicalize(raw) == '{"reps":5,"sets":4}'


def test_canonicalize_null_returns_empty_object() -> None:
    assert canonicalize("") == "{}"
