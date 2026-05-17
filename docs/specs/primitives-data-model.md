---
title: Primitives data model
status: accepted (target spec) — implementation not yet started
date: 2026-04-28
purpose: Replace today's per-timing-mode prescription/log model with 7 composable primitives serialized under a Block > Set > Slot hierarchy, so every new workout pattern is a composition of existing primitives rather than a new enum case.
supersedes:
  - docs/specs/v2-architecture.md § Data model (the primitives model replaces that section; sync + philosophy sections of v2 remain authoritative)
covers:
  - Wire format for prescriptions (authoring-shape aspect)
  - Set log row shape (log-shape aspect)
  - Seed/log/correction-time runtime resolution (runtime-resolution aspect)
  - Cutover posture for a dev-mode drop-and-rebuild (cutover aspect)
---

# Primitives data model

## The problem

Today's schema couples 12 timing modes to 12 enum values, each with its own `timing_config_json` shape, its own prescription-JSON shape, and implicit rules the driver layer re-derives. Patterns that real programming needs — cluster sets with intra-set rest, work+rest Tabata siblings, compound work targets (`60 lb farmer carry for 50 m`), superset logging that batches at round-rest, AMRAP where the block timer bounds the whole round — each forced a new enum variant, a new `timing_config` key, or a driver workaround.

Two concrete failures:

1. **A cluster set on bench (`225 × 5, 20s rest, 225 × 5, 20s rest, 225 × 5`)** has no clean authoring today. Either we add a `cluster` timing mode (another enum + driver + config), or we pack it into `sets_detail` with ad-hoc intra-set rest (driver-specific interpretation). Neither is composition; both are special cases.
2. **A compound carry (`60 lb farmer carry for 50 m`)** needs two work-target dimensions on one slot (load-carried = 60 lb *and* distance = 50 m). `prescription_json`'s single-target assumption forces one dimension into free-form text or a side field; the log can't cleanly record both.

The same class of problem recurs with every new pattern (drop sets, rest-pause, warmup ramps, circuit batch-logging). The fix is not another enum case — it's primitives that compose.

## The shape

Seven primitives, orthogonal by design, serialize under a four-level hierarchy:

```
workout
├── blocks[]
│   ├── (block.repeat, block.timer, block-level stimuli, optional block work_target)
│   └── sets[]
│       ├── (set.timing, set.repeat, set.traversal, optional set work_target, set-level stimuli)
│       └── slots[]
│           ├── exercise_id
│           ├── work_target  (list of (metric, value-form) pairs)
│           ├── load          (value, unit, unit-type)  — optional
│           ├── stimuli       (RIR / RPE / derived-from-telemetry) — optional
│           ├── post_rest_sec — optional
│           └── alternative_ids — optional
```

The primitives are: **Exercise** (identity), **Structure** (the hierarchy itself + traversal + repeat), **Timing** (set_bounded / time_bounded / cap_bounded / target_bounded), **Work target** (list of `(metric, value-form)` pairs; metrics include reps / duration / distance / rounds / completion / load_carried), **Load** (`(value, unit, unit-type)` with unit-types absolute / relative / implicit-bodyweight), **Stimulus** (numeric-on-range or derived-from-telemetry; attachable at workout / block / set / slot), **Autoreg rules** (attached to a stimulus, currently only RIR has one).

Plus orthogonal overlays: `skipped`, `notes`, `warmup` flag, `manual` flag, `side` (reserved for per-side logging).

Every pattern today's 12 timing modes express is a composition over this tree. Straight-sets, supersets, circuits, clusters, EMOM, AMRAP, for-time, intervals, continuous, target-bounded, cap-bounded — each is a specific `(set.timing × set.traversal × set.repeat × block.timer × block.repeat)` cell. New patterns land as new compositions, not new enum values.

For the concept-level discussion of the primitives and why they were chosen, see `../../scratch/primitives-stimulus-prescription-type.md` (concept record; not part of this spec's acceptance bar but useful context).

## Outcomes

1. Every workout Eric authors today — straight-sets, superset, circuit, cluster, EMOM, AMRAP, for-time, Tabata, intervals, continuous cardio, compound CrossFit-style rounds, loaded carries — expresses as a composition over Block > Set > Slot. No new enum value is needed for any pattern already in `docs/prescription.md`.
2. A new pattern the author can describe in prose (say, "EMOM where each minute is itself a cluster") lands as a new composition of existing primitives rather than a schema change.
3. The driver layer reads the set's `(timing × traversal)` cell to decide iteration behavior, not a 12-way enum switch. Drivers become parametric over primitive cells, not hand-coded per timing mode.
4. Log rows carry enough structured join keys (`slot_id`, `set_id`, `block_id`, `role`, indices) that history queries (by exercise, by workout, by block) and corrections (edit past slot) work without JSON parsing and without fragile string matching.

## Scope

### In scope

- **Authoring shape** — the wire format for workout / block / set / slot, how each of the 7 primitives serializes, merge rules for library defaults + alternatives + hierarchy walk. See `primitives-data-model/authoring-shape.md`.
- **Log shape** — the `set_log` row model, three log roles (`slot`, `set_result`, `block_result`), deterministic UUID composition, per-stimulus typed columns, overlay columns, write semantics. See `primitives-data-model/log-shape.md`.
- **Runtime resolution** — seed-time transform into `ExecutionPlan`, relative-load resolution against `user_parameters`, driver iteration contract over primitive cells, correction semantics via same-UUID upsert. See `primitives-data-model/runtime-resolution.md`.
- **Cutover posture** — since the repo is still in single-user dev, the cutover is a drop-and-rebuild. See `primitives-data-model/cutover.md`.

### Out of scope

- **Per-driver implementation.** This spec pins the contract drivers read against. Rewriting the 12 existing drivers (or collapsing them into fewer parametric ones) is a downstream unit. The spec's acceptance does not require all driver code to be rewritten — only that the new contract is sufficient to rewrite them against.
- **UI component primitives.** The concept doc notes that editor / logger / preview can compose over UI primitives that mirror the model primitives 1:1. Building that UI is a separate unit. This spec is purely model-side.
- **New stimulus types.** The spec supports RIR (shipping), RPE (column reserved), and HR-zone as derived-from-telemetry. Adding velocity, bar-speed, or other stimulus types is a followup; each needs its own small schema migration and resolver.
- **Cross-stimulus autoreg.** Today only RIR has an autoreg rule. The spec accommodates multiple stimuli on a slot but does not specify cross-stimulus rule semantics. Deferred.
- **Session-level primitives.** Deload multipliers, weekly volume caps, fatigue models — those belong to a layer above the single-workout primitives. Out of scope.
- **Legacy data migration.** The repo is single-user dev; Eric's local set_logs can be dropped and rebuilt. The converged 700-line migration machinery from the scratch artifact (outbox drain, per-mode backfill, 30-day legacy acceptance) is NOT in this spec — it was designed for a production-data-preservation scenario that doesn't exist here.

## Acceptance criteria

This spec is "done" when all of the following are demonstrable. Each criterion is externally verifiable by a third party running the code and reading the fixtures.

**A1. All 12 current timing modes execute end-to-end under the new model.** For each of straight_sets, superset, circuit, cluster, emom, amrap, for_time, tabata, intervals, continuous, target_bounded, cap_bounded (the timing modes enumerated in `docs/features/timing-modes.md`), a fixture workout authored in the new Block > Set > Slot shape:
- Seeds into an `ExecutionPlan` without unknown-primitive errors
- Executes through its driver (existing or rewritten) producing the same observable behavior as today's integration tests check for — same rest-ring durations, same cursor advancement, same autoreg proposals
- Produces the `set_log` row(s) the log-shape aspect says each mode should produce, joinable on `slot_id` / `set_id` / `block_id` without JSON parsing

Proof: integration tests under `app/Packages/Features/Execution/Tests/` pass for all 12 drivers against new-shape fixtures. Contract tests in `tests/contract/` confirm server+app schema parity.

**A2. The ten worked examples in `authoring-shape.md` round-trip.** The aspect file carries ten real prescription patterns (straight-sets, superset with RIR autoreg, circuit with compound load+distance on one slot, cluster bench, EMOM mixing strength and cardio, AMRAP compound round, for-time with distance+reps, Tabata work+rest siblings, intervals with HR-zone stimulus, loaded carry). For each:
- JSON serializes from the documented shape (author-side)
- Seeds into `ExecutionPlan` without error
- Executes to completion via the appropriate driver
- Writes the `set_log` rows the example documents

Proof: fixture file per example under `tests/contract/` or `schema/fixtures/`, plus a round-trip test that asserts each stage's output.

**A3. Seed-time relative-load resolution is deterministic and pinned.** Given `user_parameters` rows with `updated_at` timestamps, a slot with `load: { value: 0.85, unit: "1rm", unit_type: "relative" }` resolves against the latest-by-updated_at row at pull time, caches absolute kg on `ExecutionSlot.load_kg`, and pins `resolved_from_user_param_id` when the sync contract exposes it.

Proof: a unit test with two `user_parameters` updates (bodyweight_kg changes between session A and session B) produces two different cached absolute loads when two sessions are seeded with the same relative-load slot.

**A4. Corrections use same-UUID upsert.** Editing a past slot's logged reps rewrites the same `set_log` row (same deterministic UUID composed from `(slot_id, block_repeat_index, set_repeat_index, set_index, role)`), not a new row with a correction flag. Audit of "what was this set on day X" reads the current row.

Proof: a test that logs a slot, edits it, and asserts the row count on `set_log` is exactly 1 with the edited values.

**A5. The cutover is reversible within dev.** Because the cutover is drop-and-rebuild and acceptance does not depend on preserving old data, rolling back the spec means reverting the server migration + SwiftData version + app code + fixtures in one commit. The repo remains runnable at either the pre-cutover or post-cutover commit.

Proof: bisect across the cutover commit; both sides of the bisect let `uv run pytest` and the app integration tests pass against the fixtures appropriate to that side.

### Explicitly not in the acceptance bar

- **Migration preserves historical set_logs.** Not required per Eric's dev-mode stance. The cutover aspect is drop-and-rebuild.
- **The UI looks different.** Pure model-side spec; UI changes are a separate feature.
- **Every driver is rewritten to be parametric.** Drivers can stay hand-coded per timing mode after the cutover, as long as they read against the new contract. Parametric consolidation is a followup.

## Assumptions and risks

### Assumptions

- **Single-user dev mode persists through this cutover.** If Eric adds another user, or if this spec lands in production with Eric's long-term set_log history as the preservation constraint, the cutover aspect needs the full migration machinery that's currently in `scratch/primitives-data-model.md` (Phase 4pre outbox drain, Phase 4c per-mode backfill, etc.). That machinery converged through dialectic but is intentionally not in this spec.
- **Claude continues to own exercise IDs and prescription composition.** The 7 primitives are authored by Claude in conversation; the app consumes them. If authoring shifts to an in-app editor, the component primitives noted in the concept doc become in-scope.
- **Stimulus types stay discrete and rare.** The schema uses per-stimulus typed columns (`rir`, `rpe` reserved, raw telemetry columns for derived stimuli). Adding a new stimulus type is a migration. Current count: 2-3 foreseeable.

### Risks

- **Drivers may need more than the new contract exposes.** The spec names the contract drivers read against (`ExecutionPlan.slots[]`, set/block timing cells, stimulus hierarchy). If a real driver rewrite surfaces a needed signal the contract doesn't carry (say, "next slot exercise_id for cross-slot autoreg"), the contract needs extending. Mitigation: rewrite one driver end-to-end as a pilot before committing the contract as frozen.
- **Node identity rules (preserve vs new id per edit class) are prescriptive.** The authoring-shape aspect pins 13 edit-class rules for when to preserve a slot/set/block id and when to mint a new one. A miscategorized edit silently orphans or binds history incorrectly. Mitigation: the spec names the conservative default (new id) when the edit logic can't classify, and the log-shape aspect denormalizes `workout_id` + `planned_exercise_id` so orphaned rows still answer "what workout" and "which exercise."
- **The Block > Set > Slot hierarchy is deeper than today's Block > Item.** Authors and drivers both see three levels where they saw two. If this added depth proves too ergonomically heavy for the authoring surface (Claude's conversation output), the spec may need a collapsing helper — e.g., `set` auto-synthesized when only one set is needed per block. Mitigation: the authoring-shape aspect provides worked examples so Claude has direct templates.

## Open questions

These are explicit; implementation-planning should treat them as things to investigate or decide before locking the contract, not as settled.

**OQ-1. Driver parametric consolidation.** After the contract lands, is it worth collapsing similar drivers (e.g., EMOM and Tabata both being time_bounded × rounds) into one parametric driver, or do the hand-coded drivers survive? Spike: rewrite EMOM + Tabata as one driver reading the `(set.timing, set.traversal, set.repeat, block.repeat, block.timer)` cell. If the resulting code is clearer than two, consolidate across the rest.

**OQ-2. Validation layer.** The authoring-shape aspect enumerates validation constraints (every set has ≥1 slot OR is a pure-timer rest set with `slots: []`, every slot's `work_target` has ≥1 metric with a completion role, etc.). Where do these run — on server ingest, on pull, on seed? Proposal: server-side at ingest, with a re-validation pass at seed as a belt-and-suspenders. Needs a decision.

**OQ-3. UI editor affordances.** When Eric edits a workout in the app (today: limited to swap + past-set edit; future: richer), does the editor surface the full primitive tree or a flattened view? Out of scope for this spec, but the node-identity rules bake in assumptions about what an editor will do. Flag for the UI-component-primitives downstream unit.

**OQ-4. `ExecutionPlan` invalidation on server-side prescription edits.** Pinned in section 3 as "no — the executing workout is the snapshot pulled at session start." If this becomes observable (Eric re-pulls mid-session and sees a different workout vs the one he's executing), we may need an explicit re-seed prompt. Leave pinned until observed.

## Cutover posture

Because the repo is single-user dev with no production data preservation constraint, the cutover is a **drop-and-rebuild**: new server migration drops the old prescription-JSON content and rebuilds in the new shape; SwiftData version bump drops old set_logs and seeds fresh from the server on first post-upgrade pull. See `primitives-data-model/cutover.md` for the specific steps and what ships in the cutover commit.

The 700-line coordinated-cutover machinery in `scratch/primitives-data-model.md` (Phase 4pre outbox drain, per-mode backfill, 30-day legacy acceptance at `/api/sync/results`) converged through dialectic for a production-preservation scenario. It is preserved in the scratch artifact as reference for a future migration if the preservation constraint appears, but is not part of this spec's cutover.

## Handoff to implementation-planning

Implementation-planning reads this spec and the four aspect files to plan the build. Specifically:

- **A1 is the primary proof surface.** Plan backward from "every timing-mode integration test passes against a new-shape fixture." The shape of the build is: add the new schema, add the seed-time transform, port drivers to read the new contract, regenerate fixtures.
- **A5 (reversibility) gates the shape of the cutover commit.** The cutover aspect says what lands in one PR; implementation-planning should treat that list as the shipping contract.
- **OQ-1 (driver parametric consolidation) is a spike, not a build task.** Plan the spike before committing to a full driver rewrite pass.
- **OQ-2 (validation location) is a decision, not a build task.** Resolve with Eric before writing validation code.
