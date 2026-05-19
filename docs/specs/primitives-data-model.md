---
title: Primitives data model
status: accepted — primitive cutover closed with follow-on app gaps routed elsewhere
date: 2026-04-28
last_reviewed: 2026-05-18
purpose: Replace today's per-timing-mode prescription/log model with 7 composable primitives serialized under a Block > Set > Slot hierarchy, so every new workout pattern is a composition of existing primitives rather than a new enum case.
supersedes:
  - docs/specs/v2-architecture.md § Data model (the primitives model replaces that section; sync + philosophy sections of v2 remain authoritative)
covers:
  - Wire format for prescriptions (authoring-shape aspect)
  - Set log row shape (log-shape aspect)
  - Seed/log/correction-time runtime resolution (runtime-resolution aspect)
  - Cutover posture for a complete primitives cutover with explicit QA-data reset (cutover aspect)
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

The primitive workout root may also carry `activity_intent`, a
vendor-neutral export source-facts object defined by
`docs/features/watch-workoutkit-handoff.md`. It is not one of the seven
execution primitives and does not change Setmark execution legality. It tells
export profiles what the authored workout is trying to preserve when primitive
structure alone is ambiguous, for example running-first Hyrox versus
mixed-structure Hyrox. Missing `activity_intent` means Setmark may still
execute the workout, but target export profiles must return a source-choice
state instead of guessing.

Every pattern today's 12 timing modes express is a composition over this tree. Straight-sets, supersets, circuits, clusters, EMOM, AMRAP, for-time, intervals, continuous, target-bounded, cap-bounded — each is a specific `(set.timing × set.traversal × set.repeat × block.timer × block.repeat)` cell. New patterns land as new compositions, not new enum values.

The concept-level discussion of the primitives and why they were chosen has
been folded into this spec and its aspect files. If future planning needs more
history, use git history rather than treating scratch notes as durable
authority.

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
- **Cutover posture** — primitive wire/schema/cache/sync/reset cutover with no legacy acceptance path. Current local/server QA workout data is disposable; the next deployment may delete and recreate the server database instead of preserving old rows. Remaining native execution/history gaps stay tracked below. See `primitives-data-model/cutover.md`.

### Out of scope

- **Per-driver implementation.** This spec pins the contract drivers read against. Rewriting the 12 existing drivers (or collapsing them into fewer parametric ones) is a downstream unit. The spec's acceptance does not require all driver code to be rewritten — only that the new contract is sufficient to rewrite them against.
- **UI component primitives.** The concept doc notes that editor / logger / preview can compose over UI primitives that mirror the model primitives 1:1. Building that UI is a separate unit. This spec is purely model-side.
- **New stimulus types.** The spec supports RIR (shipping), RPE (column reserved), and HR-zone as derived-from-telemetry. Adding velocity, bar-speed, or other stimulus types is a followup; each needs its own small schema migration and resolver.
- **Cross-stimulus autoreg.** Today only RIR has an autoreg rule. The spec accommodates multiple stimuli on a slot but does not specify cross-stimulus rule semantics. Deferred.
- **Session-level primitives.** Deload multipliers, weekly volume caps, fatigue models — those belong to a layer above the single-workout primitives. Out of scope.
- **Adapter-specific export fields.** WorkoutKit, Strava, HealthKit, or any
  other external-system mapping data does not live on primitive block, set,
  slot, or log nodes. Primitive nodes carry vendor-neutral structure, timing,
  targets, loads, stimuli, overlays, stable IDs, and result roles. External
  adapter profiles inspect those facts and classify support outside the
  primitive execution contract. `activity_intent` is the narrow
  vendor-neutral exception at the primitive workout root: it may describe
  authored activity domain, environment, and preservation policy, but must not
  use target names such as `workoutkit_activity`, `apple_activity`,
  `HKWorkoutActivityType`, or `strava_type`.
- **Legacy acceptance windows.** The cutover does not accept both old and new workout shapes after it lands. Existing server-side prescriptions can be re-pushed by Claude in the primitive shape. Current completed local logs are QA data for this pre-real-use cutover and may be reset rather than migrated.

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

**A3. App seed-time relative-load resolution is deterministic.** Given locally mirrored `user_parameters` rows with `updated_at` timestamps, a slot with `load: { value: 0.85, unit: "1rm", unit_type: "relative" }` resolves against the latest-by-updated_at row when the app seeds the pulled workout and caches absolute kg on `ExecutionSlot.load_kg`. Source-row id provenance is deferred until a coordinated execution-plan/schema cutover needs it.

Proof: a unit test with two `user_parameters` updates (bodyweight_kg changes between session A and session B) produces two different cached absolute loads when two sessions are seeded with the same relative-load slot.

**A4. Corrections use same-UUID upsert.** Editing a past slot's logged reps rewrites the same `set_log` row (same deterministic UUID composed from `(slot_id, block_repeat_index, set_repeat_index, set_index, role)`), not a new row with a correction flag. Audit of "what was this set on day X" reads the current row.

Proof: a test that logs a slot, edits it, and asserts the row count on `set_log` is exactly 1 with the edited values.

**A5. The cutover explicitly resets old QA workout data and remains reversible within dev.** Existing local/server workouts and logs are pre-real-use QA data for this cutover and may be deleted instead of migrated. The next deployment may delete and recreate the server database; no production migration/backfill work is required for those rows. Local cache reset remains explicit, and old data must not silently mix with primitive data. Rolling back the spec still means reverting the server schema/app code/fixtures as one coherent cutover; both sides of the cutover remain runnable.

Proof: local reset/cache tests assert old-shape workouts/logs are cleared before fresh primitive workouts are pulled, executed, logged, and pushed. Server-side proof is deployment posture, not a preservation migration: recreate the database, apply current schema, and accept fresh primitive pushes. Bisect across the cutover commit; both sides of the bisect let `uv run pytest` and the app integration tests pass against the fixtures appropriate to that side.

### Explicitly not in the acceptance bar

- **Legacy shape remains accepted after cutover.** Not required and explicitly forbidden. Resetting QA data is not a compatibility mode.
- **The UI looks different.** Pure model-side spec; UI changes are a separate feature.
- **Every driver is rewritten to be parametric.** Drivers can stay hand-coded per timing mode after the cutover, as long as they read against the new contract. Parametric consolidation is a followup.

## Remaining proof matrix

Primitive cutover closeout is not "debug fixtures run." The remaining proof
must cover the seven primitives and their important compositions before
simulator QA is used as confirmation.

## Primitive semantics foundation

The completed foundation cluster introduced a shared primitive semantics layer
before broadening the matrix. The problem was not only that AMRAP partial
results needed distance or carried-load controls; the broader issue was that
seeding, projection, result entry, completion summaries, correction, and sync
could infer primitive meaning independently.

The durable contract is:

- Domain and Sync own the validated primitive authoring values and wire decode.
- A CoreSession-owned semantics layer owns the pure rules that turn a
  primitive block/set/slot into an executable/result contract.
- Feature views, completion ledgers, persistence grouping, and sync payload
  construction consume that contract; they do not rediscover primary metrics,
  completion metrics, aggregate roles, or editable result fields from timing
  mode names, row counts, or UI defaults.
- Server validation owns authoring rejection at ingest, but must enforce the
  same legal primitive composition rules the app semantics layer executes.

The semantics layer must answer, for each primitive composition:

- Which timing/traversal cells are legal, bounded, unbounded, or rejected.
- Whether a composition represents executable work or an invalid
  timer-only/programming artifact. In the current bridge runtime, a timer
  without slots is not accepted; rest/transition primitive timers require a
  later primitive-runtime authority cutover before ingest can allow them.
- Which metrics are completion-driving and which are observations.
- Which metric is primary for display, and which metrics are secondary.
- Which outputs become `slot`, `set_result`, or `block_result` rows.
- How repeated sets, repeated blocks, round-robin traversal, AMRAP traversal,
  and aggregate scopes determine deterministic log identity.
- Which fields are editable on result and correction surfaces.
- Which counts are implementation sentinels and must never render as user
  progress.

This layer intentionally does **not** rewrite every existing timing driver in
one move, introduce an in-app primitive editor, or generalize beyond the
accepted seven primitives. It is the smallest foundation needed so the next
bug fixes and proof matrix assert one set of primitive composition rules.

### Completed foundation cluster

The first implementation cluster was intentionally narrower than full
primitive-lane closeout. It delivered the app-runtime semantics foundation with
proof, not every downstream consumer in one move.

Delivered:

- CoreSession-owned computed semantics on the existing primitive
  execution types for timing/traversal legality, visible-progress policy,
  completion vs observation target lookup, metric display ordering,
  partial-result input fields, and aggregate result row policy.
- Production primitive seeding, pre-start preview projection,
  AMRAP/aggregate result entry, and completion summaries route through those
  semantics. The EMOM progress proof now hides sentinel row counts from visible
  active-block progress and completion block summaries.
- Route/sheet lifecycle risk from `bug-089` is closed by owning the End
  confirmation at the stable `ExecutionView` router instead of route-local
  Active/Rest screens.
- Narrow app/server legality parity for the primitive timing/traversal and
  aggregate-target rules centralized by this cluster.

Residual scope after this foundation cluster:

- History correction and any correction UI outside execution completion.
- New primitive wire fields, new SwiftData migrations, and new sync payload
  semantics unless implementation exposes a real encoding gap.
- Cross-runtime server/app sync proof, which belongs to the next contract
  cutover cluster because it must exercise the real URLSession/FastAPI/SQLite
  boundary.

### Completed contract cutover and sync/readback cluster

The primitive contract cutover and sync/readback cluster proves that primitive
workouts can move through the real system, not only that the app runtime can
reason about primitive fixtures.

Implemented in this cluster:

- Replaced remaining old-shape wire/schema surfaces with the primitive
  authoring/log contract where this lane owns them: server API models,
  OpenAPI/shared Swift DTOs, SwiftData cache shape, fixtures, and docs.
- Implemented the explicit local cache reset posture required by `cutover.md`;
  server QA data does not need preservation because the deployment may recreate
  the database.
- Proved pull -> local cache -> `ExecutionPlan` seed -> execution log/result
  grouping -> push -> server readback for representative primitive workouts.
- Tightened primitive result role query-safety by validating pushed slot,
  set_result, and block_result identifiers against the referenced workout's
  primitive tree.
- Extended stage/proof telemetry where simulator click-through QA needs an
  event trail for non-visual boundaries. At minimum, QA should be able to
  correlate primitive cache write, `ExecutionPlan` assembly, primitive result
  logging, completion publishing, push response, and queue drain through
  `workout_id` / primitive set-log identifiers or an explicitly documented
  equivalent readback.

Closeout status:

- `PDM-GAP-002`, `PDM-GAP-003`, `PDM-GAP-004`, `PDM-GAP-005`, `PDM-GAP-006`,
  `PDM-GAP-007`, and `PDM-GAP-008` are closed. Primitive residuals now route through
  feature-owned app gaps instead of a continuing primitive trunk.
- `EXEC-GAP-008` remains separate for expanded per-slot editing.
- External-adapter neutrality is preserved: the cutover added only
  vendor-neutral primitive fields. WorkoutKit, Strava, HealthKit, or other
  export capability mapping remains an adapter/profile layer over the
  primitive contract.

Out of scope unless the architecture review says otherwise:

- In-app primitive authoring/editor UI.
- History analytics redesign beyond the query-safety/readback proof needed for
  primitive result roles.
- Production data migration compatibility; current workouts are QA data and may
  be reset explicitly or removed by recreating the server database.

### Completed completion/history remediation cluster

The completion/history remediation closed the main primitive-result authority
gap: completion was writing primitive rows while History and some completion
copy still reasoned from legacy rows or internal row counts.

Delivered:

- `CoreSession` classifies primitive result rows by role and metric semantics:
  `slot` rows are exercise-level facts, `set_result` rows are set aggregates,
  and `block_result` rows are block aggregates. Sentinel/internal rows are not
  athlete progress.
- The primitive coordinate contract is unified across app, server, schema, and
  docs: `set_index` is commit sequence within the current
  `(block_repeat_index, set_repeat_index)` set instance, not authored slot
  ordinal.
- Completion summaries and History detail both consume that classification.
  Athlete-facing strings remain feature-local; the semantic authority does not
  live in either feature.
- History loads primitive workouts and primitive set logs for completed
  sessions, renders primitive session details, computes picker/top-load/trend
  inputs from eligible slot rows through CoreSession-aware consumers, excludes
  aggregate rows from by-exercise metrics, preserves bodyweight-window binding,
  and reset removes primitive rows from rendered History. Completed primitive
  workouts do not use legacy `SetLog` rows as fallback authority.
- Explicit-End completion preserves already logged primitive rows across EMOM,
  intervals, Tabata, for-time, continuous, AMRAP, and a composed primitive
  case.
- Persistence, Shell, and real HTTP proof now cover slot, set-result, and
  block-result rows through local SwiftData, Save & Done wiring, push queue
  flush, `sync/pull` API readback for eligible slot rows, and server SQLite
  persistence for aggregate rows and nonzero slot commit coordinates.
- The workout-type UI matrix has a focused Save & Done -> History primitive
  readback sentinel for the capstone flow. The full matrix runner is now a
  repeatable gate: `make test-workout-type-ui-repeat` runs the matrix multiple
  times into distinct result roots and fails on missing bundles.

Closed by this cluster:

- `bug-096`: History detail does not render saved completion results.
- `bug-097`: early-ending EMOM loses the interval that was just logged.
- `bug-098`: for-time completion summary uses row-count copy instead of
  workout-result language.

Residual scope:

- `HISTORY-GAP-002` remains open for primitive-native post-workout correction.
- `HISTORY-GAP-001` and `MOD-GAP-003` remain open for taxonomy, unilateral,
  cross-variant, and analytics redesign.
- Workout-type UI matrix runner stability is closed by the repeat gate and
  three-pass bundle-count proof.

The foundation-cluster proof bar was:

- CoreSession semantic-helper tests over the shared legality matrix, metric
  roles, aggregate-result policy, deterministic result identity, and sentinel
  visibility.
- FeatureExecution tests proving seeder delegation, primitive projection
  metrics, AMRAP non-rep partial results, completion summaries without
  primitive note parsing fallback, and `bug-090` across active execution and
  completion summaries.
- Server ingest tests mirroring the same accept/reject legality grid as
  CoreSession, including role-specific aggregate-target checks. Representative
  server coverage is not enough for this cluster.
- `WorkoutDBUITests.ExecutionEndConfirmationUITests` covers `bug-089` through
  the real SwiftUI route/alert lifecycle: Active/Rest End controls open the
  confirmation, route changes dismiss stale alerts, and the user can reopen and
  end the workout through the stable execution router.
- `make pre-qa` before simulator QA, then `docs/QA.md` evidence on the bounded
  primitive fixtures named below.

The cutover implementation must add deterministic proof for:

- **Timing x traversal:** legal `set_bounded`, `time_bounded`, `cap_bounded`,
  and `target_bounded` compositions across sequential, round-robin, and AMRAP
  traversal, plus explicit rejection of illegal cells such as uncapped AMRAP.
- **Executable-work legality:** rejection of timer-only workouts, timer-only
  blocks, all zero-slot sets in the current bridge runtime, and aggregate
  result targets attached to scopes with no executable work.
- **Work targets:** `reps`, `duration`, `distance`, `rounds`, `completion`,
  and `load_carried` across single, range, and open value forms, with
  completion metrics driving done conditions and observation metrics recorded
  without ending work.
- **Load:** absolute kg/lb, relative 1RM, relative bodyweight, implicit
  bodyweight, and carried-load mapping at seed/log time.
- **Stimulus and autoreg:** nearest-wins hierarchy resolution, RIR logging,
  telemetry preservation, and observable future-state proposals.
- **Structure and overlays:** block repeat, set repeat, slot traversal indices,
  alternatives, performed-exercise identity, skipped rows, warmups, notes,
  side, manual overlays, deterministic IDs, and same-UUID correction upsert.
- **Sync and cutover:** primitive authoring fixture decode, server ingest,
  pull payloads, Swift decode/cache write, execution seeding, completion
  record grouping, result push payloads, server readback, and explicit
  destructive reset of old QA workout/log data.

The expected named test families are:

1. `PrimitiveRuntimeMatrixTests`
2. `PrimitiveMetricRoleTests`
3. `PrimitiveLoadResolutionTests`
4. `PrimitiveStimulusAutoregTests`
5. `PrimitiveResultIdentityTests`
6. `PrimitiveSyncContractTests`
7. `ExecutionProjectionSentinelTests`
8. Hosted execution lifecycle proof for modal/timer route changes

Simulator fixture breadth should stay bounded to named primitive cells:
cap-bounded mixed AMRAP, for-time/chipper mixed metric flow,
intervals/rest-boundary flow, loaded-carry/multi-metric circuit, and
EMOM/density sentinel-boundary flow. Add a new QA fixture only when it proves a
named primitive composition or invariant that the deterministic matrix does not
already cover.

## Assumptions and risks

### Assumptions

- **Single-user dev mode persists through this cutover.** No multi-user or production compatibility window is needed. Current local/server workouts are QA data, so the primitive cutover may reset them rather than migrate them. Server-side prescriptions and in-flight sessions can be rebuilt or abandoned.
- **Claude continues to own exercise IDs and prescription composition.** The 7 primitives are authored by Claude in conversation; the app consumes them. If authoring shifts to an in-app editor, the component primitives noted in the concept doc become in-scope.
- **Stimulus types stay discrete and rare.** The schema uses per-stimulus typed columns (`rir`, `rpe` reserved, raw telemetry columns for derived stimuli). Adding a new stimulus type is a migration. Current count: 2-3 foreseeable.

### Risks

- **Drivers may need more than the new contract exposes.** The spec names the contract drivers read against (`ExecutionPlan.slots[]`, set/block timing cells, stimulus hierarchy). If a real driver rewrite surfaces a needed signal the contract doesn't carry (say, "next slot exercise_id for cross-slot autoreg"), the contract needs extending. Mitigation: rewrite one driver end-to-end as a pilot before committing the contract as frozen.
- **Node identity rules (preserve vs new id per edit class) are prescriptive.** The authoring-shape aspect pins 13 edit-class rules for when to preserve a slot/set/block id and when to mint a new one. A miscategorized edit silently orphans or binds history incorrectly. Mitigation: the spec names the conservative default (new id) when the edit logic can't classify, and the log-shape aspect denormalizes `workout_id` + `planned_exercise_id` so orphaned rows still answer "what workout" and "which exercise."
- **The Block > Set > Slot hierarchy is deeper than today's Block > Item.** Authors and drivers both see three levels where they saw two. If this added depth proves too ergonomically heavy for the authoring surface (Claude's conversation output), the spec may need a collapsing helper — e.g., `set` auto-synthesized when only one set is needed per block. Mitigation: the authoring-shape aspect provides worked examples so Claude has direct templates.

## Current gaps

No active `PDM-GAP-*` rows remain. The primitive cutover is closed as the data
model trunk: wire/schema/cache/sync/reset, runtime semantics, completion and
History read models, aggregate result roles, no-work rejection, grouped
completion push, real HTTP readback, and repeatable workout-type QA are now
covered by the owning tests and docs.

Follow-on work is intentionally routed to app lanes instead of keeping a
permanent primitive trunk:

- History correction and correction UI outside execution completion live in
  `HISTORY-GAP-002`, `PASTEDIT-GAP-001`, and the Set editing lane.
- Taxonomy, cross-variant, unilateral, and analytics questions live in
  `HISTORY-GAP-001` and `MOD-GAP-003`.
- Runtime-cost/object-lifetime proof lives in `EXEC-GAP-012` and
  `TEST-GAP-005`.
- Future primitive cells or new consumers should open a new owning gap only
  when a concrete feature needs them; unsupported cells fail closed today.

## Open questions

These are explicit; implementation-planning should treat them as things to investigate or decide before locking the contract, not as settled.

**OQ-1. Driver parametric consolidation.** After the contract lands, is it worth collapsing similar drivers (e.g., EMOM and Tabata both being time_bounded × rounds) into one parametric driver, or do the hand-coded drivers survive? Spike: rewrite EMOM + Tabata as one driver reading the `(set.timing, set.traversal, set.repeat, block.repeat, block.timer)` cell. If the resulting code is clearer than two, consolidate across the rest.

**OQ-2. Validation layer.** Resolved for the cutover: server ingest is the
authoritative rejection point for malformed primitive workouts. The app also
performs seed-time defensive revalidation before building an `ExecutionPlan` so
locally cached or manually seeded data cannot execute if it violates the
primitive contract. Pull-time mapping may reject malformed payloads as a decode
failure, but it is not a second source of authoring truth. Validation failures
must point to the offending block/set/slot and the violated primitive rule.

**OQ-3. UI editor affordances.** When Eric edits a workout in the app (today: limited to swap + past-set edit; future: richer), does the editor surface the full primitive tree or a flattened view? Out of scope for this spec, but the node-identity rules bake in assumptions about what an editor will do. Flag for the UI-component-primitives downstream unit.

**OQ-4. `ExecutionPlan` invalidation on server-side prescription edits.** Pinned in section 3 as "no — the executing workout is the snapshot pulled at session start." If this becomes observable (Eric re-pulls mid-session and sees a different workout vs the one he's executing), we may need an explicit re-seed prompt. Leave pinned until observed.

## Cutover posture

Because the repo is single-user dev with no production compatibility constraint, the cutover is a **complete replacement of the active contract**: old prescription JSON and timing-mode shapes stop being accepted, current local/server QA workouts may be reset, and Claude re-pushes active workouts in the new shape. The SwiftData version bump must make the destructive reset explicit while dropping legacy authoring, old logs, and in-flight-session state. See `primitives-data-model/cutover.md` for the specific steps and what ships in the cutover commit.

Earlier coordinated-cutover analysis considered a production-preservation
scenario with outbox drain, per-mode backfill, completed-log migration, and
temporary dual-shape server acceptance. That is not this repo's active
requirement. If broader preservation constraints appear, rerun requirements
planning and update this spec rather than reviving scratch analysis as
authority.

## Handoff to implementation-planning

Implementation-planning reads this spec and the four aspect files to plan the build. Specifically:

- **A1 is the primary proof surface.** Plan backward from "every timing-mode integration test passes against a new-shape fixture." The shape of the build is: add the new schema, add the seed-time transform, port drivers to read the new contract, regenerate fixtures.
- **A5 (explicit reset and reversibility) gates the shape of the cutover commit.** The cutover aspect says what lands in one PR; implementation-planning should treat that list as the shipping contract.
- **OQ-1 (driver parametric consolidation) is a spike, not a build task.** Plan the spike before committing to a full driver rewrite pass.
- **OQ-2 (validation location) is resolved.** Server ingest is authoritative; app seed-time validation is defensive; pull-time mapping may reject malformed payloads as decode failure.
