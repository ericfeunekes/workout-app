from __future__ import annotations

import json
from typing import Any

from .db import query


def utc_now() -> str:
    return "datetime('now')"


def create_action(
    conn,
    action_id: str,
    action_type: str,
    payload: dict[str, Any],
    status: str = "staged",
    source_ref: str | None = None,
    batch_id: str = "default",
) -> None:
    conn.execute(
        """
        INSERT INTO actions (
            action_id, action_type, payload_json, status, source_ref,
            batch_id, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))
        """,
        (action_id, action_type, json.dumps(payload), status, source_ref, batch_id),
    )


def list_actions(conn, status: str, batch_id: str | None = None) -> list:
    if batch_id:
        return query(
            conn,
            "SELECT * FROM actions WHERE status = ? AND batch_id = ? ORDER BY created_at ASC",
            (status, batch_id),
        )
    return query(
        conn,
        "SELECT * FROM actions WHERE status = ? ORDER BY created_at ASC",
        (status,),
    )


def update_action_status(conn, action_id: str, status: str, error: str | None = None) -> None:
    conn.execute(
        "UPDATE actions SET status = ?, updated_at = datetime('now'), last_error = ? WHERE action_id = ?",
        (status, error, action_id),
    )
