#!/usr/bin/env python3
"""Assert the watchOS HealthKit live-workout probe log.

The probe is launched through XcodeBuildMCP with
`--healthkit-live-workout-probe`. XcodeBuildMCP owns the build/install/launch
path; this script makes the captured runtime log merge-gatable by extracting
the sentinel JSON and checking the proof fields.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

BEGIN = "HEALTHKIT_LIVE_WORKOUT_PROBE_JSON_BEGIN"
END = "HEALTHKIT_LIVE_WORKOUT_PROBE_JSON_END"


def _extract_payload(log_text: str) -> dict[str, Any]:
    try:
        start = log_text.index(BEGIN) + len(BEGIN)
        end = log_text.index(END, start)
    except ValueError as exc:
        raise AssertionError("probe sentinels were not found in the runtime log") from exc

    payload = log_text[start:end].strip()
    if not payload:
        raise AssertionError("probe JSON payload was empty")
    decoded = json.loads(payload)
    if not isinstance(decoded, dict):
        raise AssertionError("probe JSON payload must be an object")
    return decoded


def _require_true(proof: dict[str, Any], key: str) -> None:
    if proof.get(key) is not True:
        raise AssertionError(f"{key} must be true; got {proof.get(key)!r}")


def assert_probe(log_path: Path, min_ticks: int) -> dict[str, Any]:
    proof = _extract_payload(log_path.read_text(encoding="utf-8", errors="replace"))

    for key in (
        "healthDataAvailable",
        "sessionStarted",
        "collectionStarted",
        "collectionEnded",
        "workoutSaved",
    ):
        _require_true(proof, key)

    if proof.get("platform") != "watchOS":
        raise AssertionError(f"platform must be watchOS; got {proof.get('platform')!r}")

    ticks = proof.get("collectedTicks")
    if not isinstance(ticks, list):
        raise AssertionError("collectedTicks must be an array")
    if len(ticks) < min_ticks:
        raise AssertionError(f"expected at least {min_ticks} collected tick(s); got {len(ticks)}")

    if not any(tick.get("heartRateBPM") is not None for tick in ticks if isinstance(tick, dict)):
        raise AssertionError("expected at least one tick with heartRateBPM")

    if proof.get("error") not in (None, ""):
        raise AssertionError(f"probe reported error: {proof.get('error')!r}")

    return proof


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("log_path", type=Path)
    parser.add_argument("--min-ticks", type=int, default=1)
    args = parser.parse_args()

    proof = assert_probe(args.log_path, args.min_ticks)
    print(
        "HealthKit watch simulator probe passed: "
        f"runID={proof.get('runID')} ticks={len(proof.get('collectedTicks', []))}"
    )


if __name__ == "__main__":
    main()
