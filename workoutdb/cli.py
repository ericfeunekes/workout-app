from __future__ import annotations

from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Optional
import json

import typer

from .db import connect, query
# ... (rest of imports)

# ... (id and template functions)

# ... (upsert function)

# ... (app setup)

# ... (db commands)

# ... (list-library and pending)

# ... (yaml commands)

@plan_app.command("set-goal")
def set_goal(
    db: Path = typer.Option(..., "--db", help="Path to SQLite DB"),
    user: str = typer.Option(..., "--user", help="User name"),
    goal: str = typer.Option(..., "--goal", help="Goal kind"),
    sessions_per_week: int = typer.Option(..., "--sessions-per-week"),
    minutes_per_session: int = typer.Option(..., "--minutes-per-session"),
    focus_muscles: str | None = typer.Option(None, "--focus-muscles", help="Comma list"),
    notes: str | None = typer.Option(None, "--notes"),
) -> None:
    if not (1 <= sessions_per_week <= 7):
        raise typer.Exit("sessions_per_week must be between 1 and 7")

    focus_list = [s.strip() for s in focus_muscles.split(",")] if focus_muscles else []
    focus_list = [s for s in focus_list if s]

    with connect(db) as conn:
        rows = query(conn, "SELECT user_id FROM app_user WHERE name = ?", (user,))
        if not rows:
            raise typer.Exit(f"User not found: {user}")
        user_id = rows[0]["user_id"]
        existing = query(conn, "SELECT user_goal_id FROM user_goal WHERE user_id = ?", (user_id,))
        if existing:
            conn.execute(
                """
                UPDATE user_goal
                SET goal_kind = ?, focus_muscles_json = ?, sessions_per_week = ?,
                    minutes_per_session = ?, notes = ?
                WHERE user_id = ?
                """,
                (
                    goal,
                    json.dumps(focus_list) if focus_list else None,
                    sessions_per_week,
                    minutes_per_session,
                    notes,
                    user_id,
                ),
            )
        else:
            conn.execute(
                """
                INSERT INTO user_goal (
                    user_goal_id, user_id, goal_kind, focus_muscles_json,
                    sessions_per_week, minutes_per_session, notes
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    _new_id(),
                    user_id,
                    goal,
                    json.dumps(focus_list) if focus_list else None,
                    sessions_per_week,
                    minutes_per_session,
                    notes,
                ),
            )
    typer.echo("Goal saved")


@plan_app.command("show")
def plan_show(
    db: Path = typer.Option(..., "--db", help="Path to SQLite DB"),
    user: str = typer.Option(..., "--user"),
    date_from: Optional[datetime] = typer.Option(None, "--from"),
    date_to: Optional[datetime] = typer.Option(None, "--to"),
) -> None:
    start_date = date_from.date() if date_from else date.today()
    end_date = date_to.date() if date_to else (start_date + timedelta(days=7))

    with connect(db) as conn:
        rows = query(conn, "SELECT user_id FROM app_user WHERE name = ?", (user,))
        if not rows:
            raise typer.Exit(f"User not found: {user}")
        user_id = rows[0]["user_id"]
        plan_rows = query(
            conn,
            """
            SELECT pw.date, pw.status, pw.notes, t.name AS template_name
            FROM planned_workout pw
            LEFT JOIN workout_template t ON t.template_id = pw.template_id
            WHERE pw.user_id = ? AND pw.date >= ? AND pw.date <= ?
            ORDER BY pw.date
            """,
            (user_id, start_date.isoformat(), end_date.isoformat()),
        )
    if not plan_rows:
        typer.echo("No planned workouts found")
        return
    for row in plan_rows:
        template = row["template_name"] or "Rest"
        status = row["status"] or "planned"
        notes = row["notes"] or ""
        typer.echo(f"{row['date']}: {template} [{status}]")
        if notes:
            typer.echo(f"  {notes}")


@plan_app.command("generate")
def plan_generate(
    db: Path = typer.Option(..., "--db", help="Path to SQLite DB"),
    user: str = typer.Option(..., "--user"),
    weeks: int = typer.Option(4, "--weeks"),
    start: datetime = typer.Option(datetime.now(), "--start"),
    reference_plan: str | None = typer.Option(None, "--reference-plan"),
    tag: list[str] = typer.Option(None, "--tag", help="Filter templates by tag (repeatable)"),
    sessions_per_week: int | None = typer.Option(None, "--sessions-per-week"),
) -> None:
    tag = tag or []
    start_date = start.date()
    with connect(db) as conn:
        user_rows = query(conn, "SELECT user_id FROM app_user WHERE name = ?", (user,))
        if not user_rows:
            raise typer.Exit(f"User not found: {user}")
        user_id = user_rows[0]["user_id"]

        if sessions_per_week is None:
            goal_rows = query(
                conn, "SELECT sessions_per_week FROM user_goal WHERE user_id = ?", (user_id,)
            )
            if goal_rows:
                sessions_per_week = goal_rows[0]["sessions_per_week"]

        if not sessions_per_week:
            raise typer.Exit("sessions_per_week required (set goal or pass --sessions-per-week)")

        if reference_plan:
            tag.append(f"plan:{reference_plan}")

        templates = _select_templates(conn, tag)
        if not templates:
            raise typer.Exit("No templates found for selection")

        target_days = _session_days_map(int(sessions_per_week))
        total_days = weeks * 7

        idx = 0
        for day_offset in range(total_days):
            current = start_date + timedelta(days=day_offset)
            weekday = current.weekday()
            if weekday not in target_days:
                continue
            template_id, _ = templates[idx % len(templates)]
            idx += 1
            _upsert_planned_workout(conn, user_id, current, template_id, "generator_v1")

    typer.echo("Plan generated")



app.add_typer(plan_app, name="plan")


if __name__ == "__main__":
    app()
