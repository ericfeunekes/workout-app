from __future__ import annotations

import json
import uuid

from .action_models import Action, ActionStatus, ActionType
from .actions_db import list_actions, update_action_status
from .db import query


def apply_actions(conn, batch_id: str | None = None) -> dict[str, object]:
    counts: dict[str, object] = {"completed": 0, "failed": 0, "failed_ids": []}
    actions = list_actions(conn, status=ActionStatus.PENDING.value, batch_id=batch_id)
    for row in actions:
        action_id = row["action_id"]
        update_action_status(conn, action_id, ActionStatus.RUNNING.value)
        try:
            payload = json.loads(row["payload_json"])
            action = Action.model_validate(
                {
                    "action_id": action_id,
                    "action_type": row["action_type"],
                    "payload": payload,
                    "source_ref": row["source_ref"],
                }
            )
            if action.action_type == ActionType.PLAN_SCHEDULE:
                _apply_plan_schedule(conn, action.payload)
            update_action_status(conn, action_id, ActionStatus.COMPLETED.value)
            counts["completed"] = int(counts["completed"]) + 1
        except Exception as exc:  # noqa: BLE001
            update_action_status(conn, action_id, ActionStatus.FAILED.value, str(exc))
            counts["failed"] = int(counts["failed"]) + 1
            counts["failed_ids"].append(action_id)
    return counts


def _apply_plan_schedule(conn, payload) -> None:
    user_rows = query(conn, "SELECT user_id FROM app_user WHERE name = ?", (payload.user,))
    if not user_rows:
        raise ValueError(f"User not found: {payload.user}")
    user_id = user_rows[0]["user_id"]

    if payload.rest:
        template_id = None
    else:
        rows = query(conn, "SELECT template_id FROM workout_template WHERE name = ?", (payload.template,))
        if not rows:
            raise ValueError(f"Template not found: {payload.template}")
        template_id = rows[0]["template_id"]

    status_arg = payload.status
    conn.execute(
        """
        INSERT INTO planned_workout (
            planned_id, user_id, date, template_id, status, notes, generated_by
        ) VALUES (?, ?, ?, ?, COALESCE(?, 'planned'), ?, 'assist_actions')
        ON CONFLICT(user_id, date) DO UPDATE SET
            template_id = excluded.template_id,
            notes = excluded.notes,
            generated_by = excluded.generated_by,
            status = COALESCE(?, planned_workout.status)
        """,
        (
            str(uuid.uuid4()),
            user_id,
            payload.date.isoformat(),
            template_id,
            status_arg,
            payload.notes,
            status_arg,
        ),
    )
