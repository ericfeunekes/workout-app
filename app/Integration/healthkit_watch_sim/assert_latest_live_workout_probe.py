#!/usr/bin/env python3
"""Find and assert the latest XcodeBuildMCP watch live-workout probe log."""

from __future__ import annotations

import argparse
from pathlib import Path

from assert_live_workout_probe import BEGIN, assert_probe


def find_latest_probe_log(search_root: Path) -> Path:
    candidates = []
    for path in search_root.glob("workspaces/*/logs/com.ericfeunekes.WorkoutDB.watchkitapp*.log"):
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if BEGIN not in text:
            continue
        candidates.append(path)
    if not candidates:
        raise AssertionError(f"no watch live-workout probe logs found under {search_root}")
    return max(candidates, key=lambda path: path.stat().st_mtime)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--search-root",
        type=Path,
        default=Path.home() / "Library/Developer/XcodeBuildMCP",
    )
    parser.add_argument("--min-ticks", type=int, default=1)
    args = parser.parse_args()

    log_path = find_latest_probe_log(args.search_root)
    proof = assert_probe(log_path, args.min_ticks)
    print(
        "HealthKit watch simulator probe passed: "
        f"log={log_path} runID={proof.get('runID')} "
        f"ticks={len(proof.get('collectedTicks', []))}"
    )


if __name__ == "__main__":
    main()
