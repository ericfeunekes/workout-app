# WorkoutDB — Agent Instructions

Monorepo for a workout system built on **"dumb app, smart conversation"**. Read `docs/specs/v2-architecture.md` in full before any non-trivial work — the philosophy and data model are load-bearing.

See `docs/AGENTS.md` for the docs navigator and `docs/ARCHITECTURE.md` for the system map.

## Project Overview

- `server/` — Python + FastAPI + SQLite home server. Schema, API endpoints, sync.
  - `workoutdb_server/` — Python package
  - `db/migrations/` — idempotent SQL migrations
- `app/` — SwiftData iOS app. The "dumb" client: show, time, log.
- `schema/` — shared schema definitions between server and app (not yet populated)
- `docs/` — architecture, testing contract, target spec (see `docs/AGENTS.md`)
- `tests/` — server tests (`tests/server/`) and cross-stack contracts (`tests/contract/`); iOS tests live alongside the Xcode target in `app/`
- `scratch/` — ephemeral multi-unit work (gitignored)

## Workflows

See `docs/WORKFLOW.md` for the full lifecycle (idea → spec → plan → implement → verify → close → deploy). Quick pointers:

### Starting work
- Classify the change: trivial / scoped / non-trivial. Non-trivial → `skill:interview` or update a spec before coding.
- Read `docs/specs/v2-architecture.md` (target architecture, accepted) and `docs/ARCHITECTURE.md` (system map at a glance).
- Read the affected area's README (`server/README.md`, `app/README.md`, `schema/README.md`).
- Schema change? Read `docs/MIGRATIONS.md` before touching entity definitions.

### During work
- Schema change → follow the seven-step cutover flow in `docs/MIGRATIONS.md`.
- New API endpoint → route in `server/workoutdb_server/api/`, models updated, test in `tests/server/`, `docs/ARCHITECTURE.md` updated if sync story changes.
- New timing mode → extend enum in server + SwiftData + spec; app timer engine handles it.
- Bug found → hypothesis-driven debugging before patching.

### Finishing work
- Follow `docs/runbooks/closeout.md` — the per-change checklist enforces the cutover philosophy.
- Pre-push hook runs `pytest` automatically; install once with `pre-commit install --hook-type pre-commit --hook-type pre-push`.

### After context loss
- Re-read this file, `docs/WORKFLOW.md`, and `docs/specs/v2-architecture.md`.
- Check `docs/plans/active/` (if any) for in-flight work.

## Review workflow — Codex is the investigator/sweeper/reviewer, lead Claude synthesizes

**Reviews, sweeps, and investigations are done by Codex (a different model), not by another Claude subagent.** The three roles are fixed:

- **Implementation = Claude subagent** (dispatched from the main thread).
- **Review / sweep / investigation = Codex** (via `cxd task --sandbox read-only --detach`).
- **Synthesis = the lead Claude agent in the main conversation.** Synthesis is NOT delegated to a spawned subagent — the lead reads Codex findings directly, filters false-positives, and dispatches the next fix-it round from the main thread.

Same-model review misses the same blind spots that produced the bug. That's the load-bearing reason for the split.

The loop for every non-trivial unit of work:

1. Claude implementer subagent writes the fix.
2. Codex review fires via `cxd task --sandbox read-only --detach --cwd $PWD --service-name review-<domain> --effort medium -f <prompt-file>`.
3. **Lead Claude synthesizes in the main thread** — reads Codex findings, filters false-positives, dispatches a Claude fix-it subagent with the real findings inline.
4. Repeat step 2. Loop until Codex returns clean.

**Sweeping the codebase state to find new issues uses Codex, not Claude subagents.** Same goes for hypothesis-driven bug investigations and adversarial reviews — different-model + read-only sandbox is the pattern. Synthesis of Codex findings always happens in the main conversation.

Working template in `scratch/codex-reviews/`: `_template-header.md` + `_session-context.md` are the methodology baseline; per-domain prompts cite focus files + questions + hazards; `_dispatch.sh` fires N in parallel; `_monitor.sh` polls. Pull findings via `cxd thread read <id> --include-turns --json`.

Same-model Claude-reviews are acceptable only for trivial scoped fixes, pure doc edits, or config tweaks already guarded by automated checks.

See `docs/WORKFLOW.md` § "The implementer / reviewer cycle" for the full story.

## Module Coordination

- **Schema change** touches: `server/workoutdb_server/models.py` (SQLAlchemy ORM), `server/db/migrations/NNN_*.sql`, `server/workoutdb_server/api/schemas.py` (Pydantic), `schema/Sources/WorkoutDBSchema/*.swift` (Swift DTOs), regenerated `schema/openapi.json`, SwiftData models in `app/` (when the Xcode project exists), contract tests in `tests/contract/`, and the data model section of `docs/specs/v2-architecture.md`. See `docs/MIGRATIONS.md` for the cutover flow.
- **Sync protocol change** touches: `server/workoutdb_server/api/sync.py`, the iOS sync manager in `app/`, `schema/openapi.json`, the "Sync model" section of `docs/specs/v2-architecture.md`, and contract tests.
- **New timing mode** touches: `TimingMode` in `schema/Sources/WorkoutDBSchema/Enums.swift`, the `Literal` in `api/schemas.py`, the SQL `CHECK` constraint in `001_initial.sql` (add via new migration — never edit), the contract test in `tests/contract/test_swift_schema_parity.py`, the timing modes table in `docs/specs/v2-architecture.md`, and the app's timer engine.
- **User parameter key added** is data-only — no code change needed unless the app is supposed to interpret it. If the app must interpret it (e.g. new `percent_1rm` variant), update the resolver in `app/` and document the key.

## Build & Verify

```bash
# One-time setup after cloning
uv sync --extra dev
pre-commit install --hook-type pre-commit --hook-type pre-push
cp .env.example .env      # then fill in WORKOUTDB_BEARER_TOKEN

# Server
uv run pytest             # full test suite
uv run ruff check .       # lint
uv run ruff format .      # format
uv run uvicorn workoutdb_server.main:app --reload   # run locally

# App
# Xcode project to be added under app/ — build + test via Xcode
```

**CI** (`.github/workflows/ci.yml`): Linux only, server tests + ruff on push and PR. iOS build/test deferred until the app exists and we revisit public-vs-private repo. See `docs/WORKFLOW.md` § "CI scope" for the budget math.

**Secrets**: `.env` (gitignored) holds the bearer token and DB path. Server loads via `pydantic-settings` with `env_prefix="WORKOUTDB_"`. The same bearer token is pasted into the iOS app's first-run setup — server and app share one secret, Tailscale handles network-layer trust.

## Invariants

### System philosophy

- **Dumb app, smart conversation.** The app never does programming logic, exercise selection, periodization, or progression. All of that lives in Claude conversations and arrives as data via the server. If a change adds "app reasons about X", push back — X probably belongs in `user_parameters` or in conversation.
- **UUIDs everywhere, no auto-increment IDs.** Every entity has a `UUID` primary key so sync merges are trivial.
- **Direction-based sync, no conflict resolution.** Plans flow server → app; results flow app → server. Never both for the same field.
- **Schema parity between server and app.** If the Python model changes and the SwiftData model doesn't (or vice versa), sync breaks. Contract tests enforce this.
- **`prescription_json` and `timing_config_json` are JSON blobs by design.** New prescription shapes and timing configs don't require schema changes — add the shape to the spec and the app reader, not to the table.
- **Claude owns exercise IDs.** The server does not canonicalize on exercise name. Claude lists `/api/exercises` at conversation start and reuses UUIDs for recurring exercises.
- **`user_parameters` is append-only.** Every push inserts a new row. Overwrites would destroy history; history is load-bearing for longitudinal analysis.
- **App must execute a fully-pulled workout with zero network calls.** Offline-first is not optional — cellular at the gym, travel, and hotel WiFi fail too often.

### Development philosophy (single-user, no legacy)

This repo has one user (Eric) and one prod deployment (also Eric). There is no "existing user base" to migrate, no backwards compatibility to preserve, and no deprecation curve to honor. Act accordingly:

- **Complete cutovers only.** When something changes, change it everywhere in one commit — server, app, schema, tests, docs. No feature flags, no legacy paths, no parallel old+new codepaths, no "one sprint to deprecate X" periods. If you find yourself writing an adapter between old-shape and new-shape code, you're doing it wrong.
- **Resolve nitpicks at the time.** Naming is off → rename it now. Tiny inconsistency → fix it now. We do not carry a "small stuff to clean up later" list. Technical debt accumulated here will outlive the short-term pain of resolving it immediately.
- **No legacy fallback code.** v1 (Python CLI, YAML, Google Calendar, intents, muscle/movement/equipment tables) is gone. Don't resurrect any of it. If you see a code path "in case the old thing is still around," delete it.
- **Local data is the only preservation constraint.** Workout logs on Eric's phone are the one thing that must survive schema changes. Everything else (plans, exercises, alternatives, user_parameters on the server) can be re-pushed by Claude. Migrations may export + transform + re-import local data, but must not lose it.
- **Schema changes are always cutovers.** Server migration + SwiftData version bump + API update + contract test + spec update all ship together. App and server schema versions are always identical in the running system — see `docs/MIGRATIONS.md` for the flow.

### Migrations

- **Migrations are append-only and idempotent.** `server/db/migrations/NNN_*.sql` — never edit a merged migration.
- **Every schema change is a coordinated cutover** across server migration, SwiftData versioned schema, API models, contract test, and the spec. See `docs/MIGRATIONS.md` for the detailed flow.
- **Local set_logs are the only authoritative client data.** SwiftData migrations use lightweight stages where possible; when a stage can't be lightweight, export → transform → re-import is explicit and documented in the migration.

### Architectural enforcement

- **Boundaries are enforced at lint time, not at review time.** Python server boundaries are checked by `import-linter` contracts in `pyproject.toml` (run `uv run lint-imports`). Contracts run in pre-push and CI.
- **New architectural boundaries require new contracts.** Adding a module or package? Add an import-linter contract in the same commit. If reaching for an import that would violate an existing contract, extract the shared logic into the right layer — do not loosen the contract. See `docs/WORKFLOW.md` § "Architectural enforcement".

## Agent harness (local, untracked)

`.codex/`, `.xskills/`, `.claude/settings.local.json` are agent-local and gitignored. `scratch/` is for ephemeral multi-unit work.
