---
title: Phase 4 — Compositional patterns unlocked by primitives become authorable
status: backlog
last_reviewed: 2026-04-29
purpose: Fourth phase of the primitives-data-model cutover. After this phase, workout patterns that the old per-timing-mode model could not express cleanly — cluster sets, sibling work+rest structures, compound work targets, zero-slot pure-timer rest sets, mixed strength+cardio within one round — are authorable under the primitive vocabulary and execute correctly.
parent: ./README.md
spec:
  - docs/specs/primitives-data-model.md
  - docs/specs/primitives-data-model/authoring-shape.md
  - docs/specs/primitives-data-model/runtime-resolution.md
---

# Phase 4 — Compositional patterns unlocked by primitives become authorable

> Historical/source-material note: this is not a standing implementation plan.
> Future work must start from `PDM-GAP-*` rows in the owning primitives spec
> files and create a fresh active plan against the codebase state at pickup
> time.

## Unit statement

After this phase, the workout patterns that motivated the primitives redesign — patterns the old model either could not express or forced into awkward workarounds — are first-class authorable compositions. Cluster sets compose as multi-slot structures with authored intra-slot rest. Work+rest sibling sets replace the Tabata-intrinsic hardcoded cadence. Compound work targets (load + distance on one slot) route correctly through the cardio-and-strength log shape. Zero-slot pure-timer rest sets exist as blocks of their own. Mixed strength and cardio within one AMRAP round is authorable without timing-mode negotiation.

## Why

Phase 3 delivered feature parity with the pre-cutover build: every workout Eric can run today, he can still run. Phase 4 delivers what the primitives redesign was for — capability that didn't exist before.

Five concrete gaps in today's authoring drove the redesign:

The first is cluster sets. Today, the authoring vocabulary has a `cluster` prescription shape that the execution layer collapses to a plain set at seed time, dropping the intra-slot rest. A cluster-rest-pause architecture plan (`docs/plans/archive/cluster-rest-pause-architecture.md`) was in flight to add a new session primitive for slot-level cursor advancement; that plan is superseded by this phase. Under primitives, a cluster is not a new primitive — it is one set with N slots carrying the same exercise, per-slot rep targets, and authored post-slot rest. The composition already exists; what Phase 4 adds is the execution support for authoring and running one.

The second is sibling work+rest structures. Today, Tabata's 20-seconds-of-work then 10-seconds-of-rest cadence is hardcoded in the Tabata driver. Any other work+rest cadence (30s/15s, 40s/20s) is not expressible. Under primitives, work+rest sibling sets inside a block with `block.repeat = 8` compose the Tabata pattern from parts — and the parts generalize to any cadence the author writes.

The third is compound work targets. Today, a 60lb farmer carry for 50 meters forces one dimension (load, distance) into free-form text or a side field because `prescription_json` assumes one target per slot. Under primitives, `work_target` is a list of metric/value pairs; load-and-distance on one slot composes natively and logs both values.

The fourth is zero-slot pure-timer rest sets. Today, rest between blocks is driven by the end-of-block rest field on the preceding block's timing config. A standalone rest block exists but is a stub — it cannot be a set-level composition. Under primitives, a set with an empty slot list and a timing window is a pure-timer rest; it can compose alongside work sets inside a block.

The fifth is mixed strength and cardio within one round. Today, a CrossFit-style round that alternates pull-ups with a 1km run forces the authoring vocabulary into a single timing mode per block. Under primitives, slots inside a round can each carry their own work-target metric — reps for the pull-ups, distance for the run — and the round advances through them without a timing-mode commitment.

These five patterns together are what the spec's acceptance criterion A2 (ten worked examples round-trip) is ultimately about. Phase 4 is where A2 is proven.

The stakeholder is Eric as user on the branch build. After this phase, he can author workouts he could not author before.

## Acceptance criteria

1. **Cluster sets compose as authored multi-slot structures.** A cluster authored as one set with N slots of the same exercise, per-slot rep counts, and authored post-slot rest executes with every sub-slot committed as its own log row and the inter-slot rest observed at the authored duration. The top-level set produces whatever aggregate row the log-shape aspect prescribes for a multi-slot set; the cluster does not collapse to a single row at seed or commit time.

2. **Work+rest sibling sets replace timing-intrinsic cadence.** A block composed of a work set (timing window, slot with the work exercise) and a rest set (timing window, no slots) with `block.repeat = N` executes as N iterations alternating work and rest, where the work window reads from the authored work set's timing and the rest window reads from the authored rest set's timing. The existing Tabata cadence is reachable by authoring 20-second-work + 10-second-rest + 8-repeat; any other cadence is reachable by changing the authored values.

3. **Compound work targets execute and log both dimensions.** A slot authored with both a load and a distance work target (e.g., 60lb load + 50m distance) renders correctly on the active screen, accepts both dimensions as observed outcomes at log time, and writes both values to the log row. A slot with load + duration does the same. The log-shape aspect's row carries both fields populated.

4. **Zero-slot rest sets exist as composable set-level entities.** A set authored with an empty slot list and a timing window executes as a pure timer — the user sees rest-screen semantics during the timing window and the set advances to the next set (or block completion) without requiring a slot commit. The zero-slot set produces the aggregate row the log-shape aspect prescribes for a timer-only set, with no slot rows.

5. **Round-based blocks compose heterogeneous slot types.** An AMRAP or round-based block whose slots have heterogeneous work-target metrics — some rep-counted, some distance-counted, some duration-counted — executes with each slot committed in its own shape (reps for the rep slot, distance for the distance slot, duration for the duration slot), and the block's round-counting or cap-bounded completion fires as authored. Mixed metrics within a round do not force any slot into the wrong log shape.

6. **All ten canonical worked examples execute end-to-end.** The ten worked examples documented in the authoring-shape aspect — straight-sets, superset with RIR autoreg, circuit with compound load+distance on one slot, cluster bench, EMOM mixing strength and cardio, AMRAP compound round, for-time with distance+reps, Tabata as sibling work+rest, intervals with HR-zone stimulus, loaded carry — each pull, seed, execute, log, and push without error. This is the direct proof of spec A2.

## QA contract

**Phase gate — deterministic, fast, blocks Phase 4 close.**

- **AC1** is proven by a cluster execution test: seed a cluster fixture, drive through every sub-slot to the top-level set commit, assert each sub-slot landed a log row with the authored reps and the inter-slot rest duration. Reverse-patch: a seed-time collapse of the cluster to a single slot breaks the multi-row assertion; a driver that skips intra-slot rest breaks the rest-duration assertion.
- **AC2** is proven by a work+rest sibling test at two authored cadences — the Tabata 20/10 and one non-Tabata cadence (e.g., 30/15). Both execute to completion with the authored windows, round counts, and log rows per repeat. Reverse-patch: a driver that hardcodes the 20/10 cadence regresses the non-Tabata cadence test; a port that treats the rest set as a zero-duration transition regresses the Tabata test's rest window.
- **AC3** is proven by a compound-work-target execution test on a loaded carry fixture (load + distance) and a weighted hold fixture (load + duration). Both fixtures drive to completion and write both dimensions on the log row. Reverse-patch: a log-row writer that drops load for a distance-shaped slot regresses the carry; a slot that rejects the dual work target at seed time regresses both.
- **AC4** is proven by a zero-slot rest-set execution test: a block with a work set followed by a zero-slot rest set executes, advances through the rest set as a pure timer, and reaches the next set or block completion. The zero-slot set produces an aggregate row; it produces no slot rows. Reverse-patch: a seeder that errors on empty-slots breaks execution; a driver that tries to commit a slot during the timer breaks the "no slot rows" assertion.
- **AC5** is proven by a heterogeneous-AMRAP test: an AMRAP fixture with a rep slot, a distance slot, and a duration slot inside one round executes with each slot committed in its own shape, and the round counter increments after all three slots commit in order. Reverse-patch: a cursor that treats all slots as rep-shaped regresses the distance and duration commits; a round-counting implementation tied to slot count rather than round completion regresses the counter assertion.
- **AC6** is proven by ten end-to-end round-trip tests, one per worked example, each driving the example to completion and asserting the pushed log rows match the authored configuration. This is the direct A2 proof. Reverse-patch: any single worked example that doesn't round-trip breaks its own test; no shortcut covers all ten.

**RC gate — one manual smoke on a novel pattern.** Before phase close, one manual simulator smoke on a cluster workout or a custom-cadence work+rest workout (whichever pattern is hardest to verify by test alone) is run. The smoke is not a deterministic phase gate but exists to catch integration surprises that per-test baselines miss.

## Scope

**In scope**:
- Execution support for the five compositional patterns above — cluster, sibling work+rest, compound targets, zero-slot rest sets, heterogeneous round slots.
- Driver changes needed to read the composition — intra-slot rest anchors, sibling-set iteration within a repeat, dual-dimension slot reads, zero-slot cursor advancement, heterogeneous-slot round counting.
- Session-state shape extensions needed to carry these compositions through pause-and-resume.
- Fixtures for the ten canonical worked examples, driving them end-to-end.
- Retirement of the superseded cluster-rest-pause architecture plan as its target behavior is subsumed by this phase.

**Out of scope**:
- Correction semantics for the new patterns beyond the idempotent-upsert invariant already enforced. Phase 5 (deferred) owns correction + history.
- History query shape changes needed to surface cluster + work+rest + compound rows correctly. Phase 5 (deferred) owns that.
- Documentation that describes the new patterns to Claude as author and Eric as reader. Phase 6 (deferred) owns the docs sweep, including `docs/prescription.md` and `docs/workout-generation.md` rewrites.
- Any new primitive beyond the seven the spec pins. If an authored pattern that Eric asks for cannot be composed from existing primitives, the phase escalates — a new primitive is a spec change, not a phase-scope expansion.
- UI component primitives that mirror the model primitives. The concept doc notes that editor/logger/preview can compose from a UI primitive set; building that UI is separate scope, downstream of this phase plan.

## Constraints

- The primitives spec pins seven primitives. Phase 4 does not add an eighth. If a pattern requires one, the phase stops and the spec is amended.
- Idempotent upsert holds for the new log-row shapes. A cluster's sub-slot rows, a work+rest block's aggregate rows, a compound slot's dual-dimension row — each round-trips without duplication.
- Offline-first invariant holds. Executing a cluster or a compound carry does not depend on network.
- The behavior-preservation invariant from Phase 3 holds for already-ported patterns. Adding Phase 4's capabilities must not regress any of the twelve timing modes' baselines.
- Stakeholder acknowledgment is the capability test: Eric must be able to describe what he can now do that he could not do before. If a pattern technically executes but Eric cannot author it from a conversational prompt without contorting the description, the phase has shipped the mechanism and missed the outcome.

## Ordering within the phase

1. Zero-slot rest sets land first. They are the smallest compositional capability and their landing validates that the seeder and cursor can handle empty-slot structures without special-casing.
2. Sibling work+rest lands next. It depends on zero-slot rest existing but extends the seeder to iterate sibling sets under a block repeat.
3. Compound work targets land next. They are a slot-shape extension, largely orthogonal to the structural changes above, but their landing exercises the log-shape aspect's multi-metric row.
4. Cluster execution lands after the simpler structural changes. Cluster is the case where the superseded plan's intra-slot rest concerns live; getting the earlier compositions right first means cluster is primarily a driver-side port rather than a session-state invention.
5. Heterogeneous round slots land last. They exercise the cursor and round-counting surface most heavily and benefit from the other compositions being settled before this one tests them in combination.
6. The ten worked examples' end-to-end tests land after each corresponding capability lands. Running all ten green is the phase's closing gate.

## Known hazards

- **Cluster authoring ergonomics versus primitive fidelity.** The spec's Q-H open question names a tension: a cluster authored as "one slot with sub_sets metadata" is shorter to write than "one set with N slots, same exercise, per-slot reps, post-rest." The spec's preference is the explicit multi-slot form. Phase 4 implements the explicit form; an implementer who encounters an existing fixture in the short form should convert it, not support both.
- **Work+rest cadence flexibility surfacing a spec gap.** If any work+rest cadence Eric wants to author cannot be expressed as `work_set.timing + rest_set.timing + block.repeat`, the primitives compose but the spec's timing enum is incomplete. The phase escalates; the spec is amended before more drivers read the gap.
- **Compound work target log-row shape.** The log-shape aspect names the multi-metric row. A driver port that writes a compound slot's row by treating one dimension as the metric and the other as a sidecar (weight-as-modifier rather than weight-as-target) violates the shape even if the values land. The assertion on AC3 must inspect the row's metric-tagging, not just the values.
- **Zero-slot rest set's aggregate row shape.** A pure-timer set produces no slot rows but does produce an aggregate row. An implementer who treats "no slots means no rows" regresses the aggregate production. The log-shape aspect's set-result-row semantics must be read carefully here.
- **Heterogeneous round cursor versus current round-robin semantics.** Phase 3's round-robin ports assumed slots within a round share a shape. Heterogeneous rounds break that assumption. An implementer who extends the Phase 3 cursor without reconsidering its slot-shape assumption may introduce a regression on a previously-uniform round-based fixture.
- **The superseded cluster-rest-pause plan was mid-design.** Its concerns — where intra-slot rest lives in session state, how driver log-mutation separates from block-level rest, how autoreg interacts with partial-cluster completion — are not invalidated by being superseded; they are now Phase 4's concerns under different structural names. An implementer should read that plan's Pressure Map before writing the cluster port.

## Proof commands

Phase-close gate: the per-mode suites from Phase 3 still pass (no regression), plus the new compositional-pattern suites and the ten worked-example round-trip suite all pass.

RC gate: one manual simulator smoke on cluster or custom-cadence work+rest before phase close.

## Handoff to implementation-planning

Do not use this file directly as the implementation-planning input. Use
`PDM-GAP-*` rows in the owning primitives spec files first, then consult this
phase only for prior decomposition and hazards.
