---
title: Schema & migrations
status: stable
date: 2026-04-17
purpose: "How schema changes flow through the two SQLite stores (server + device), with the complete-cutover philosophy that governs this repo."
covers:
  - server/db/migrations/
  - app/
  - schema/
  - tests/contract/
---

# Schema & migrations

This repo has **two SQLite stores** that must stay identical:

1. **Server** — Python + FastAPI + SQLite at `server/db/workout.db`. Schema evolves via numbered SQL migrations in `server/db/migrations/`.
2. **Device** — SwiftData on the iPhone/Watch. Schema evolves via SwiftData's `VersionedSchema` with migration stages.

**Schema parity is an invariant.** If they drift, sync breaks. The contract tests in `tests/contract/` fail the build when they drift.

## Single-user cutover philosophy

One user (Eric) uses this system. No legacy data to migrate from a previous user base, no old app versions in the wild. This simplifies migrations dramatically:

- **No backwards-compatible DB layouts.** The server and the phone in Eric's pocket run the exact same schema version at all times.
- **No parallel old+new code paths.** When a field is renamed, both sides rename in the same commit.
- **No multi-phase rollouts.** Migrations land complete; the app is rebuilt; the server is restarted. Downtime is acceptable (Eric isn't working out during the deploy).
- **Data preservation is explicit per cutover.** Plans, exercises,
  alternatives, and `user_parameters` are re-pushable by Claude. Local
  set_logs are normally the only data worth preserving, but a cutover may
  explicitly treat current local/server workouts as disposable QA data. Do not
  silently choose either preservation or deletion; the owning spec must say.

## Server migrations

**Format:** Numbered SQL files in `server/db/migrations/`:

```
server/db/migrations/
├── 001_initial.sql
├── 002_add_tempo_to_prescription.sql     # example
└── 003_make_user_parameters_append_only.sql
```

**Rules:**

- Filenames: `NNN_<snake_case_description>.sql`. Three-digit zero-padded number, monotonic.
- Idempotent: every migration wraps DDL in conditional statements (`CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`, `ALTER TABLE ADD COLUMN` only if absent — SQLite lacks `IF NOT EXISTS` on `ALTER TABLE`, so check `PRAGMA table_info` in the runner).
- Append-only: **never edit a merged migration**. Fix-forward with a new one.
- Applied in order by the migration runner at server startup. A `schema_migrations` table records what's been applied.

**Tool choice:** hand-rolled SQL + a small Python runner in `server/workoutdb_server/migrations.py`. No Alembic — this is a single-user system; autogenerate and version branches aren't worth the dependency. If the migration list exceeds ~50 files or a second developer joins, revisit.

**Adding a migration:**

1. Create `server/db/migrations/NNN_<description>.sql`.
2. Write the migration idempotently.
3. Run the server; the runner applies it.
4. Confirm with `sqlite3 server/db/workout.db '.schema'`.

## SwiftData migrations (app side)

SwiftData uses `VersionedSchema` with migration stages.

**Pattern:**

```swift
enum WorkoutSchemaV1: VersionedSchema { … }
enum WorkoutSchemaV2: VersionedSchema { … }

enum WorkoutMigrationPlan: SchemaMigrationPlan {
    static var schemas: [VersionedSchema.Type] { [WorkoutSchemaV1.self, WorkoutSchemaV2.self] }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: WorkoutSchemaV1.self, toVersion: WorkoutSchemaV2.self)]
    }
}
```

**Lightweight vs custom stages:**

- **Lightweight** — add/remove optional properties, rename with `@Attribute(originalName:)`, add relationships. No data touched. Use these whenever possible.
- **Custom** — data needs transforming, required properties added, enum values changed. Implement with a `MigrationStage.custom` closure that reads, transforms, and writes model instances. Slower, riskier, but unavoidable for some changes.

**Set_log preservation or reset is the hard decision.** If the owning spec
requires preserving existing set_logs and a custom stage can't cleanly transform
them, the migration must:

1. Export set_logs to a JSON file on device before the stage runs.
2. Apply the stage.
3. Re-import transformed set_logs.
4. On success, delete the backup. On failure, restore from it.

The app should refuse to launch if a preservation migration fails — don't
silently drop data. If the owning spec permits a reset, the migration or
operator runbook must make the destructive reset explicit.

## The cutover flow (every schema change)

A schema change is a single atomic commit that touches all of the below:

1. **Server SQL migration** — `server/db/migrations/NNN_<change>.sql`
2. **Server models** — `server/workoutdb_server/models.py` (SQLAlchemy + Pydantic)
3. **Server API** — any affected route in `server/workoutdb_server/api/`
4. **SwiftData model** — bump `WorkoutSchemaVN → WorkoutSchemaV(N+1)` in `app/`; add stage to `WorkoutMigrationPlan`
5. **Contract test** — update `tests/contract/` to pin the new shape on both sides
6. **Spec** — update `docs/specs/v2-architecture.md` entity table
7. **Schema file** — if `schema/` is populated (OpenAPI or similar), regenerate

No partial commits. If one piece can't ship, nothing ships.

## Version handshake

The server exposes its current schema version at `GET /api/version`. The app checks this at every sync attempt.

- **Server schema version > app schema version** → app refuses to sync, prompts user to update the app. (In practice: Eric rebuilds the app in Xcode.)
- **App schema version > server schema version** → app refuses to sync, tells the user to update the server. (In practice: Eric SSHs to the home server and pulls + restarts.)
- **Equal** → proceed.

No "graceful degradation" or "partial-schema sync." Single-user means we can afford strict equality.

## Recovering when things go sideways

If a preservation migration lands broken and set_logs are at risk:

1. **Stop the app** from syncing (airplane mode works).
2. **Find the SwiftData store** in the app container and copy it off device.
3. **Export set_logs to JSON** using a one-off Swift script (or a debug endpoint we add for this).
4. **Revert the migration** on the server (drop and rebuild from a backup, or write a reverse-direction migration NNN+1).
5. **Roll back the app** to a build with the previous schema version.
6. **Re-import set_logs.**

Plans, exercises, and user_parameters can be wiped and re-pushed by Claude — they're recoverable by conversation, not by backup.

## Not yet in scope

- **Scheduled server backups** (sqlite3 dump on cron) — add before any real logging happens.
- **Client-side set_log export endpoint** for recovery — add when first non-trivial schema migration ships.
- **Migration preview tooling** (show diff between two schema versions) — probably unnecessary; the numbered SQL files are already a readable diff.

## See also

- `docs/specs/v2-architecture.md` — what the schema actually is
- `tests/contract/` — the cross-stack parity guardrails
- `server/README.md` — server dev loop
- `app/README.md` — app dev loop
