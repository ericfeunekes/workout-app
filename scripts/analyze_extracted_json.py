from __future__ import annotations

import json
import sys
from collections import Counter
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import argparse


@dataclass
class Summary:
    files_seen: int
    files_parsed: int
    files_invalid: int
    workouts_seen: int
    templates_seen: int
    blocks_seen: int
    items_seen: int
    unique_exercises: int
    program_names: list[str]
    week_ranges: list[str]
    athletes: list[str]
    block_types: dict[str, int]
    structure_types: dict[str, int]
    prescription_keys: dict[str, int]
    reps_formats: dict[str, int]
    time_formats: dict[str, int]
    distance_formats: dict[str, int]
    missing_fields: dict[str, int]


@dataclass
class Report:
    run_id: str
    input_dir: str
    files: dict[str, Any]
    summary: Summary


def _load_json(path: Path) -> dict[str, Any] | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None
    if not isinstance(data, dict):
        return None
    return data


def _rep_format(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, int):
        return "int"
    if isinstance(value, float):
        return "float"
    if isinstance(value, str):
        return "str"
    return type(value).__name__


def _track_missing(counter: Counter[str], field: str, value: Any) -> None:
    if value in (None, ""):
        counter[field] += 1


def run(input_dir: Path, run_dir: Path) -> None:
    if not input_dir.exists():
        print(f"Error: Input directory '{input_dir}' does not exist.", file=sys.stderr)
        return
    if not input_dir.is_dir():
        print(f"Error: Input path '{input_dir}' is not a directory.", file=sys.stderr)
        return

    files = sorted(p for p in input_dir.glob("*.json") if p.is_file())
    files_seen = 0
    files_parsed = 0
    files_invalid = 0

    workouts_seen = 0
    templates_seen = 0
    blocks_seen = 0
    items_seen = 0

    program_names: set[str] = set()
    week_ranges: set[str] = set()
    athletes: set[str] = set()
    exercise_names: set[str] = set()

    block_types: Counter[str] = Counter()
    structure_types: Counter[str] = Counter()
    prescription_keys: Counter[str] = Counter()
    reps_formats: Counter[str] = Counter()
    time_formats: Counter[str] = Counter()
    distance_formats: Counter[str] = Counter()
    missing_fields: Counter[str] = Counter()

    file_report: dict[str, Any] = {}

    for path in files:
        files_seen += 1
        data = _load_json(path)
        if data is None:
            files_invalid += 1
            file_report[path.name] = {"status": "invalid_json"}
            continue
        files_parsed += 1

        workouts = data.get("workouts")
        if not isinstance(workouts, list):
            missing_fields["workouts"] += 1
            file_report[path.name] = {"status": "missing_workouts"}
            continue

        page_source = data.get("page_source") or path.stem
        file_meta = {
            "page_source": page_source,
            "workouts": len(workouts),
        }
        file_report[path.name] = file_meta

        program_name = data.get("program_name")
        week_range = data.get("week_range")
        athlete = data.get("athlete")

        if program_name:
            program_names.add(program_name)
        if week_range:
            week_ranges.add(week_range)
        if athlete:
            athletes.add(athlete)

        for workout in workouts:
            workouts_seen += 1
            template_name = workout.get("template_name")
            if template_name:
                templates_seen += 1
            _track_missing(missing_fields, "template_name", template_name)

            metadata = workout.get("metadata") or {}
            _track_missing(missing_fields, "metadata.day_number", metadata.get("day_number"))

            blocks = workout.get("blocks")
            if not isinstance(blocks, list):
                missing_fields["blocks"] += 1
                continue

            for block in blocks:
                blocks_seen += 1
                block_types[block.get("block_type") or "null"] += 1
                structure_types[block.get("structure_type") or "null"] += 1

                items = block.get("items") or []
                for item in items:
                    items_seen += 1
                    exercise_name = item.get("exercise_name")
                    if exercise_name:
                        exercise_names.add(exercise_name)
                    _track_missing(missing_fields, "exercise_name", exercise_name)

                    prescription = item.get("prescription") or {}
                    if isinstance(prescription, dict):
                        for key, value in prescription.items():
                            prescription_keys[key] += 1
                            if key in {"reps", "reps_per_side"}:
                                reps_formats[_rep_format(value)] += 1
                            if key == "time_sec":
                                time_formats[_rep_format(value)] += 1
                            if key == "distance":
                                distance_formats[_rep_format(value)] += 1

    summary = Summary(
        files_seen=files_seen,
        files_parsed=files_parsed,
        files_invalid=files_invalid,
        workouts_seen=workouts_seen,
        templates_seen=templates_seen,
        blocks_seen=blocks_seen,
        items_seen=items_seen,
        unique_exercises=len(exercise_names),
        program_names=sorted(program_names),
        week_ranges=sorted(week_ranges),
        athletes=sorted(athletes),
        block_types=dict(block_types.most_common()),
        structure_types=dict(structure_types.most_common()),
        prescription_keys=dict(prescription_keys.most_common()),
        reps_formats=dict(reps_formats.most_common()),
        time_formats=dict(time_formats.most_common()),
        distance_formats=dict(distance_formats.most_common()),
        missing_fields=dict(missing_fields.most_common()),
    )

    run_id = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    run_path = run_dir / run_id
    run_path.mkdir(parents=True, exist_ok=True)

    report = Report(
        run_id=run_id,
        input_dir=str(input_dir),
        files=file_report,
        summary=summary,
    )

    output = json.dumps(asdict(report), indent=2)
    summary_file = run_path / "summary.json"
    summary_file.write_text(output, encoding="utf-8")
    
    print(f"Analysis complete.")
    print(f"Files processed: {files_seen} (Parsed: {files_parsed}, Invalid: {files_invalid})")
    print(f"Workouts found: {workouts_seen}")
    print(f"Full report written to: {summary_file}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="Directory of extracted JSON")
    parser.add_argument(
        "--run-dir",
        default="runs/analyze-extracted-json",
        help="Directory to write run outputs",
    )
    args = parser.parse_args()
    run(Path(args.input), Path(args.run_dir))


if __name__ == "__main__":
    main()
