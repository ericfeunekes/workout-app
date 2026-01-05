from __future__ import annotations

from datetime import date, timedelta
from pathlib import Path
import json
import uuid

import typer

from .actions_apply import apply_actions
from .actions_db import create_action, update_action_status
from .action_models import ActionStatus, ProposalFile
from .db import connect, query
from .migrations import apply_migrations, pending_migrations
from .plan_proposals import proposal_from_days, proposal_from_yaml, write_proposal
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


@app.command("init-db")
def init_db(db_path: Path = typer.Option(..., "--db", help="Path to SQLite DB")) -> None:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    applied = apply_migrations(db_path)
    typer.echo(f"Initialized {db_path}")
    if applied:
        typer.echo("Applied migrations:")
        for name in applied:
            typer.echo(f"- {name}")
    else:
        typer.echo("No migrations to apply")


@app.command("migrate")
def migrate(db_path: Path = typer.Option(..., "--db", help="Path to SQLite DB")) -> None:
    applied = apply_migrations(db_path)
    if applied:
        typer.echo("Applied migrations:")
        for name in applied:
            typer.echo(f"- {name}")
    else:
        typer.echo("No migrations to apply")


@app.command("doctor")
def doctor(db_path: Path = typer.Option(..., "--db", help="Path to SQLite DB")) -> None:
    with connect(db_path) as conn:
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
    db_path: Path = typer.Option(..., "--db", help="Path to SQLite DB"),
    tags: list[str] = typer.Option(None, "--tag", help="Filter by tag (repeatable)"),
) -> None:
    tags = tags or []
    where_clause = ""
    params = []

    if tags:
        placeholders = ",".join(["?"] * len(tags))
        where_clause = f"""
        WHERE t.template_id IN (
            SELECT et2.entity_id
            FROM entity_tag et2
            JOIN tag t2 ON t2.tag_id = et2.tag_id
            WHERE et2.entity_kind = 'template' AND t2.name IN ({placeholders})
        )
        """
        params = tags

    with connect(db_path) as conn:
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
        row_tags = row["tags"] or ""
        desc = row["description"] or ""
        typer.echo(f"- {row['name']}  [{row_tags}]")
        if desc:
            typer.echo(f"  {desc}")


@app.command("pending")
def pending(db_path: Path = typer.Option(..., "--db", help="Path to SQLite DB")) -> None:
    names = pending_migrations(db_path)
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
    db_path: Path = typer.Option(..., "--db", help="Path to SQLite DB"),
    path: Path = typer.Argument(..., help="Path to YAML file"),
) -> None:
    try:
        library = validate_yaml(path)
    except ValueError as exc:
        typer.echo(str(exc), err=True)
        raise typer.Exit(1) from exc
    if library.plans:
        typer.echo("Warning: plans found in YAML; use `plan propose-yaml` to schedule.", err=True)
    try:
        result = import_yaml(db_path, path)
    except ValueError as exc:
        typer.echo(str(exc), err=True)
        raise typer.Exit(1) from exc
    typer.echo("Import complete")
    typer.echo(f"Users created: {result.users_created}")
    typer.echo(f"Templates created: {result.templates_created}")
    typer.echo(f"Blocks created: {result.blocks_created}")
    typer.echo(f"Items created: {result.items_created}")
    typer.echo(f"Exercises created: {result.exercises_created}")


@plan_app.command("propose-yaml")
def propose_yaml(
    path: Path = typer.Argument(..., help="Path to YAML file"),
    out: Path = typer.Option(..., "--out", help="Proposal JSON output path"),
) -> None:
    library = validate_yaml(path)
    if library.templates:
        typer.echo("Warning: templates found in YAML; use `plan import-yaml` to load them.", err=True)
    if not library.plans:
        raise typer.Exit("No plans found in YAML")
    proposal = proposal_from_yaml(path, title="plan from yaml")
    write_proposal(proposal, out)
    typer.echo(f"Proposal written: {out}")


@plan_app.command("propose")
def propose_actions(
    db_path: Path = typer.Option(..., "--db", help="Path to SQLite DB"),
    input_path: Path = typer.Argument(..., help="Proposal JSON file"),
) -> None:
    try:
        proposal_data = json.loads(input_path.read_text(encoding="utf-8"))
        proposal = ProposalFile.model_validate(proposal_data)
    except Exception as exc:  # noqa: BLE001
        typer.echo(f"Validation error: {exc}", err=True)
        raise typer.Exit(1) from exc

    batch_id = f"plan-{uuid.uuid4().hex[:8]}"
    with connect(db_path) as conn:
        for action in proposal.actions:
            create_action(
                conn,
                action_id=action.action_id,
                action_type=action.action_type.value,
                payload=action.payload.model_dump(),
                status=ActionStatus.STAGED.value,
                source_ref=action.source_ref,
                batch_id=batch_id,
            )
    typer.echo(f"Proposed actions (batch_id={batch_id})")


@plan_app.command("approve")
def approve_actions(
    db_path: Path = typer.Option(..., "--db", help="Path to SQLite DB"),
    batch_id: str = typer.Option(..., "--batch-id"),
) -> None:
    with connect(db_path) as conn:
        rows = query(conn, "SELECT action_id FROM actions WHERE batch_id = ?", (batch_id,))
        if not rows:
            raise typer.Exit(f"No actions found for batch_id={batch_id}")
        for row in rows:
            update_action_status(conn, row["action_id"], ActionStatus.PENDING.value)
    typer.echo("Approved")


@plan_app.command("apply")
def apply_pending(
    db_path: Path = typer.Option(..., "--db", help="Path to SQLite DB"),
    batch_id: str | None = typer.Option(None, "--batch-id"),
) -> None:
    with connect(db_path) as conn:
        counts = apply_actions(conn, batch_id=batch_id)
    typer.echo(f"Applied: {counts['completed']} completed, {counts['failed']} failed")
    if counts["failed_ids"]:
        typer.echo("Failed action IDs:")
        for action_id in counts["failed_ids"]:
            typer.echo(f"- {action_id}")


@plan_app.command("set-goal")
def set_goal(
    db_path: Path = typer.Option(..., "--db", help="Path to SQLite DB"),
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

    with connect(db_path) as conn:
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
    db_path: Path = typer.Option(..., "--db", help="Path to SQLite DB"),
    user: str = typer.Option(..., "--user"),
    date_from: date | None = typer.Option(None, "--from"),
    date_to: date | None = typer.Option(None, "--to"),
) -> None:
    start_date = date_from or date.today()
    end_date = date_to or (start_date + timedelta(days=7))

    with connect(db_path) as conn:
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
    db_path: Path = typer.Option(..., "--db", help="Path to SQLite DB"),
    user: str = typer.Option(..., "--user"),
    weeks: int = typer.Option(4, "--weeks"),
    start: date = typer.Option(date.today(), "--start"),
    reference_plan: str | None = typer.Option(None, "--reference-plan"),
    tags: list[str] = typer.Option(None, "--tag", help="Filter templates by tag (repeatable)"),
    sessions_per_week: int | None = typer.Option(None, "--sessions-per-week"),
    out: Path = typer.Option(..., "--out", help="Proposal JSON output path"),
) -> None:
    tags = tags or []
    with connect(db_path) as conn:
        user_rows = query(conn, "SELECT user_id FROM app_user WHERE name = ?", (user,))
        if not user_rows:
            raise typer.Exit(f"User not found: {user}")

        if sessions_per_week is None:
            goal_rows = query(conn, "SELECT sessions_per_week FROM user_goal WHERE user_id = ?", (user_rows[0]["user_id"],))
            if goal_rows:
                sessions_per_week = goal_rows[0]["sessions_per_week"]

        if not sessions_per_week:
            raise typer.Exit("sessions_per_week required (set goal or pass --sessions-per-week)")

        if reference_plan:
            tags.append(f"plan:{reference_plan}")

        templates = _select_template_names(conn, tags)
        if not templates:
            raise typer.Exit("No templates found for selection")

    target_days = _session_days_map(int(sessions_per_week))
    total_days = weeks * 7

    days = []
    idx = 0
    for day_offset in range(total_days):
        current = start + timedelta(days=day_offset)
        if current.weekday() not in target_days:
            continue
        template_name = templates[idx % len(templates)]
        idx += 1
        days.append({"date": current, "template": template_name})

    proposal = proposal_from_days(user=user, days=days, title="generated plan", source_ref="generator_v1")
    write_proposal(proposal, out)
    typer.echo(f"Proposal written: {out}")