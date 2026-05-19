---
title: Cutover — complete primitive contract with disposable QA data
status: accepted — active cutover contract with residual runtime followups
last_reviewed: 2026-05-18
parent: ../primitives-data-model.md
purpose: How the primitives data model lands and how residual runtime cutover work stays on the no-legacy primitive contract. Because the repo is single-user dev with no production compatibility constraint, current local/server QA workout data may be reset or removed by recreating the database, and old-shape acceptance windows are not allowed.
---

# Cutover

## Why this is short

The repo is single-user dev. There is no existing user base to migrate and no backwards compatibility window to honor. The server database can be deleted and recreated on the next deployment, then rehydrated when Claude pushes workouts in the primitive shape.

Current local/server workouts and logs are QA data, not authoritative training
history. They may be deleted during this cutover. Reset does not mean keeping
the old schema, accepting old payloads, preserving rows, or supporting a legacy
execution path. It means local cache reset is explicit and fresh primitive
workouts can be pulled, executed, logged, pushed, and reset without old data
returning.

Earlier migration analysis considered outbox drain, per-timing-mode backfill
rules, temporary legacy-acceptance windows, and orphan policies for a broader
production-preservation scenario. That is **not** the cutover for this spec.
This spec carries the narrower disposable-QA-data requirement.

## Current implementation state

The primitive wire/schema/cache/sync/reset cutover has landed as the active
contract: workout create/read/update and sync pull expose `primitive_blocks`,
result pushes write `primitive_set_logs`, the app mirrors primitive workouts
and result rows, reset clears primitive logs, and old QA workout data may be
deleted rather than migrated. Grouped completion payloads now carry primitive
result rows only; the old `SetLog` result batch is no longer a sync or
push-queue payload shape. Live execution push wiring now uses only the
primitive result hook; the previous per-log `SetLog` push hook is no longer a
production execution dependency.

Residual work remains in the runtime-facing followups tracked by
`docs/specs/primitives-data-model.md` and `docs/feature-gap-map.md`: full
primitive-native execution, history correction over primitive result rows,
cross-runtime proof, and the remaining bridge/projection retirement work. This
file remains the cutover contract, not a claim that every downstream runtime
surface has been replaced.

## Current gaps

No cutover-only cache/reset gap remains. `PDM-GAP-005` is closed: old QA rows
do not need a preservation migration, local cache reset is explicit, and the
server database may be recreated on deployment before fresh primitive workouts
are pushed.

## Original full-cutover target

This was the original one-PR target. It remains the north-star shape for
removing residual bridge code, but the current implementation has already
landed the primitive wire/schema/cache/sync/reset core and is carrying the
runtime-facing leftovers as explicit gaps.

A complete runtime cutover lands:

1. **Server — database replacement.** On the next deployment, the server
   database may be deleted and recreated on the current primitive schema. If a
   future deploy needs preservation, re-enter requirements planning before
   writing a migration/backfill path. The active primitive schema:
   - Drops the existing `workout_item`, `block.timing_mode`, `block.timing_config_json`, `block.rounds`, `exercise_alternative`, and the old `prescription_json` columns.
   - Creates the new `workout`, `block`, `set` (new table), `slot` (renamed from workout_item), `alternative_slot` (replaces exercise_alternative) tables per the log-shape aspect's DDL.
   - Recreates `set_log` with the columns the log-shape aspect names (`role`, `slot_id`, `set_id`, `block_id`, `workout_id`, `planned_exercise_id`, `set_repeat_index`, `block_repeat_index`, `set_index`, `rounds`, `rir`, stimulus raw columns, overlay columns).
   - Existing server-side `set_log` rows may be deleted as QA data; no old-shape server result payload remains accepted after cutover.

2. **Server — API and Pydantic models.** `api/schemas.py` updated to the new prescription shape (nested block/set/slot). `api/sync.py` updated to write the new `set_log` row shape. `api/exercises.py` unchanged (exercise identity is unaffected). Regenerated `schema/openapi.json`.

3. **Shared schema DTOs.** `schema/Sources/WorkoutDBSchema/` Swift DTOs updated to match. `TimingMode` enum replaced by the `(timing, traversal, repeat)` cells defined in the authoring-shape aspect. Contract test in `tests/contract/test_swift_schema_parity.py` updated.

4. **App — local cache replacement.** Local QA workout/log/cache data may be
   reset. No row-preserving SwiftData migration is required for workout data:
   - Drops old `WorkoutItem`, `ExerciseAlternative`, `SetLog`, `Block` timing fields.
   - Adds new `Set`, `Slot`, `AlternativeSlot` model types and new `Block` fields (`repeat`, `timer`, `work_target`, `stimuli`).
   - New `SetLog` with the columns above.
   - Explicitly resets old local workout/log data as QA data. The proof
     obligation is reset correctness and clean fresh primitive operation, not
     field-for-field legacy schema retention.

5. **App — execution engine.** `SessionSeeder` rewritten to consume the new prescription shape and produce an `ExecutionPlan` per the runtime-resolution aspect. Drivers under `app/Packages/Features/Execution/Sources/FeaturesExecution/Drivers/` updated to read the new contract. Existing driver _behavior_ is preserved per acceptance criterion A1; driver _code_ is rewritten against the new `ExecutionPlan` / `ExecutionSlot` shape.

6. **Fixtures.** Regenerate every fixture under `schema/fixtures/` and `tests/` to the new shape. Ten worked-example fixtures from the authoring-shape aspect land as canonical test inputs.

7. **Docs sweep.** Update `docs/prescription.md` (current authoring vocabulary) to reflect the new shape. Update `docs/features/timing-modes.md` to describe timing modes as `(timing, traversal, repeat)` cells rather than a 12-case enum. Update `docs/specs/v2-architecture.md` with a pointer to this spec and a status note on the superseded data model section. Update harness surfaces whose cutover guidance changes, including `docs/MIGRATIONS.md` and `docs/runbooks/closeout.md`.

The original target expected all of the above to land together: no feature
flags, no parallel accepted payloads, and no compat shims. The current trunk
already enforces the primitive wire contract; the remaining work must keep that
same no-legacy posture while replacing bridge/runtime surfaces.

## Planning interpretation

The primitive cutover is the active trunk lane in `docs/backlog.md`, but this
cutover file owns the durable requirement: the only mergeable state is storage,
API, schema, execution, sync, fixtures, tests, and docs all on the primitive
contract with no legacy acceptance path.

Use `scratch/` for any temporary decomposition needed while implementing the
cutover. Do not preserve stale phase files in `docs/`; if implementation
discovers a requirement gap, update this spec or the relevant aspect file.

## Reversibility

Rollback is `git revert <cutover-commit>`. Both sides of the bisect remain
runnable for the committed cutover surface:

- Pre-cutover: server used old schema + old fixtures; app used old SwiftData version + old drivers.
- Post-cutover core: primitive wire/cache/sync/reset, old QA workout data reset, and fresh primitive prescriptions.

No runtime compatibility layer between the two sides is required because old-shape authoring and result payloads are not accepted post-cutover.

This satisfies acceptance criterion **A5**: the cutover treats old QA workout
data as disposable, keeps local reset explicit, and remains reversible within
dev.

## What the cutover deliberately does not do

- **Does not preserve old local workout/log data.** Current workouts and logs are QA data and may be deleted. The old row shape, old foreign keys, and old execution IDs do not survive as a compatibility lane.
- **Does not preserve server-side prescriptions.** Claude re-pushes active workouts in the new shape after the cutover lands. The server's old prescription store is wiped, and the whole server database may be recreated on deployment.
- **Does not preserve in-flight sessions.** If Eric has an active session when the cutover deploys, it is abandoned. The SwiftData destructive migration drops the `SessionState` store alongside `SetLog`.
- **Does not carry any legacy acceptance path.** `/api/sync/results` accepts only new-shape payloads post-cutover. No dual-shape window.
- **Does not include per-driver rewrite planning.** Each driver's port is its own implementation unit under `app/Packages/Features/Execution/`. The cutover lands the new contract; driver rewrites may land in the same PR as a single-shot port, or in stacked PRs sequenced by the driver-rewrite plan that implementation-planning produces.

## Verification for remaining runtime cutover

Per acceptance criteria A1 (all timing modes execute end-to-end) and A2 (ten worked examples round-trip), the remaining runtime cutover is green when:

1. All existing driver integration tests under `app/Packages/Features/Execution/Tests/` pass against new-shape fixtures.
2. Contract tests in `tests/contract/` pass (server + app schema parity).
3. Ten round-trip tests (one per worked example) pass.
4. `uv run pytest` passes on the server.
5. `uv run lint-imports` passes (no new architectural boundary violations).
6. A reset/cutover test proves representative local QA workouts/logs are removed and fresh primitive workouts/logs operate after the reset. Server proof is database recreation plus fresh primitive push/readback, not row-preserving migration.
7. A manual simulator smoke: Eric starts a fresh workout, executes a straight-set, a superset, and a cap-bounded block, confirms the set_log is written with the expected `slot_id` / `set_id` / `block_id` composition.

If any of the above fail, the runtime cutover remains open. There is no
dual-shape payload window: the repo stays on the primitive wire contract while
the implementation closes the named runtime gaps.

## When broader preservation constraints appear

If at some point this spec ships with broader preservation constraints — a
second user is onboarded, old server payloads must be accepted for a window, or
queued pre-cutover results must drain after deployment — the clean replacement
above becomes inappropriate. Re-enter requirements planning and write the
broader preservation contract into durable docs before phase or implementation
planning.
