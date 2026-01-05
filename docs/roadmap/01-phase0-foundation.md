# Phase 0 — Foundation (DB + CLI) ✅ highest detail

## Objective
Create a stable local data core: SQLite schema, migrations, and a CLI that makes the DB usable immediately.

## Recommended tech (minimal, python-first)
- Python 3.11+
- SQLite
- `typer` for CLI (fast to ship)
- `pydantic` for config + JSON validation (optional but helpful)
- No ORM required initially (raw SQL is fine)

## Schema note (future sync)
- Use UUIDs for all primary keys (TEXT or BLOB) to avoid merge conflicts later.

## Tasks (implementation order)
### 0.1 Repo bootstrap
- [ ] Create folders: `db/`, `db/migrations/`, `workoutdb/`, `scripts/`, `tests/`, `docs/`
- [ ] Add `pyproject.toml` with dependencies and a `workoutdb` console script entrypoint

### 0.2 Database schema (v0)
- [ ] Start from your current schema (exercises, muscles, templates, sessions)
- [ ] Add **source/provenance** tables (see Phase 1)
- [ ] Add **planning/schedule** tables (see Phase 3)
- [ ] Add **generic attachments** tables for stimulus/metrics (Phase 4; safe to add now even if unused)

### 0.3 Migration runner (very small)
- [ ] Use numbered SQL files in `db/migrations/NNN_description.sql`
- [ ] Create `schema_migrations` table to track applied migrations
- [ ] CLI `migrate` applies new migrations in order
- [ ] CLI `init-db` creates DB + runs migrations

Acceptance:
- `init-db --db path/to/workouts.db` works from empty folder.
- `migrate` is idempotent.

### 0.4 DB access layer
- [ ] `workoutdb/db.py` with:
  - connect(db_path)
  - execute/query helpers
  - transaction context manager

### 0.5 Minimal CLI scaffolding
Commands (names can vary, but keep these capabilities):
- [ ] `init-db`
- [ ] `migrate`
- [ ] `doctor` (checks schema version, can open DB, lists counts)

Acceptance:
- Running `doctor` prints basic stats: # exercises, # templates, # sessions, # planned workouts.

## Risk controls
- Keep schema changes additive whenever possible.
- Never block logging because catalog metadata is missing.
