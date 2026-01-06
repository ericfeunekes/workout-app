from __future__ import annotations

import json
import uuid
from dataclasses import dataclass
from pathlib import Path

from .db import connect, query, transaction
from .yaml_io import validate_yaml
from .yaml_models import IntentDef, Prescription, SetPrescription, Template


@dataclass
class ImportResult:
    users_created: int = 0
    templates_created: int = 0
    blocks_created: int = 0
    items_created: int = 0
    exercises_created: int = 0
    plans_created: int = 0
    planned_workouts_created: int = 0


def _new_id() -> str:
    return str(uuid.uuid4())


def _ensure_user(conn, name: str) -> str:
    rows = query(conn, "SELECT user_id FROM app_user WHERE name = ?", (name,))
    if rows:
        if len(rows) > 1:
            raise ValueError(f"Multiple users named '{name}' found. Use unique names.")
        return rows[0]["user_id"]
    user_id = _new_id()
    conn.execute("INSERT INTO app_user (user_id, name) VALUES (?, ?)", (user_id, name))
    return user_id


def _ensure_exercise(conn, name: str) -> tuple[str, bool]:
    rows = query(conn, "SELECT exercise_id FROM exercise WHERE name = ?", (name,))
    if rows:
        return rows[0]["exercise_id"], False
    exercise_id = _new_id()
    conn.execute("INSERT INTO exercise (exercise_id, name) VALUES (?, ?)", (exercise_id, name))
    return exercise_id, True


def _ensure_tag(conn, name: str) -> str:
    rows = query(conn, "SELECT tag_id FROM tag WHERE name = ?", (name,))
    if rows:
        return rows[0]["tag_id"]
    tag_id = _new_id()
    conn.execute("INSERT INTO tag (tag_id, name) VALUES (?, ?)", (tag_id, name))
    return tag_id


def _ensure_intent(conn, intent: IntentDef, intent_ids: dict[str, str]) -> str:
    if intent.name in intent_ids:
        return intent_ids[intent.name]
    rows = query(conn, "SELECT intent_id FROM intent_taxonomy WHERE name = ?", (intent.name,))
    if rows:
        intent_ids[intent.name] = rows[0]["intent_id"]
        return intent_ids[intent.name]
    intent_id = _new_id()
    parent_id = None
    if intent.parent:
        parent_rows = query(
            conn,
            "SELECT intent_id FROM intent_taxonomy WHERE name = ?",
            (intent.parent,),
        )
        if not parent_rows:
            raise ValueError(f"Intent parent not found: {intent.parent}")
        parent_id = parent_rows[0]["intent_id"]
    conn.execute(
        "INSERT INTO intent_taxonomy (intent_id, parent_intent_id, name, description) VALUES (?, ?, ?, ?)",
        (intent_id, parent_id, intent.name, intent.description),
    )
    intent_ids[intent.name] = intent_id
    return intent_id


def _lookup_intent_id(conn, name: str | None, intent_ids: dict[str, str]) -> str | None:
    if not name:
        return None
    if name in intent_ids:
        return intent_ids[name]
    rows = query(conn, "SELECT intent_id FROM intent_taxonomy WHERE name = ?", (name,))
    if not rows:
        raise ValueError(f"Unknown intent: {name}")
    intent_ids[name] = rows[0]["intent_id"]
    return intent_ids[name]


def _tag_entity(conn, tag_id: str, entity_kind: str, entity_id: str) -> None:
    conn.execute(
        "INSERT OR IGNORE INTO entity_tag (tag_id, entity_kind, entity_id) VALUES (?, ?, ?)",
        (tag_id, entity_kind, entity_id),
    )


def _clear_template(conn, template_id: str) -> None:
    conn.execute(
        "DELETE FROM workout_item WHERE block_id IN (SELECT block_id FROM workout_block WHERE template_id = ?)",
        (template_id,),
    )
    conn.execute("DELETE FROM workout_block WHERE template_id = ?", (template_id,))
    conn.execute(
        "DELETE FROM entity_tag WHERE entity_kind = 'template' AND entity_id = ?",
        (template_id,),
    )


def _infer_prescription_type(p: Prescription | None, sp: list[SetPrescription] | None) -> str:
    if sp:
        return _infer_type_from_fields(sp)
    return _infer_type_from_fields([p] if p else [])


def _infer_type_from_fields(prescriptions: list[Prescription]) -> str:
    has_reps = False
    has_time = False
    has_distance = False
    has_pace = False
    for p in prescriptions:
        if p is None:
            continue
        if p.reps_target is not None or p.reps_min is not None or p.reps_max is not None:
            has_reps = True
        if p.time_sec_target is not None or p.time_sec_min is not None or p.time_sec_max is not None:
            has_time = True
        if p.distance_m_target is not None or p.distance_m_min is not None or p.distance_m_max is not None:
            has_distance = True
        if (
            p.pace_sec_per_m_target is not None
            or p.pace_sec_per_m_min is not None
            or p.pace_sec_per_m_max is not None
        ):
            has_pace = True
    kinds = [has_reps, has_time, has_distance, has_pace]
    if sum(1 for k in kinds if k) > 1:
        return "mixed"
    if has_reps:
        return "reps"
    if has_time:
        return "time"
    if has_distance or has_pace:
        return "distance"
    return "freeform"


def import_yaml(db_path: str | Path, yaml_path: Path) -> ImportResult:
    library = validate_yaml(yaml_path)
    result = ImportResult()

    with connect(db_path) as conn:
        with transaction(conn):
            intent_ids: dict[str, str] = {}
            if library.intents:
                pending = list(library.intents)
                while pending:
                    progressed = False
                    for intent in list(pending):
                        if intent.parent and intent.parent not in intent_ids:
                            continue
                        _ensure_intent(conn, intent, intent_ids)
                        pending.remove(intent)
                        progressed = True
                    if not progressed:
                        missing = ", ".join(sorted({i.parent for i in pending if i.parent}))
                        raise ValueError(f"Intent parents not found: {missing}")

            for user in library.users:
                rows = query(conn, "SELECT user_id FROM app_user WHERE name = ?", (user.name,))
                if not rows:
                    _ensure_user(conn, user.name)
                    result.users_created += 1

            template_name_to_id: dict[str, str] = {}
            existing = query(conn, "SELECT template_id, name FROM workout_template")
            for row in existing:
                template_name_to_id[row["name"]] = row["template_id"]

            for template in library.templates:
                stats = _import_template(conn, template, template_name_to_id, intent_ids)
                result.templates_created += stats[0]
                result.blocks_created += stats[1]
                result.items_created += stats[2]
                result.exercises_created += stats[3]

            for plan in library.plans:
                stats = _import_plan(conn, plan, template_name_to_id)
                result.plans_created += stats[0]
                result.planned_workouts_created += stats[1]

    return result


def _import_plan(conn, plan, template_map: dict[str, str]) -> tuple[int, int]:
    user_id = _ensure_user(conn, plan.user)
    plan_id = None
    if plan.name:
        rows = query(
            conn,
            "SELECT plan_id FROM plan WHERE user_id = ? AND name = ? AND deleted = 0",
            (user_id, plan.name),
        )
        if rows:
            plan_id = rows[0]["plan_id"]
            conn.execute(
                "UPDATE plan SET meta_json = ? WHERE plan_id = ?",
                (json.dumps(plan.meta) if plan.meta else None, plan_id),
            )
    if plan_id is None:
        plan_id = _new_id()
        conn.execute(
            """
            INSERT INTO plan (plan_id, user_id, name, meta_json)
            VALUES (?, ?, ?, ?)
            """,
            (plan_id, user_id, plan.name, json.dumps(plan.meta) if plan.meta else None),
        )
    created_workouts = 0
    for day in plan.days:
        _insert_plan_day(conn, day, user_id, template_map, plan_id)
        created_workouts += 1
    return 1, created_workouts


def _insert_plan_day(conn, day, user_id: str, template_map: dict[str, str], plan_id: str) -> None:
    if day.rest:
        template_id = None
    else:
        if day.template not in template_map:
            raise ValueError(f"Unknown template referenced in plan: {day.template}")
        template_id = template_map[day.template]

    status_arg = day.status
    start_time = day.start_time.isoformat() if day.start_time else None
    conn.execute(
        """
        INSERT INTO planned_workout (
            planned_id, user_id, date, template_id, status, notes, generated_by,
            start_time, duration_min, plan_id, meta_json
        ) VALUES (?, ?, ?, ?, COALESCE(?, 'planned'), ?, ?, ?, ?, ?, ?)
        ON CONFLICT(user_id, date) DO UPDATE SET
            template_id = excluded.template_id,
            status = COALESCE(?, planned_workout.status),
            notes = excluded.notes,
            generated_by = excluded.generated_by,
            start_time = excluded.start_time,
            duration_min = excluded.duration_min,
            plan_id = excluded.plan_id,
            meta_json = excluded.meta_json
        """,
        (
            _new_id(),
            user_id,
            day.date.isoformat(),
            template_id,
            status_arg,
            day.notes,
            "manual_yaml",
            start_time,
            day.duration_min,
            plan_id,
            json.dumps(day.meta) if day.meta else None,
            status_arg,
        ),
    )


def _import_template(
    conn,
    template: Template,
    name_to_id: dict[str, str],
    intent_ids: dict[str, str],
) -> tuple[int, int, int, int]:
    """Returns (created_templates, created_blocks, created_items, created_exercises)"""
    created_templates = 0
    created_blocks = 0
    created_items = 0
    created_exercises = 0

    if template.name in name_to_id:
        template_id = name_to_id[template.name]
        _clear_template(conn, template_id)
        conn.execute(
            """
            UPDATE workout_template
            SET description = ?, intent_json = ?, intent_primary_id = ?, intent_secondary_id = ?
            WHERE template_id = ?
            """,
            (
                template.description,
                json.dumps(template.intent) if template.intent else None,
                _lookup_intent_id(conn, template.intent_primary, intent_ids),
                _lookup_intent_id(conn, template.intent_secondary, intent_ids),
                template_id,
            ),
        )
    else:
        # Create new template
        template_id = _new_id()
        conn.execute(
            """
            INSERT INTO workout_template (
                template_id, name, description, intent_json, intent_primary_id, intent_secondary_id
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                template_id,
                template.name,
                template.description,
                json.dumps(template.intent) if template.intent else None,
                _lookup_intent_id(conn, template.intent_primary, intent_ids),
                _lookup_intent_id(conn, template.intent_secondary, intent_ids),
            ),
        )
        name_to_id[template.name] = template_id
        created_templates = 1

    # Replace tags with current YAML values
    for tag in template.tags:
        tag_id = _ensure_tag(conn, tag)
        _tag_entity(conn, tag_id, "template", template_id)

    # Insert Blocks
    for block_index, block in enumerate(template.blocks, start=1):
        block_id = _new_id()
        conn.execute(
            """
            INSERT INTO workout_block (
                block_id, template_id, block_index, name, block_type,
                structure_type, intent_json, intent_primary_id, intent_secondary_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                block_id,
                template_id,
                block_index,
                block.name,
                block.block_type,
                block.structure_type,
                json.dumps(block.intent) if block.intent else None,
                _lookup_intent_id(conn, block.intent_primary, intent_ids),
                _lookup_intent_id(conn, block.intent_secondary, intent_ids),
            ),
        )
        created_blocks += 1

        for item_index, item in enumerate(block.items, start=1):
            exercise_id, created = _ensure_exercise(conn, item.exercise)
            if created:
                created_exercises += 1
            
            prescription = item.prescription
            prescription_type = _infer_prescription_type(prescription, item.set_prescriptions)

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
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    item_id,
                    block_id,
                    item_index,
                    exercise_id,
                    prescription_type,
                    prescription.sets if prescription else None,
                    prescription.reps_target if prescription else None,
                    prescription.reps_min if prescription else None,
                    prescription.reps_max if prescription else None,
                    (1 if prescription and prescription.reps_is_per_side else 0),
                    prescription.time_sec_target if prescription else None,
                    prescription.time_sec_min if prescription else None,
                    prescription.time_sec_max if prescription else None,
                    prescription.distance_m_target if prescription else None,
                    prescription.distance_m_min if prescription else None,
                    prescription.distance_m_max if prescription else None,
                    prescription.pace_sec_per_m_target if prescription else None,
                    prescription.pace_sec_per_m_min if prescription else None,
                    prescription.pace_sec_per_m_max if prescription else None,
                    json.dumps(prescription.extra) if prescription and prescription.extra else None,
                    item.notes,
                    _lookup_intent_id(conn, item.intent_primary, intent_ids),
                    _lookup_intent_id(conn, item.intent_secondary, intent_ids),
                ),
            )
            created_items += 1

            if item.set_prescriptions:
                for set_index, set_prescription in enumerate(item.set_prescriptions, start=1):
                    set_type = _infer_prescription_type(set_prescription, None)
                    conn.execute(
                        """
                        INSERT INTO workout_item_set_prescription (
                            item_id, set_index, prescription_type,
                            reps_target, reps_min, reps_max, reps_is_per_side,
                            time_sec_target, time_sec_min, time_sec_max,
                            distance_m_target, distance_m_min, distance_m_max,
                            pace_sec_per_m_target, pace_sec_per_m_min, pace_sec_per_m_max
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            item_id,
                            set_index,
                            set_type,
                            set_prescription.reps_target,
                            set_prescription.reps_min,
                            set_prescription.reps_max,
                            1 if set_prescription.reps_is_per_side else 0,
                            set_prescription.time_sec_target,
                            set_prescription.time_sec_min,
                            set_prescription.time_sec_max,
                            set_prescription.distance_m_target,
                            set_prescription.distance_m_min,
                            set_prescription.distance_m_max,
                            set_prescription.pace_sec_per_m_target,
                            set_prescription.pace_sec_per_m_min,
                            set_prescription.pace_sec_per_m_max,
                        ),
                    )

    return created_templates, created_blocks, created_items, created_exercises
