from __future__ import annotations

from pathlib import Path

import typer

from .db import connect, query
from .migrations import apply_migrations, pending_migrations
from .yaml_import import import_yaml
from .yaml_io import validate_yaml

app = typer.Typer(add_completion=False)
plan_app = typer.Typer(add_completion=False)


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


app.add_typer(plan_app, name="plan")


if __name__ == "__main__":
    app()
