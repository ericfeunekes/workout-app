# Home Server

Python + FastAPI + SQLite. The exchange layer between Claude (who writes plans) and the iOS app (which executes them and logs results).

See `docs/specs/v2-architecture.md` for the API contract and `docs/ARCHITECTURE.md` for the system map.

## Layout

- `workoutdb_server/`
  - `config.py` — `pydantic-settings` (env prefix `WORKOUTDB_`)
  - `logging_setup.py` — JSON logs + `RequestIdMiddleware`
  - `db.py` — SQLAlchemy engine/session; FK enforcement on every connection
  - `models.py` — SQLAlchemy 2.0 ORM for all entities; mirrors SwiftData in `app/`
  - `migrations.py` — numbered-SQL runner, idempotent
  - `main.py` — FastAPI app, lifespan hooks, router mounting
  - `api/` — route modules (`version`, `exercises`, `user_parameters`, `workouts`, `sync`) + `deps.py` (auth, db session) + `schemas.py` (Pydantic)
  - `sync/` — future sync orchestration logic
- `db/migrations/NNN_*.sql` — append-only SQL migrations

## Dev loop

```bash
# From the repo root:
uv sync --extra dev
cp .env.example .env     # fill in WORKOUTDB_BEARER_TOKEN
pre-commit install --hook-type pre-commit --hook-type pre-push

# Run locally
uv run uvicorn workoutdb_server.main:app --reload

# Tests
uv run pytest              # server + contract
uv run ruff check .
uv run lint-imports
```

## Invariants enforced here

- **Layered imports.** `import-linter` contracts in `pyproject.toml` forbid `api/` from being imported by `db/models/migrations/config`. `sync/` is a peer of `api/`, not a caller. See `docs/WORKFLOW.md` § "Architectural enforcement".
- **No canonicalization on exercise name.** Claude owns exercise IDs; the server upserts by id only.
- **`user_parameters` is append-only.** Every POST inserts a new row. Latest-per-key is a query, not an update.
- **Migrations are idempotent.** Re-running the runner is safe. See `docs/MIGRATIONS.md`.

## Deploy

See `docs/infrastructure/home-server.md` for the one-time setup + ongoing deploy flow.
