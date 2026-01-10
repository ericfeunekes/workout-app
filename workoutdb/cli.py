from __future__ import annotations

from datetime import date, datetime, time, timedelta
from pathlib import Path
import json
import uuid

import typer

from .calendar_api import build_event_payload, list_calendars, upsert_events
from .config import ConfigError, load_config
from .db import connect, query
from .extracted_json_import import import_extracted_json_dir
from .migrations import apply_migrations, pending_migrations
from .yaml_import import import_intents, import_yaml
from .yaml_io import validate_yaml

app = typer.Typer(add_completion=False)
plan_app = typer.Typer(add_completion=False)
calendar_app = typer.Typer(add_completion=False)
intent_app = typer.Typer(add_completion=False)


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
        _fail("sessions_per_week must be between 1 and 7")
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
        _fail(f"User not found: {user}")
    return rows[0]["user_id"]


def _fetch_planned_workouts(conn, user_id: str, start_date: date, end_date: date):
    return query(
        conn,
        """
        SELECT pw.planned_id, pw.date, pw.status, pw.notes, pw.start_time, pw.duration_min,
               pw.calendar_id, pw.calendar_event_id, pw.calendar_html_link,
               t.name AS template_name
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
                "planned_id": row["planned_id"],
                "date": row["date"],
                "title": template,
                "status": status,
                "notes": notes,
                "start_time": row["start_time"],
                "duration_min": row["duration_min"],
                "calendar_id": row["calendar_id"],
                "calendar_event_id": row["calendar_event_id"],
            }
        )
    return formatted

def _upsert_planned_workout(
    conn,
    user_id: str,
    day: date,
    template_id: str | None,
    gen: str,
    start_time_value: time | None,
    duration_min: int | None,
) -> None:
    conn.execute(
        """
        INSERT INTO planned_workout (
            planned_id, user_id, date, template_id, status, notes, generated_by,
            start_time, duration_min
        ) VALUES (?, ?, ?, ?, 'planned', NULL, ?, ?, ?)
        ON CONFLICT(user_id, date) DO UPDATE SET
            template_id = excluded.template_id,
            generated_by = excluded.generated_by,
            start_time = COALESCE(excluded.start_time, planned_workout.start_time),
            duration_min = COALESCE(excluded.duration_min, planned_workout.duration_min)
        """,
        (
            _new_id(),
            user_id,
            day.isoformat(),
            template_id,
            gen,
            start_time_value.isoformat() if start_time_value else None,
            duration_min,
        ),
    )

def _parse_start_time(value: str | None) -> time | None:
    if value is None:
        return None
    try:
        return time.fromisoformat(value)
    except ValueError as exc:
        _fail("start_time must be in HH:MM or HH:MM:SS format")

def _validate_date_range(start_date: date, end_date: date) -> None:
    if end_date < start_date:
        _fail("date range invalid: --to must be on or after --from")

def _local_tzinfo():
    return datetime.now().astimezone().tzinfo

def _load_config(path: Path | None):
    try:
        return load_config(path)
    except ConfigError as exc:
        _fail(str(exc))


def _fail(message: str) -> None:
    typer.echo(message, err=True)
    raise typer.Exit(1)


def _seed_intents(conn) -> int:
    intents = [
        ("strength", None, "Primary strength intent"),
        ("hypertrophy", None, "Muscle growth intent"),
        ("conditioning", None, "Mixed intensity conditioning intent"),
        ("endurance", None, "Sustained aerobic intent"),
        ("skill", None, "Skill or technique focus"),
        ("mobility", None, "Mobility or range of motion focus"),
        ("recovery", None, "Low intensity recovery focus"),
        ("max_strength", "strength", "High load, low reps"),
        ("strength_endurance", "strength", "Moderate load, higher reps"),
        ("pump", "hypertrophy", "High-rep metabolic focus"),
        ("mechanical_tension", "hypertrophy", "Moderate reps, heavier loads"),
        ("vo2max", "conditioning", "High-intensity interval focus"),
        ("aerobic_base", "endurance", "Zone 2 / base aerobic"),
        ("threshold", "endurance", "Lactate threshold focus"),
    ]

    created = 0
    name_to_id: dict[str, str] = {}
    rows = query(conn, "SELECT intent_id, name FROM intent_taxonomy WHERE deleted = 0")
    for row in rows:
        name_to_id[row["name"]] = row["intent_id"]

    for name, parent, desc in intents:
        if name in name_to_id:
            continue
        parent_id = None
        if parent:
            parent_id = name_to_id.get(parent)
            if parent_id is None:
                parent_id = _new_id()
                conn.execute(
                    "INSERT INTO intent_taxonomy (intent_id, parent_intent_id, name, description) VALUES (?, ?, ?, ?)",
                    (parent_id, None, parent, None),
                )
                name_to_id[parent] = parent_id
                created += 1
        intent_id = _new_id()
        conn.execute(
            "INSERT INTO intent_taxonomy (intent_id, parent_intent_id, name, description) VALUES (?, ?, ?, ?)",
            (intent_id, parent_id, name, desc),
        )
        name_to_id[name] = intent_id
        created += 1
    return created


@intent_app.command("list")
def intent_list(db: Path = typer.Option(..., "--db", help="Path to SQLite DB")) -> None:
    with connect(db) as conn:
        rows = query(
            conn,
            """
            SELECT intent_id, parent_intent_id, name, description
            FROM intent_taxonomy
            WHERE deleted = 0
            ORDER BY name
            """,
        )
    if not rows:
        typer.echo("No intents found")
        return

    intents: dict[str, dict[str, str | None]] = {}
    children: dict[str, list[str]] = {}
    roots: list[str] = []
    for row in rows:
        intent_id = row["intent_id"]
        parent_id = row["parent_intent_id"]
        intents[intent_id] = {
            "name": row["name"],
            "description": row["description"],
            "parent_id": parent_id,
        }
        if parent_id:
            children.setdefault(parent_id, []).append(intent_id)
        else:
            roots.append(intent_id)

    def render_intent(intent_id: str, indent: str) -> None:
        intent = intents[intent_id]
        typer.echo(f"{indent}- {intent['name']}")
        if intent["description"]:
            typer.echo(f"{indent}  {intent['description']}")
        for child_id in sorted(children.get(intent_id, []), key=lambda cid: intents[cid]["name"]):
            render_intent(child_id, f"{indent}  ")

    for root_id in sorted(roots, key=lambda rid: intents[rid]["name"]):
        render_intent(root_id, "")


@intent_app.command("seed")
def intent_seed(
    db: Path = typer.Option(..., "--db", help="Path to SQLite DB"),
    path: Path | None = typer.Argument(None, help="Path to YAML file"),
) -> None:
    if path:
        try:
            created = import_intents(db, path)
        except ValueError as exc:
            typer.echo(str(exc), err=True)
            raise typer.Exit(1) from exc
        typer.echo(f"Intents created: {created}")
        return

    with connect(db) as conn:
        created = _seed_intents(conn)
        conn.commit()
    typer.echo(f"Intents created: {created}")



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


@app.command("import-extracted-json")
def import_extracted_json(
    db: Path = typer.Option(..., "--db", help="Path to SQLite DB"),
    input_dir: Path = typer.Option(..., "--input", help="Directory of extracted JSON files"),
    source_title: str = typer.Option("STC workouts 2025", "--source-title"),
    source_author: str | None = typer.Option("Synergy Training Centre", "--source-author"),
    source_kind: str = typer.Option("file_import", "--source-kind"),
    source_original_url: str | None = typer.Option(None, "--source-original-url"),
    source_license_note: str | None = typer.Option(None, "--source-license-note"),
    overwrite_templates: bool = typer.Option(False, "--overwrite-templates"),
) -> None:
    db.parent.mkdir(parents=True, exist_ok=True)
    apply_migrations(db)
    try:
        result = import_extracted_json_dir(
            db_path=db,
            input_dir=input_dir,
            source_title=source_title,
            source_author=source_author,
            source_kind=source_kind,
            source_original_url=source_original_url,
            source_license_note=source_license_note,
            overwrite_templates=overwrite_templates,
        )
    except ValueError as exc:
        typer.echo(str(exc), err=True)
        raise typer.Exit(1) from exc

    typer.echo(f"Source created: {result.source_created}")
    typer.echo(f"Pages seen: {result.pages_seen} (invalid: {result.pages_invalid})")
    typer.echo(f"Workouts seen: {result.workouts_seen}")
    typer.echo(
        f"Raw workouts created/updated: {result.raw_workouts_created}/{result.raw_workouts_updated}"
    )
    typer.echo(
        "Templates created/linked/overwritten: "
        f"{result.templates_created}/{result.templates_linked_existing}/{result.templates_overwritten}"
    )
    typer.echo(f"Blocks created: {result.blocks_created}")
    typer.echo(f"Items created: {result.items_created}")
    typer.echo(f"Exercises created: {result.exercises_created}")


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
    typer.echo(f"Intents created: {result.intents_created}")
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
        _fail("sessions_per_week must be between 1 and 7")

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
    _validate_date_range(start_date, end_date)

    with connect(db) as conn:
        user_id = _get_user_id(conn, user)
        plan_rows = _fetch_planned_workouts(conn, user_id, start_date, end_date)

    if not plan_rows:
        typer.echo("No planned workouts found")
        return
    for row in _format_plan_rows(plan_rows):
        time_suffix = ""
        if row["start_time"] and row["duration_min"]:
            time_suffix = f" @ {row['start_time']} ({row['duration_min']}m)"
        typer.echo(f"{row['date']}: {row['title']} [{row['status']}] {time_suffix}".rstrip())
        if row["notes"]:
            typer.echo(f"  {row['notes']}")


@calendar_app.command("list")
def calendar_list(
    config: Path | None = typer.Option(None, "--config", help="Path to config.toml"),
) -> None:
    cfg = _load_config(config)
    calendars = list_calendars(cfg)
    if not calendars:
        typer.echo("No calendars found")
        return
    for item in calendars:
        summary = item.get("summary") or ""
        cal_id = item.get("id") or ""
        access = item.get("accessRole") or ""
        primary = " (primary)" if item.get("primary") else ""
        typer.echo(f"- {summary}{primary}")
        typer.echo(f"  id: {cal_id}")
        if access:
            typer.echo(f"  access: {access}")


@plan_app.command("push-calendar")
def push_calendar(
    db: Path = typer.Option(..., "--db", help="Path to SQLite DB"),
    user: str = typer.Option(..., "--user", help="User name"),
    date_from: datetime | None = typer.Option(None, "--from"),
    date_to: datetime | None = typer.Option(None, "--to"),
    calendar_id: str | None = typer.Option(None, "--calendar-id"),
    config: Path | None = typer.Option(None, "--config", help="Path to config.toml"),
    dry_run: bool = typer.Option(True, "--dry-run/--no-dry-run"),
) -> None:
    start_date = date_from.date() if date_from else date.today()
    end_date = date_to.date() if date_to else (start_date + timedelta(days=7))
    _validate_date_range(start_date, end_date)

    with connect(db) as conn:
        user_id = _get_user_id(conn, user)
        plan_rows = _fetch_planned_workouts(conn, user_id, start_date, end_date)

    if not plan_rows:
        typer.echo("No planned workouts found")
        return

    cfg = _load_config(config)
    target_calendar_id = calendar_id or cfg.calendar.default_id
    if not target_calendar_id:
        _fail("calendar-id required (set calendar.default_id in config or pass --calendar-id)")

    events = []
    missing_times = []
    for row in _format_plan_rows(plan_rows):
        if row["title"] == "Rest":
            continue
        if not row["start_time"] or not row["duration_min"]:
            missing_times.append(f"{row['date']} {row['title']}")
            continue
        start_time = _parse_start_time(row["start_time"])
        events.append(
            {
                "planned_id": row["planned_id"],
                "event_id": row["calendar_event_id"],
                "payload": build_event_payload(
                    summary=row["title"],
                    workout_date=date.fromisoformat(row["date"]),
                    start_time=start_time,
                    duration_min=int(row["duration_min"]),
                    description=row["notes"] or None,
                    tzinfo=_local_tzinfo(),
                ),
            }
        )

    if missing_times:
        typer.echo("Missing start_time/duration_min for:")
        for item in missing_times:
            typer.echo(f"- {item}")
        _fail("Add times to planned workouts before pushing to calendar")

    if dry_run:
        typer.echo("Calendar events preview:")
        typer.echo(json.dumps(events, indent=2, ensure_ascii=True))
        return
    with connect(db) as conn:
        results = upsert_events(cfg, calendar_id=target_calendar_id, events=events)
        for result in results:
            if result["status"] == "failed":
                typer.echo(f"Failed: {result['planned_id']} ({result['error']})")
                continue
            response = result["response"] or {}
            conn.execute(
                """
                UPDATE planned_workout
                SET calendar_id = ?, calendar_event_id = ?, calendar_html_link = ?
                WHERE planned_id = ?
                """,
                (
                    target_calendar_id,
                    result["event_id"],
                    response.get("htmlLink"),
                    result["planned_id"],
                ),
            )
        conn.commit()
    typer.echo("Calendar push complete")

@plan_app.command("generate")
def plan_generate(
    db: Path = typer.Option(..., "--db", help="Path to SQLite DB"),
    user: str = typer.Option(..., "--user", help="User name"),
    weeks: int = typer.Option(4, "--weeks"),
    start: datetime = typer.Option(datetime.now(), "--start"),
    reference_plan: str | None = typer.Option(None, "--reference-plan"),
    tag: list[str] = typer.Option(None, "--tag", help="Filter templates by tag (repeatable)"),
    sessions_per_week: int | None = typer.Option(None, "--sessions-per-week"),
    start_time: str | None = typer.Option(None, "--start-time", help="HH:MM time for all workouts"),
    duration_min: int | None = typer.Option(None, "--duration-min"),
) -> None:
    tag = tag or []
    start_date = start.date()
    with connect(db) as conn:
        user_id = _get_user_id(conn, user)
        start_time_value = _parse_start_time(start_time)
        if (start_time_value is None) ^ (duration_min is None):
            _fail("start_time and duration_min must be provided together")
        if duration_min is not None and duration_min <= 0:
            _fail("duration_min must be > 0")

        if sessions_per_week is None:
            goal_rows = query(conn, "SELECT sessions_per_week FROM user_goal WHERE user_id = ?", (user_id,))
            if goal_rows:
                sessions_per_week = goal_rows[0]["sessions_per_week"]

        if not sessions_per_week:
            _fail("sessions_per_week required (set goal or pass --sessions-per-week)")

        if reference_plan:
            tag.append(f"plan:{reference_plan}")

        templates = _select_template_names(conn, tag)
        if not templates:
            _fail("No templates found for selection")

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
            _upsert_planned_workout(
                conn,
                user_id,
                current,
                template_id,
                "generator_v1",
                start_time_value,
                duration_min,
            )

    typer.echo("Plan generated")


plan_app.add_typer(calendar_app, name="calendar")
app.add_typer(plan_app, name="plan")
app.add_typer(intent_app, name="intent")


if __name__ == "__main__":
    app()
