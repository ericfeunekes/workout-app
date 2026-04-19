"""Post-merge prescription validation — reject shapes that ship in spec but not code.

Runs AFTER `prescription_merge.merge_prescriptions` on every ingest path
(`POST /api/workouts`, `PUT /api/workouts/{id}`). The merge resolves library
defaults into the stored blob; this module enforces the v1-shipped subset on
the resolved form so we catch both client-authored violations and
library-default-induced violations in one place.

Why server-side and not just client-side:
- The iOS parser isolates unknown `apply_to` values so one bad item doesn't
  nuke a whole workout (bug-052), but parse-failure is silent from the
  server's view — a workout with `"apply_to": "next"` would land in SQLite,
  sync down to every future app install, and quietly execute without
  autoreg. Failing loudly at ingest keeps the wire contract one-way.
- Claude is the upstream author; a 422 here teaches it immediately when it
  drifts from the documented vocabulary (`docs/prescription.md` § "autoreg").

Scope kept tight (qa-017): only `autoreg.apply_to` for now. ADR-2026-04-17
calls out that `apply_to` ships with `"remaining"` only — `"next"` and
`"all-future"` are reserved-unimplemented. If other autoreg invariants need
the same ingest-time guard (e.g. `target_rir` required when `autoreg` is
present, `step_kg` types), add them here and cover them in
`tests/server/test_api_workouts.py`.
"""

from __future__ import annotations

import json
from typing import Any

from fastapi import HTTPException, status

# The only `apply_to` value shipped in v1. See ADR-2026-04-17-rir-autoreg-sync
# § 2 and `docs/prescription.md` § "autoreg.apply_to" — `"next"` and
# `"all-future"` are reserved-unimplemented.
_ALLOWED_APPLY_TO = ("remaining",)


def _iter_autoreg_objects(value: Any) -> list[dict[str, Any]]:
    """Walk `value` and return every dict stored under an `autoreg` key.

    The v1 shape only puts `autoreg` at the top level of a prescription, but
    walking recursively costs nothing and guards against future shapes
    (parametric overrides, per-set variation blocks) accidentally embedding
    an autoreg sub-object that bypasses the top-level check.
    """
    found: list[dict[str, Any]] = []

    def _walk(node: Any) -> None:
        if isinstance(node, dict):
            for key, child in node.items():
                if key == "autoreg" and isinstance(child, dict):
                    found.append(child)
                _walk(child)
        elif isinstance(node, list):
            for child in node:
                _walk(child)

    _walk(value)
    return found


def validate_resolved_prescription(
    resolved_json: str,
    *,
    item_position: int,
    block_position: int,
) -> None:
    """Raise 422 if the resolved prescription carries a disallowed value.

    `resolved_json` is the output of `merge_prescriptions` — a JSON object
    string. Callers pass the block + item positions so the error message
    points the author at the exact offending item; UUIDs would be less
    useful because a workout typically hasn't been persisted yet when this
    runs.

    Current checks:
    - `autoreg.apply_to`, if present, must be `"remaining"`.

    New checks should either extend the `autoreg` walk here or factor out
    a dispatcher once the checklist grows past two or three items.
    """
    try:
        parsed = json.loads(resolved_json)
    except (json.JSONDecodeError, ValueError):
        # The merge helper only emits well-formed JSON, so this would
        # indicate an upstream bug — let it bubble as a generic validator
        # error rather than silently swallowing.
        raise
    if not isinstance(parsed, dict):
        return

    for autoreg in _iter_autoreg_objects(parsed):
        apply_to = autoreg.get("apply_to")
        if apply_to is None:
            continue
        if apply_to not in _ALLOWED_APPLY_TO:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail=(
                    f"blocks[{block_position}].workout_items[{item_position}]"
                    f".prescription_json.autoreg.apply_to must be one of "
                    f"{list(_ALLOWED_APPLY_TO)}, got {apply_to!r}"
                ),
            )
