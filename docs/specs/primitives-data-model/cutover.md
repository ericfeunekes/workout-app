---
title: Cutover — drop-and-rebuild in one ship unit
status: accepted — spec
parent: ../primitives-data-model.md
purpose: How the primitives data model lands. Because the repo is single-user dev with no production data preservation constraint, the cutover is a clean drop-and-rebuild in one PR — not a coordinated migration with orphan policies and per-mode backfill.
---

# Cutover

## Why this is short

The repo is single-user dev. Eric's local set_logs on device can be dropped and rebuilt from scratch. The server's prescription store can be dropped and re-accepted when Claude pushes workouts in the new shape. There is no "existing user base" to migrate, no historical data to preserve, no backward compatibility to honor.

A converged 700-line migration plan — covering outbox drain, per-timing-mode backfill rules, 30-day legacy-acceptance windows, orphan policies for pre-V3 denormalization — lives in `scratch/primitives-data-model.md` § "Section 4: Migration Plan". That plan is the right shape for a production-preservation scenario and can be revived if this spec later ships in a context with real user data. It is **not** the cutover for this spec.

## What the cutover ships in one PR

A single commit lands:

1. **Server — new schema migration.** One SQL migration (append-only, per `docs/MIGRATIONS.md`) that:
   - Drops the existing `workout_item`, `block.timing_mode`, `block.timing_config_json`, `block.rounds`, `exercise_alternative`, and the old `prescription_json` columns.
   - Creates the new `workout`, `block`, `set` (new table), `slot` (renamed from workout_item), `alternative_slot` (replaces exercise_alternative) tables per the log-shape aspect's DDL.
   - Recreates `set_log` with the columns the log-shape aspect names (`role`, `slot_id`, `set_id`, `block_id`, `workout_id`, `planned_exercise_id`, `set_repeat_index`, `block_repeat_index`, `set_index`, `rounds`, `rir`, stimulus raw columns, overlay columns).
   - Existing `set_log` rows are dropped. This is explicit. The repo's single-user dev posture makes this safe.

2. **Server — API and Pydantic models.** `api/schemas.py` updated to the new prescription shape (nested block/set/slot). `api/sync.py` updated to write the new `set_log` row shape. `api/exercises.py` unchanged (exercise identity is unaffected). Regenerated `schema/openapi.json`.

3. **Shared schema DTOs.** `schema/Sources/WorkoutDBSchema/` Swift DTOs updated to match. `TimingMode` enum replaced by the `(timing, traversal, repeat)` cells defined in the authoring-shape aspect. Contract test in `tests/contract/test_swift_schema_parity.py` updated.

4. **App — SwiftData versioned cutover.** One SwiftData migration stage from V_current to V_new:
   - Drops old `WorkoutItem`, `ExerciseAlternative`, `SetLog`, `Block` timing fields.
   - Adds new `Set`, `Slot`, `AlternativeSlot` model types and new `Block` fields (`repeat`, `timer`, `work_target`, `stimuli`).
   - New `SetLog` with the columns above.
   - Lightweight on adds, destructive on removals. Local data is discarded.

5. **App — execution engine.** `SessionSeeder` rewritten to consume the new prescription shape and produce an `ExecutionPlan` per the runtime-resolution aspect. Drivers under `app/Packages/Features/Execution/Sources/FeaturesExecution/Drivers/` updated to read the new contract. Existing driver _behavior_ is preserved per acceptance criterion A1; driver _code_ is rewritten against the new `ExecutionPlan` / `ExecutionSlot` shape.

6. **Fixtures.** Regenerate every fixture under `schema/fixtures/` and `tests/` to the new shape. Ten worked-example fixtures from the authoring-shape aspect land as canonical test inputs.

7. **Docs sweep.** Update `docs/prescription.md` (current authoring vocabulary) to reflect the new shape. Update `docs/features/timing-modes.md` to describe timing modes as `(timing, traversal, repeat)` cells rather than a 12-case enum. Update `docs/specs/v2-architecture.md` with a pointer to this spec and a status note on the superseded data model section.

All of the above lands in one PR. This is the complete-cutover invariant from `CLAUDE.md` — no feature flags, no parallel codepaths, no compat shims.

## Reversibility

Because nothing is preserved across the cutover, rollback is `git revert <cutover-commit>`. Both sides of the bisect are runnable:

- Pre-cutover: server uses old schema + old fixtures; app uses old SwiftData version + old drivers.
- Post-cutover: new everything, empty `set_log` and fresh prescriptions.

No data interpolation between the two sides is required because no data is retained across the boundary.

This satisfies acceptance criterion **A5**: the cutover is reversible within dev.

## What the cutover deliberately does not do

- **Does not preserve local set_log rows.** Eric's existing set_logs are dropped. This is acceptable because the repo is single-user dev and Eric has no long-term history to preserve (no sessions are being analyzed longitudinally today).
- **Does not preserve server-side prescriptions.** Claude re-pushes active workouts in the new shape after the cutover lands. The server's old prescription store is wiped.
- **Does not preserve in-flight sessions.** If Eric has an active session when the cutover deploys, it is abandoned. The SwiftData destructive migration drops the `SessionState` store alongside `SetLog`.
- **Does not carry any legacy acceptance path.** `/api/sync/results` accepts only new-shape payloads post-cutover. No dual-shape window.
- **Does not include per-driver rewrite planning.** Each driver's port is its own implementation unit under `app/Packages/Features/Execution/`. The cutover lands the new contract; driver rewrites may land in the same PR as a single-shot port, or in stacked PRs sequenced by the driver-rewrite plan that implementation-planning produces.

## Verification at cutover land

Per acceptance criteria A1 (all 12 timing modes execute end-to-end) and A2 (ten worked examples round-trip), the cutover PR lands green when:

1. All existing driver integration tests under `app/Packages/Features/Execution/Tests/` pass against new-shape fixtures.
2. Contract tests in `tests/contract/` pass (server + app schema parity).
3. Ten round-trip tests (one per worked example) pass.
4. `uv run pytest` passes on the server.
5. `uv run lint-imports` passes (no new architectural boundary violations).
6. A manual simulator smoke: Eric starts a fresh workout, executes a straight-set, a superset, and a cap-bounded block, confirms the set_log is written with the expected `slot_id` / `set_id` / `block_id` composition.

If any of the above fail, the cutover does not land. There is no half-shipped state — either everything on the new contract or everything on the old.

## When the preservation constraint appears

If at some point this spec ships with a preservation constraint — Eric's historical set_logs matter, or a second user is onboarded, or the app moves to a state where rebuilding from scratch is disruptive — the drop-and-rebuild cutover above becomes inappropriate. The fallback is the full coordinated-cutover plan preserved in `scratch/primitives-data-model.md` § Section 4: Phase 4pre outbox drain (local rewrite using Phase 4c rules before drain), Phase 4a/4b/4c app-side backfill with per-timing-mode rewrite rules, orphan policy, deterministic set_log UUID composition. That plan was pressure-tested through 4 rounds of dialectic and is structurally sound for a production preservation scenario; it was set aside here only because the dev-mode posture makes it premature.
