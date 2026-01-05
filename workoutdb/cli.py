from __future__ import annotations

from datetime import date, datetime, timedelta
from pathlib import Path
import json
import uuid

import typer

from .db import connect, query
from .migrations import apply_migrations, pending_migrations
from .yaml_import import import_yaml
from .yaml_io import validate_yaml

app = typer.Typer(add_completion=False)
plan_app = typer.Typer(add_completion=False)


def _new_id() -> str:
    return str(uuid.uuid4())


def _session_days_map(sessions_per_week: int) -> set[int]:
    patterns = {
        1: {0},
        2: {0, 3},
        3: {0, 2, 4},
        4: {0, 1, 3, 4},
        5: {0, 1, 2, 3, 4},
        6: {0, 1, 2, 3, 4, 5},
        7: {0, 1, 2, 3, 4, 5, 6},
    }
    if sessions_per_week not in patterns:
        raise typer.Exit("sessions_per_week must be between 1 and 7")
    return patterns[sessions_per_week]


def _select_template_names(conn, tags: list[str]) -> list[str]:
    if tags:
        placeholders = ",".join(["?"] * len(tags))
        rows = query(
            conn,
            f"""
            SELECT t.name
            FROM workout_template t
            WHERE t.template_id IN (
                SELECT et.entity_id
                FROM entity_tag et
                JOIN tag tg ON tg.tag_id = et.tag_id
                WHERE et.entity_kind = 'template' AND tg.name IN ({placeholders})
            )
            ORDER BY t.name
            """,
            tags,
        )
    else:
        rows = query(conn, "SELECT name FROM workout_template ORDER BY name")
    return [row["name"] for row in rows]


def _get_user_id(conn, user: str) -> str:
    rows = query(conn, "SELECT user_id FROM app_user WHERE name = ?", (user,))
    if not rows:
        raise typer.Exit(f"User not found: {user}")
    return rows[0]["user_id"]


def _fetch_planned_workouts(conn, user_id: str, start_date: date, end_date: date):
    return query(
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

def _format_plan_rows(rows):
    formatted = []
    for row in rows:
        template = row["template_name"] or "Rest"
        status = row["status"] or "planned"
        notes = row["notes"] or ""
        formatted.append(
            {
                "date": row["date"],
                "title": template,
                "status": status,
                "notes": notes,
            }
        )
    return formatted

def _upsert_planned_workout(conn, user_id: str, day: date, template_id: str | None, gen: str) -> None:
    conn.execute(
        """
        INSERT INTO planned_workout (
            planned_id, user_id, date, template_id, status, notes, generated_by
        ) VALUES (?, ?, ?, ?, 'planned', NULL, ?)
        ON CONFLICT(user_id, date) DO UPDATE SET
            template_id = excluded.template_id,
            generated_by = excluded.generated_by
        """,
        (_new_id(), user_id, day.isoformat(), template_id, gen),
    )



@app.command("init-db")
def init_db(db: Path = typer.Option(..., "--db", help="Path to SQLite DB")) -> None:
    db.parent.mkdir(parents=True, exist_ok=True)
    applied = apply_migrations(db)
    typer.echo(f"Initialized {db}")
    if applied:
        typer.echo("Applied migrations:")
        for name in applied:
            typer.echo(f"- {name}")
    else:
        typer.echo("No migrations to apply")


@app.command("migrate")
def migrate(db: Path = typer.Option(..., "--db", help="Path to SQLite DB")) -> None:
    applied = apply_migrations(db)
    if applied:
        typer.echo("Applied migrations:")
        for name in applied:
            typer.echo(f"- {name}")
    else:
        typer.echo("No migrations to apply")


@app.command("doctor")
def doctor(db: Path = typer.Option(..., "--db", help="Path to SQLite DB")) -> None:
    with connect(db) as conn:
        rows = query(
            conn,
            """
            SELECT name
            FROM sqlite_master
            WHERE type='table'
            ORDER BY name
            """,
        )
        table_names = [row["name"] for row in rows if row["name"] != "schema_migrations"]
        typer.echo(f"Tables: {len(table_names)}")
        for name in table_names:
            count = query(conn, f"SELECT COUNT(1) AS c FROM {name}")[0]["c"]
            typer.echo(f"- {name}: {count}")


@app.command("list-library")
def list_library(
    db: Path = typer.Option(..., "--db", help="Path to SQLite DB"),
    tag: list[str] = typer.Option(None, "--tag", help="Filter by tag (repeatable)"),
) -> None:
    tag = tag or []
    where_clause = ""
    params = []

    if tag:
        placeholders = ",".join(["?"] * len(tag))
        where_clause = f"""
        WHERE t.template_id IN (
            SELECT et2.entity_id
            FROM entity_tag et2
            JOIN tag t2 ON t2.tag_id = et2.tag_id
            WHERE et2.entity_kind = 'template' AND t2.name IN ({placeholders})
        )
        """
        params = tag

    with connect(db) as conn:
        rows = query(
            conn,
            f"""
            SELECT t.template_id, t.name, t.description,
                   GROUP_CONCAT(tag.name, ', ') AS tags
            FROM workout_template t
            LEFT JOIN entity_tag et ON et.entity_kind = 'template' AND et.entity_id = t.template_id
            LEFT JOIN tag ON tag.tag_id = et.tag_id
            {where_clause}
            GROUP BY t.template_id
            ORDER BY t.name
            """,
            params,
        )

    if not rows:
        typer.echo("No templates found")
        return
    for row in rows:
        tags = row["tags"] or ""
        desc = row["description"] or ""
        typer.echo(f"- {row['name']}  [{tags}]")
        if desc:
            typer.echo(f"  {desc}")


@app.command("pending")
def pending(db: Path = typer.Option(..., "--db", help="Path to SQLite DB")) -> None:
    names = pending_migrations(db)
    if not names:
        typer.echo("No pending migrations")
        return
    typer.echo("Pending migrations:")
    for name in names:
        typer.echo(f"- {name}")


@plan_app.command("validate-yaml")
def validate_yaml_cmd(path: Path = typer.Argument(..., help="Path to YAML file")) -> None:
    try:
        library = validate_yaml(path)
    except ValueError as exc:
        typer.echo(str(exc), err=True)
        raise typer.Exit(1) from exc
    typer.echo("YAML valid")
    typer.echo(f"Templates: {len(library.templates)}")
    typer.echo(f"Plans: {len(library.plans)}")


@plan_app.command("import-yaml")
def import_yaml_cmd(
    db: Path = typer.Option(..., "--db", help="Path to SQLite DB"),
    path: Path = typer.Argument(..., help="Path to YAML file"),
) -> None:
    try:
        result = import_yaml(db, path)
    except ValueError as exc:
        typer.echo(str(exc), err=True)
        raise typer.Exit(1) from exc
    typer.echo("Import complete")
    typer.echo(f"Users created: {result.users_created}")
    typer.echo(f"Templates created: {result.templates_created}")
    typer.echo(f"Blocks created: {result.blocks_created}")
    typer.echo(f"Items created: {result.items_created}")
    typer.echo(f"Exercises created: {result.exercises_created}")
    typer.echo(f"Plans created: {result.plans_created}")
    typer.echo(f"Planned workouts created: {result.planned_workouts_created}")


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

    focus_list = [s.strip() for s in focus_muscles.split(",") if s.strip()] if focus_muscles else []

    with connect(db) as conn:
        user_id = _get_user_id(conn, user)
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
    user: str = typer.Option(..., "--user", help="User name"),
    date_from: datetime | None = typer.Option(None, "--from"),
    date_to: datetime | None = typer.Option(None, "--to"),
) -> None:
    start_date = date_from.date() if date_from else date.today()
    end_date = date_to.date() if date_to else (start_date + timedelta(days=7))

    with connect(db) as conn:
        user_id = _get_user_id(conn, user)
        plan_rows = _fetch_planned_workouts(conn, user_id, start_date, end_date)

    if not plan_rows:
        typer.echo("No planned workouts found")
        return
    for row in _format_plan_rows(plan_rows):
        typer.echo(f"{row['date']}: {row['title']} [{row['status']}]")
        if row["notes"]:
            typer.echo(f"  {row['notes']}")


@plan_app.command("push-calendar")
def push_calendar(
    db: Path = typer.Option(..., "--db", help="Path to SQLite DB"),
    user: str = typer.Option(..., "--user", help="User name"),
    date_from: datetime | None = typer.Option(None, "--from"),
    date_to: datetime | None = typer.Option(None, "--to"),
    dry_run: bool = typer.Option(True, "--dry-run"),
) -> None:
    start_date = date_from.date() if date_from else date.today()
    end_date = date_to.date() if date_to else (start_date + timedelta(days=7))

    with connect(db) as conn:
        user_id = _get_user_id(conn, user)
        plan_rows = _fetch_planned_workouts(conn, user_id, start_date, end_date)

    if not plan_rows:
        typer.echo("No planned workouts found")
        return

    events = _format_plan_rows(plan_rows)
    if dry_run:
        typer.echo("Calendar events preview (stub):")
        typer.echo(json.dumps(events, indent=2, ensure_ascii=True))
        return
    typer.echo("Calendar push not implemented yet. Use --dry-run for preview.")

@plan_app.command("generate")
def plan_generate(
    db: Path = typer.Option(..., "--db", help="Path to SQLite DB"),
    user: str = typer.Option(..., "--user", help="User name"),
    weeks: int = typer.Option(4, "--weeks"),
    start: datetime = typer.Option(datetime.now(), "--start"),
    reference_plan: str | None = typer.Option(None, "--reference-plan"),
    tag: list[str] = typer.Option(None, "--tag", help="Filter templates by tag (repeatable)"),
    sessions_per_week: int | None = typer.Option(None, "--sessions-per-week"),
) -> None:
    tag = tag or []
    start_date = start.date()
    with connect(db) as conn:
        user_id = _get_user_id(conn, user)

        if sessions_per_week is None:
            goal_rows = query(conn, "SELECT sessions_per_week FROM user_goal WHERE user_id = ?", (user_id,))
            if goal_rows:
                sessions_per_week = goal_rows[0]["sessions_per_week"]

        if not sessions_per_week:
            raise typer.Exit("sessions_per_week required (set goal or pass --sessions-per-week)")

        if reference_plan:
            tag.append(f"plan:{reference_plan}")

        templates = _select_template_names(conn, tag)
        if not templates:
            raise typer.Exit("No templates found for selection")

        target_days = _session_days_map(int(sessions_per_week))
        total_days = weeks * 7

        idx = 0
        for day_offset in range(total_days):
            current = start + timedelta(days=day_offset)
            if current.weekday() not in target_days:
                continue
            template_name = templates[idx % len(templates)]
            idx += 1
            template_id = query(
                conn,
                "SELECT template_id FROM workout_template WHERE name = ?",
                (template_name,),
            )[0]["template_id"]
            _upsert_planned_workout(conn, user_id, current, template_id, "generator_v1")

    typer.echo("Plan generated")


app.add_typer(plan_app, name="plan")


if __name__ == "__main__":
    app()
