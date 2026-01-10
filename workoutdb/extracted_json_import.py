from __future__ import annotations

import json
import re
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .db import connect, query, transaction


@dataclass
class ExtractedJsonImportResult:
    source_created: bool = False
    pages_seen: int = 0
    pages_invalid: int = 0
    workouts_seen: int = 0
    raw_workouts_created: int = 0
    raw_workouts_updated: int = 0
    templates_created: int = 0
    templates_linked_existing: int = 0
    templates_overwritten: int = 0
    blocks_created: int = 0
    items_created: int = 0
    exercises_created: int = 0


def _new_id() -> str:
    return str(uuid.uuid4())


def _load_json(path: Path) -> dict[str, Any] | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None
    if not isinstance(data, dict):
        return None
    return data


def _ensure_workout_source(
    conn,
    *,
    kind: str,
    title: str,
    author: str | None,
    original_url: str | None,
    license_note: str | None,
) -> tuple[str, bool]:
    rows = query(
        conn,
        """
        SELECT source_id
        FROM workout_source
        WHERE deleted = 0
          AND kind = ?
          AND COALESCE(title, '') = COALESCE(?, '')
          AND COALESCE(author, '') = COALESCE(?, '')
        """,
        (kind, title, author),
    )
    if rows:
        if len(rows) > 1:
            raise ValueError(f"Multiple workout_source rows found for {kind=} {title=} {author=}")
        return rows[0]["source_id"], False

    source_id = _new_id()
    conn.execute(
        """
        INSERT INTO workout_source (source_id, kind, title, author, original_url, license_note)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        (source_id, kind, title, author, original_url, license_note),
    )
    return source_id, True


def _upsert_raw_workout(
    conn,
    *,
    source_id: str,
    external_ref: str,
    raw_text: str,
    raw_format: str,
    parse_status: str,
    parsed_json: dict[str, Any] | None,
    linked_template_id: str | None,
) -> tuple[str, bool]:
    rows = query(
        conn,
        """
        SELECT raw_workout_id
        FROM raw_workout
        WHERE deleted = 0 AND source_id = ? AND external_ref = ?
        """,
        (source_id, external_ref),
    )
    if rows:
        if len(rows) > 1:
            raise ValueError(f"Multiple raw_workout rows found for external_ref={external_ref}")
        raw_workout_id = rows[0]["raw_workout_id"]
        conn.execute(
            """
            UPDATE raw_workout
            SET raw_text = ?,
                raw_format = ?,
                parse_status = ?,
                parsed_json = ?,
                linked_template_id = ?
            WHERE raw_workout_id = ?
            """,
            (
                raw_text,
                raw_format,
                parse_status,
                json.dumps(parsed_json, ensure_ascii=False) if parsed_json is not None else None,
                linked_template_id,
                raw_workout_id,
            ),
        )
        return raw_workout_id, False

    raw_workout_id = _new_id()
    conn.execute(
        """
        INSERT INTO raw_workout (
            raw_workout_id, source_id, external_ref,
            raw_text, raw_format, parse_status, parsed_json, linked_template_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            raw_workout_id,
            source_id,
            external_ref,
            raw_text,
            raw_format,
            parse_status,
            json.dumps(parsed_json, ensure_ascii=False) if parsed_json is not None else None,
            linked_template_id,
        ),
    )
    return raw_workout_id, True


def _ensure_exercise(conn, name: str) -> tuple[str, bool]:
    rows = query(conn, "SELECT exercise_id FROM exercise WHERE deleted = 0 AND name = ?", (name,))
    if rows:
        return rows[0]["exercise_id"], False
    exercise_id = _new_id()
    conn.execute("INSERT INTO exercise (exercise_id, name) VALUES (?, ?)", (exercise_id, name))
    return exercise_id, True


def _get_template_id_by_name(conn, name: str) -> str | None:
    rows = query(
        conn,
        "SELECT template_id FROM workout_template WHERE deleted = 0 AND name = ?",
        (name,),
    )
    if not rows:
        return None
    if len(rows) > 1:
        raise ValueError(f"Multiple workout_template rows found for name={name!r}")
    return rows[0]["template_id"]


def _clear_template(conn, template_id: str) -> None:
    conn.execute(
        "DELETE FROM workout_item WHERE block_id IN (SELECT block_id FROM workout_block WHERE template_id = ?)",
        (template_id,),
    )
    conn.execute("DELETE FROM workout_block WHERE template_id = ?", (template_id,))


_RE_INT_LIST = re.compile(r"^\s*\d+(?:\s*,\s*\d+)+\s*$")
_RE_RANGE = re.compile(r"^\s*(\d+)\s*-\s*(\d+)\s*$")
_RE_DAY_PREFIX = re.compile(r"^\s*day\s*(\d+)\s*[-—:]?\s*(.*)$", re.IGNORECASE)
_RE_WS = re.compile(r"\s+")
_RE_STC_HYPHEN = re.compile(r"\bSTC\s*-\s*", re.IGNORECASE)


@dataclass
class _ParsedPrescription:
    prescription_type: str
    sets: int | None
    reps_target: int | None
    reps_min: int | None
    reps_max: int | None
    reps_is_per_side: int
    time_sec_target: int | None
    time_sec_min: int | None
    time_sec_max: int | None
    distance_m_target: float | None
    distance_m_min: float | None
    distance_m_max: float | None
    pace_sec_per_m_target: float | None
    pace_sec_per_m_min: float | None
    pace_sec_per_m_max: float | None
    extra_json: dict[str, Any] | None
    item_notes: str | None
    set_reps_targets: list[int] | None


def _infer_prescription_type(
    *,
    reps: Any,
    reps_per_side: Any,
    time_sec: Any,
    distance: Any,
    pace: Any,
) -> str:
    has_reps = reps is not None or reps_per_side is not None
    has_time = time_sec is not None
    has_distance = distance is not None or pace is not None
    kinds = [has_reps, has_time, has_distance]
    if sum(1 for k in kinds if k) > 1:
        return "mixed"
    if has_reps:
        return "reps"
    if has_time:
        return "time"
    if has_distance:
        return "distance"
    return "freeform"


def _parse_prescription(prescription: dict[str, Any] | None) -> _ParsedPrescription:
    prescription = prescription or {}

    sets = prescription.get("sets")
    sets_value: int | None = sets if isinstance(sets, int) else None

    reps = prescription.get("reps")
    reps_per_side = prescription.get("reps_per_side")
    time_sec = prescription.get("time_sec")
    distance = prescription.get("distance")
    pace = prescription.get("pace_sec_per_m")

    item_notes = prescription.get("notes")
    if item_notes is not None and not isinstance(item_notes, str):
        item_notes = str(item_notes)

    reps_target = None
    reps_min = None
    reps_max = None
    reps_is_per_side = 0
    set_reps_targets: list[int] | None = None

    if isinstance(reps_per_side, int):
        reps_target = reps_per_side
        reps_is_per_side = 1
    elif reps_per_side is not None:
        # Keep as extra if non-int
        pass

    if reps_target is None:
        if isinstance(reps, int):
            reps_target = reps
        elif isinstance(reps, str):
            value = reps.strip()
            m = _RE_RANGE.match(value)
            if m:
                reps_min = int(m.group(1))
                reps_max = int(m.group(2))
            elif _RE_INT_LIST.match(value):
                set_reps_targets = [int(x.strip()) for x in value.split(",")]
                if sets_value is None:
                    sets_value = len(set_reps_targets)
            else:
                # Try best-effort single int parse
                try:
                    reps_target = int(value)
                except ValueError:
                    pass

    time_sec_target = time_sec if isinstance(time_sec, int) else None

    distance_m_target = None
    if isinstance(distance, (int, float)):
        distance_m_target = float(distance)

    pace_sec_per_m_target = None
    if isinstance(pace, (int, float)):
        pace_sec_per_m_target = float(pace)

    extra: dict[str, Any] = {}
    for key, value in prescription.items():
        if key in {
            "sets",
            "reps",
            "reps_per_side",
            "time_sec",
            "distance",
            "pace_sec_per_m",
            "notes",
        }:
            continue
        extra[key] = value

    # Preserve non-canonical values for review.
    if isinstance(reps, str) and (reps_target is None and reps_min is None and set_reps_targets is None):
        extra["reps_raw"] = reps
    if reps_per_side is not None and not isinstance(reps_per_side, int):
        extra["reps_per_side_raw"] = reps_per_side
    if distance is not None and not isinstance(distance, (int, float)):
        extra["distance_raw"] = distance
    if time_sec is not None and not isinstance(time_sec, int):
        extra["time_sec_raw"] = time_sec

    prescription_type = _infer_prescription_type(
        reps=reps,
        reps_per_side=reps_per_side,
        time_sec=time_sec,
        distance=distance,
        pace=pace,
    )

    return _ParsedPrescription(
        prescription_type=prescription_type,
        sets=sets_value,
        reps_target=reps_target,
        reps_min=reps_min,
        reps_max=reps_max,
        reps_is_per_side=reps_is_per_side,
        time_sec_target=time_sec_target,
        time_sec_min=None,
        time_sec_max=None,
        distance_m_target=distance_m_target,
        distance_m_min=None,
        distance_m_max=None,
        pace_sec_per_m_target=pace_sec_per_m_target,
        pace_sec_per_m_min=None,
        pace_sec_per_m_max=None,
        extra_json=(extra if extra else None),
        item_notes=item_notes,
        set_reps_targets=set_reps_targets,
    )


def _canonical_template_name(
    *,
    template_name: str,
    page_program_name: str | None,
    page_week_range: str | None,
    page_title_raw: str | None,
    workout_metadata: dict[str, Any],
) -> str:
    """Return a stable, collision-resistant template name.

    Extracted JSON often contains generic names like 'Day 1'. For DB import we need
    a canonical name that is stable across re-imports and avoids collisions across
    different programs/weeks.
    """
    program_name = workout_metadata.get("program_name") or page_program_name
    week_range = workout_metadata.get("week_range") or page_week_range
    day_number = workout_metadata.get("day_number")
    title_raw = workout_metadata.get("title_raw") or page_title_raw

    descriptor = ""
    m = _RE_DAY_PREFIX.match(template_name.strip())
    if m:
        descriptor = (m.group(2) or "").strip()

    if isinstance(day_number, int):
        label = str(program_name or title_raw or page_title_raw or template_name).strip()
        label = _RE_STC_HYPHEN.sub("STC ", label)
        label = _RE_WS.sub(" ", label).strip()
        parts = [label]

        if week_range:
            week_str = str(week_range).strip()
            label_l = label.lower()
            if "week" not in label_l and "wk" not in label_l:
                parts.append(f"Week {week_str}")
        parts.append(f"Day {day_number}")
        if descriptor:
            parts.append(descriptor)
        return " — ".join(parts)

    return template_name.strip()


def import_extracted_json_dir(
    *,
    db_path: str | Path,
    input_dir: Path,
    source_title: str,
    source_author: str | None,
    source_kind: str = "file_import",
    source_original_url: str | None = None,
    source_license_note: str | None = None,
    overwrite_templates: bool = False,
    raw_format: str = "extracted_json_v1",
) -> ExtractedJsonImportResult:
    db_path = Path(db_path)
    if not input_dir.exists():
        raise ValueError(f"Input dir not found: {input_dir}")
    if not input_dir.is_dir():
        raise ValueError(f"Input path is not a directory: {input_dir}")

    result = ExtractedJsonImportResult()

    json_files = sorted(p for p in input_dir.glob("*.json") if p.is_file())
    with connect(db_path) as conn:
        with transaction(conn):
            source_id, created = _ensure_workout_source(
                conn,
                kind=source_kind,
                title=source_title,
                author=source_author,
                original_url=source_original_url,
                license_note=source_license_note,
            )
            result.source_created = created

            for path in json_files:
                result.pages_seen += 1
                data = _load_json(path)
                if data is None:
                    result.pages_invalid += 1
                    continue

                page_source = data.get("page_source") or path.stem
                page_program_name = data.get("program_name")
                page_week_range = data.get("week_range")
                page_title_raw = data.get("title_raw")
                workouts = data.get("workouts")
                if not isinstance(workouts, list):
                    continue

                for workout_index, workout in enumerate(workouts, start=1):
                    if not isinstance(workout, dict):
                        continue
                    result.workouts_seen += 1

                    metadata = workout.get("metadata") if isinstance(workout.get("metadata"), dict) else {}
                    day_number = metadata.get("day_number")
                    if isinstance(day_number, int):
                        suffix = f"day-{day_number}"
                    else:
                        suffix = f"workout-{workout_index:02d}"
                    external_ref = f"{page_source}#{suffix}"

                    raw_payload = {
                        "page": {
                            "page_source": page_source,
                            "program_name": data.get("program_name"),
                            "week_range": data.get("week_range"),
                            "athlete": data.get("athlete"),
                            "title_raw": data.get("title_raw"),
                        },
                        "workout": workout,
                    }
                    raw_text = json.dumps(raw_payload, ensure_ascii=False, indent=2)

                    template_name = workout.get("template_name")
                    if not isinstance(template_name, str) or not template_name.strip():
                        _, created_raw = _upsert_raw_workout(
                            conn,
                            source_id=source_id,
                            external_ref=external_ref,
                            raw_text=raw_text,
                            raw_format=raw_format,
                            parse_status="needs_review",
                            parsed_json=workout,
                            linked_template_id=None,
                        )
                        if created_raw:
                            result.raw_workouts_created += 1
                        else:
                            result.raw_workouts_updated += 1
                        continue

                    blocks = workout.get("blocks")
                    if not isinstance(blocks, list) or not blocks:
                        # Keep the raw workout for review, but do not create/update templates
                        # when there is no usable structure.
                        _, created_raw = _upsert_raw_workout(
                            conn,
                            source_id=source_id,
                            external_ref=external_ref,
                            raw_text=raw_text,
                            raw_format=raw_format,
                            parse_status="needs_review",
                            parsed_json=workout,
                            linked_template_id=None,
                        )
                        if created_raw:
                            result.raw_workouts_created += 1
                        else:
                            result.raw_workouts_updated += 1
                        continue

                    canonical_name = _canonical_template_name(
                        template_name=template_name,
                        page_program_name=page_program_name if isinstance(page_program_name, str) else None,
                        page_week_range=page_week_range if isinstance(page_week_range, str) else None,
                        page_title_raw=page_title_raw if isinstance(page_title_raw, str) else None,
                        workout_metadata=metadata,
                    )

                    existing_template_id = _get_template_id_by_name(conn, canonical_name)
                    if existing_template_id is not None and not overwrite_templates:
                        _, created_raw = _upsert_raw_workout(
                            conn,
                            source_id=source_id,
                            external_ref=external_ref,
                            raw_text=raw_text,
                            raw_format=raw_format,
                            parse_status="parsed",
                            parsed_json=workout,
                            linked_template_id=existing_template_id,
                        )
                        if created_raw:
                            result.raw_workouts_created += 1
                        else:
                            result.raw_workouts_updated += 1
                        result.templates_linked_existing += 1
                        continue

                    # Create or overwrite template.
                    if existing_template_id is None:
                        template_id = _new_id()
                        conn.execute(
                            """
                            INSERT INTO workout_template (template_id, name, description, intent_json, intent_primary_id, intent_secondary_id)
                            VALUES (?, ?, NULL, NULL, NULL, NULL)
                            """,
                            (template_id, canonical_name),
                        )
                        result.templates_created += 1
                    else:
                        template_id = existing_template_id
                        _clear_template(conn, template_id)
                        result.templates_overwritten += 1

                    for block in blocks:
                        if not isinstance(block, dict):
                            continue
                        block_index = block.get("block_index")
                        if not isinstance(block_index, int):
                            continue
                        block_id = _new_id()
                        block_intent = block.get("intent") if isinstance(block.get("intent"), dict) else {}
                        block_comments = block.get("additional_comments")
                        if block_comments:
                            block_intent = dict(block_intent)
                            block_intent["comments"] = block_comments

                        conn.execute(
                            """
                            INSERT INTO workout_block (
                                block_id, template_id, block_index, name, block_type,
                                structure_type, intent_json, intent_primary_id, intent_secondary_id
                            ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, NULL)
                            """,
                            (
                                block_id,
                                template_id,
                                block_index,
                                block.get("block_name"),
                                block.get("block_type"),
                                block.get("structure_type"),
                                json.dumps(block_intent, ensure_ascii=False) if block_intent else None,
                            ),
                        )
                        result.blocks_created += 1

                        items = block.get("items")
                        if not isinstance(items, list):
                            continue
                        for item in items:
                            if not isinstance(item, dict):
                                continue
                            item_index = item.get("item_index")
                            if not isinstance(item_index, int):
                                continue
                            exercise_name = item.get("exercise_name")
                            if not isinstance(exercise_name, str) or not exercise_name.strip():
                                continue

                            exercise_id, created_ex = _ensure_exercise(conn, exercise_name.strip())
                            if created_ex:
                                result.exercises_created += 1

                            parsed = _parse_prescription(
                                item.get("prescription")
                                if isinstance(item.get("prescription"), dict)
                                else None
                            )
                            item_id = _new_id()

                            conn.execute(
                                """
                                INSERT INTO workout_item (
                                    item_id, block_id, item_index, exercise_id,
                                    prescription_type, sets, reps_target, reps_min, reps_max,
                                    reps_is_per_side, time_sec_target, time_sec_min, time_sec_max,
                                    distance_m_target, distance_m_min, distance_m_max,
                                    pace_sec_per_m_target, pace_sec_per_m_min, pace_sec_per_m_max,
                                    prescription_json, notes, intent_primary_id, intent_secondary_id
                                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL)
                                """,
                                (
                                    item_id,
                                    block_id,
                                    item_index,
                                    exercise_id,
                                    parsed.prescription_type,
                                    parsed.sets,
                                    parsed.reps_target,
                                    parsed.reps_min,
                                    parsed.reps_max,
                                    parsed.reps_is_per_side,
                                    parsed.time_sec_target,
                                    parsed.time_sec_min,
                                    parsed.time_sec_max,
                                    parsed.distance_m_target,
                                    parsed.distance_m_min,
                                    parsed.distance_m_max,
                                    parsed.pace_sec_per_m_target,
                                    parsed.pace_sec_per_m_min,
                                    parsed.pace_sec_per_m_max,
                                    json.dumps(parsed.extra_json, ensure_ascii=False)
                                    if parsed.extra_json
                                    else None,
                                    parsed.item_notes,
                                ),
                            )
                            result.items_created += 1

                            if parsed.set_reps_targets:
                                for set_index, reps_target in enumerate(parsed.set_reps_targets, start=1):
                                    conn.execute(
                                        """
                                        INSERT INTO workout_item_set_prescription (
                                            item_id, set_index, prescription_type,
                                            reps_target, reps_min, reps_max, reps_is_per_side,
                                            time_sec_target, time_sec_min, time_sec_max,
                                            distance_m_target, distance_m_min, distance_m_max,
                                            pace_sec_per_m_target, pace_sec_per_m_min, pace_sec_per_m_max
                                        ) VALUES (?, ?, 'reps', ?, NULL, NULL, ?, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL)
                                        """,
                                        (item_id, set_index, reps_target, parsed.reps_is_per_side),
                                    )

                    _, created_raw = _upsert_raw_workout(
                        conn,
                        source_id=source_id,
                        external_ref=external_ref,
                        raw_text=raw_text,
                        raw_format=raw_format,
                        parse_status="parsed",
                        parsed_json=workout,
                        linked_template_id=template_id,
                    )
                    if created_raw:
                        result.raw_workouts_created += 1
                    else:
                        result.raw_workouts_updated += 1

    return result
