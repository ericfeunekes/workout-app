"""Prescription merge helpers — library defaults + item overrides → resolved form.

See docs/decisions/ADR-2026-04-18-smart-defaults.md.

The merge is pure: operates on parsed dicts, returns JSON strings with
`sort_keys=True` for stable equality. It runs on POST /api/workouts and
PUT /api/workouts/{id} — once, at ingest. After that, workout_items carry
their fully-resolved prescription and are immune to library mutations.

Semantics:

- Scalar keys at the top level: item wins.
- The `autoreg` sub-object is merged field-by-field, item wins on conflict.
  Missing `autoreg` on item => library's `autoreg` used wholesale; both missing
  => no `autoreg` key in the resolved output.
- Alternatives: item's list replaces library defaults when non-empty; when the
  item omits alternatives, library defaults are copied in wholesale.
"""

from __future__ import annotations

import json
from typing import Any


def _load_or_empty(raw: str | None) -> dict[str, Any]:
    """Parse a JSON object string or return {} for null/empty input.

    Malformed JSON raises — the server should never have stored an
    unparseable blob; surfacing it loudly beats silently merging nothing.
    """
    if raw is None or raw == "":
        return {}
    parsed = json.loads(raw)
    if not isinstance(parsed, dict):
        raise ValueError(f"prescription JSON must be an object, got {type(parsed).__name__}")
    return parsed


def _dumps(value: Any) -> str:
    """Stable JSON serialization so equality checks are deterministic."""
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


#: R2.10 default for ``weight_unit`` when neither library nor item
#: specify one. Eric trains primarily in pounds, so pound-first is the
#: new default (see ``docs/prescription.md`` § "Units").
DEFAULT_WEIGHT_UNIT = "lb"


def merge_prescriptions(library_default: str | None, item_prescription: str) -> str:
    """Deep-merge an exercise's library default onto a workout_item's payload.

    `item_prescription` is required (a workout_item always has a
    prescription_json column, even if the object is ``{}``). `library_default`
    is optional — when absent, the item payload is returned unchanged (but
    re-serialized for stable equality).

    Only the `autoreg` sub-object gets field-level merging. Everything else
    at the top level is scalar-win-item. Deeper nesting inside `autoreg` is
    not merged — the ADR calls out `autoreg` specifically and no other
    known sub-object needs per-field inheritance today.

    R2.10: when the resolved prescription is non-empty and has no
    ``weight_unit`` key, ``DEFAULT_WEIGHT_UNIT`` is stamped. The empty
    object ``{}`` stays empty — it commonly represents an item inside a
    conditioning block where the work lives on the block, not the item.
    """
    lib = _load_or_empty(library_default)
    item = _load_or_empty(item_prescription)

    # Start with the library default as the floor, let item keys overwrite.
    resolved: dict[str, Any] = dict(lib)
    for key, value in item.items():
        resolved[key] = value

    # Autoreg merges field-by-field when both sides provide it.
    lib_autoreg = lib.get("autoreg")
    item_autoreg = item.get("autoreg")
    if isinstance(lib_autoreg, dict) and isinstance(item_autoreg, dict):
        merged_autoreg = dict(lib_autoreg)
        merged_autoreg.update(item_autoreg)
        resolved["autoreg"] = merged_autoreg
    # else: whichever of the two was a dict (or neither) is already correct
    # from the top-level scalar-win pass above.

    # R2.10: default `weight_unit` to "lb" for non-empty prescriptions
    # that didn't declare one on either side. Empty `{}` payloads are
    # preserved verbatim — those items live under conditioning blocks
    # whose work lives on the block, not the item.
    if resolved and "weight_unit" not in resolved:
        resolved["weight_unit"] = DEFAULT_WEIGHT_UNIT

    return _dumps(resolved)


def merge_alternatives(
    library_defaults: str | None,
    item_alternatives: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Resolve an item's alternatives list against the exercise's library defaults.

    If the item supplies any alternatives, they replace the library defaults
    wholesale — the ADR deliberately does not merge alternative lists
    element-by-element because alternatives are identified by exercise_id and
    a merge would surprise more than it would help.

    If the item omits alternatives (empty list) and the library carries a
    non-empty default list, the library list is copied into the stored
    alternatives. If both are empty, the result is an empty list.

    The return is a list of parsed dicts. Callers materialize them into
    `ExerciseAlternative` ORM rows; any `id` needed for a new row is
    assigned at insert time.

    bug-034: library-default alternatives are a *template*, not rows. Any
    `id` on the library blob is stripped before the dict leaves this
    function — callers mint a fresh UUID per materialization. Otherwise
    the same library default embedded in two workouts collides on the
    UNIQUE primary key of `exercise_alternatives.id`.
    """
    if item_alternatives:
        return list(item_alternatives)

    if library_defaults is None or library_defaults == "":
        return []
    parsed = json.loads(library_defaults)
    if not isinstance(parsed, list):
        raise ValueError(
            f"default_alternatives_json must be a JSON array, got {type(parsed).__name__}"
        )
    # Strip any `id` from library defaults so each materialization gets a
    # fresh UUID assigned downstream. The library entry is a template.
    return [{k: v for k, v in alt.items() if k != "id"} for alt in parsed]


def canonicalize(raw: str) -> str:
    """Re-serialize a prescription JSON blob with sort_keys.

    Used to compare the resolved output against the client-sent input so we
    can null out `prescription_json_raw` when they're equivalent ignoring
    key ordering / whitespace.
    """
    return _dumps(_load_or_empty(raw))
