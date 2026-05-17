---
title: Phase 3 — All twelve current timing modes execute with behavior parity
status: backlog
last_reviewed: 2026-04-29
purpose: Third phase of the primitives-data-model cutover. After this phase, every timing mode Eric uses today runs under the primitive model with observable behavior matching the pre-cutover baseline.
parent: ./README.md
spec:
  - docs/specs/primitives-data-model.md
  - docs/specs/primitives-data-model/runtime-resolution.md
---

# Phase 3 — All twelve current timing modes execute with behavior parity

## Unit statement

After this phase, every timing mode the app supports today — straight-sets, superset, circuit, AMRAP, EMOM, Tabata, intervals, continuous, for-time, accumulate, rest-block, and custom — executes end-to-end under the primitive model with observable behavior matching the pre-cutover build. Any behavior that diverges from the baseline is either an intentional spec change with a documented justification, or a bug to be fixed before the phase closes.

## Why

Phase 2 proved the execution pattern works for the simplest timing mode. Phase 3 is where the rest of Eric's training gets ported, which is the load-bearing claim of spec acceptance criterion A1: "every timing mode Eric uses today continues to work." Without Phase 3, merging the cutover would regress Eric's ability to run the workouts he actually does — supersets, circuits, conditioning, cardio. That's not acceptable; the cutover must not be a functional downgrade.

The stakeholder is Eric as user on the branch build. After this phase, every workout type he could run yesterday he can still run today. Rest timings are unchanged from his felt experience. Autoreg proposals fire at the same moments. The cardio display reads the same way. EMOM minute boundaries advance at the same wall-clock instants. He does not notice the cutover happened — and that's the goal.

This phase is also the place where a hidden gap in the primitive contract (a driver that needs a signal the contract doesn't carry) surfaces with greatest force. If such a gap exists, Phase 3 is where the cost of the earlier phases' contract freeze gets paid. The phase spec names this hazard explicitly so the implementer treats driver ports as probes on the contract, not just as translations.

## Acceptance criteria

1. **Every timing mode executes to completion.** For each of the twelve timing modes the app supports today, a representative fixture workout can be driven through to its completion state without error, crash, or silent divergence. "Driven to completion" means: every commit lands a log row (or deliberately doesn't, for rest-bounded work windows), every cursor transition follows the authored configuration, completion is reached on the mode-appropriate trigger (last slot, time cap, rounds exhausted, distance met).

2. **Observable behavior matches the pre-cutover baseline.** For every timing mode, the observable behavior captured against the pre-cutover build — cursor transition sequence, rest ring durations at each transition, autoreg proposal trigger moments and values, completion signal — is reproduced under the primitive model. A diff between the pre-cutover baseline and the post-cutover run is empty, or every divergence is documented as an intentional spec change with a justification the reviewer can verify.

3. **Timer-sensitive modes preserve boundary behavior.** EMOM minute-boundary advancement, Tabata's 20s/10s/8-round cadence, AMRAP cap expiration, for-time cap handling, intervals work/rest alternation, continuous target coverage, and cap-bounded block termination all fire at the wall-clock moments they fire today. Background-then-resume catchup for EMOM still advances missed intervals without fabricating fake completed rows. The behavior here is not a new implementation from scratch; it is a port that preserves timing semantics.

4. **Round-robin traversal preserves the cursor shape.** Superset and circuit modes walk station-by-station within a round, then bump the round counter, then walk stations again. The new-model cursor produces the same commit sequence the pre-cutover model did. Batch logging versus station-by-station logging follows the authored configuration, not a driver-intrinsic default.

5. **Cardio-shaped logging still routes through the cardio path.** Continuous and intervals modes produce log rows with duration and distance fields populated; they do not fabricate a rep count they didn't observe. Loaded carries and weighted holds log both the load and the duration-or-distance target. A distance-based interval that cannot observe elapsed distance via the available sensors still logs what it can and does not invent values.

6. **Cursor, cap, and work-window persistence survives backgrounding.** An in-flight workout of any timing mode suspended mid-execution, then resumed, continues from the same observable state — cursor position, elapsed block cap, elapsed work window, autoreg scratch, last-logged row all intact. The primitive-model session state carries enough to round-trip across app suspension for every mode this phase ports.

## QA contract

**Phase gate — deterministic, fast, blocks Phase 3 close.**

- **AC1** is proven by a per-mode execution test, one per timing mode, that seeds the mode's representative fixture and drives it to completion. Reverse-patch: a driver that crashes on its own fixture breaks its test; a driver that silently falls through to another mode's behavior breaks the completion-state assertion.
- **AC2** is proven by a per-mode baseline-diff test that runs the post-cutover execution against the pre-cutover baseline captured for that mode and asserts the diff is empty modulo documented divergences. This is the load-bearing A1 proof. Reverse-patch: a silent regression in any observable axis (rest timing, cursor sequence, autoreg trigger, completion signal) breaks the baseline diff on the affected mode's fixture; a change that adds a "fix" without documenting it in the divergence list breaks the diff by surprise.
- **AC3** is proven by the existing timer-boundary suites under the pre-cutover naming, regenerated against the primitive model. The suites exercise minute boundaries, catch-up under suspension, cap expiration mid-logging, and sentinel cadences. Reverse-patch: a port that uses wall-clock minutes instead of anchored intervals regresses the minute-boundary test; a port that clears the anchor on suspension regresses the catch-up test.
- **AC4** is proven by a round-robin traversal test that walks a 3-station × 3-round fixture through both superset (round-rest batched) and circuit (station-rest) configurations and asserts the commit sequence and rest durations. Reverse-patch: a cursor that flattens round-robin to set-major breaks the sequence assertion.
- **AC5** is proven by cardio-shape integration tests for continuous, intervals, and loaded-carry/held cases. Reverse-patch: a rep-shape default on a cardio slot breaks the log-field assertion; a fabricated distance on a sensor-unavailable interval breaks the "does not invent values" assertion.
- **AC6** is proven by a persistence round-trip test per timing mode: start, suspend, resume, assert state matches pre-suspension across the observable axes. Reverse-patch: a session-state field dropped from the persisted shape breaks resume on the mode that reads it.

**RC gate — manual smoke on the most timer-sensitive modes.** Before phase close, a manual simulator smoke is run on EMOM (minute boundaries under suspension), Tabata (20s/10s cadence across the full 8 rounds), AMRAP (cap expiration mid-log), and one round-based mode (superset or circuit). The smoke is not a deterministic phase gate, but the baseline-diff assertions can miss integration-level issues that the smoke catches.

## Scope

**In scope**:
- Porting all twelve current timing-mode drivers to read the primitive-model execution state.
- The execution view-model orchestration for every mode — cursor advancement, cap timers, work-window timers, autoreg dispatch, completion routing.
- The session-state shape extensions needed for modes Phase 2 didn't exercise (round-robin cursor, work-window anchors, round counters, etc.), to the extent the spec's runtime-resolution aspect prescribes them.
- Per-mode behavior baselines captured against the pre-cutover build for the behavior-equivalence assertions.
- Regenerating the per-mode integration fixtures and test suites against the primitive model, preserving pre-cutover assertion intent.
- Cardio-shaped log routing and its interaction with the primitive load + work-target shape.

**Out of scope**:
- Compositional patterns that the old model could not express (cluster with explicit intra-slot rest, sibling work+rest as structural composition rather than Tabata-intrinsic, compound load+distance slots authored outside loaded-carry shortcut, zero-slot pure-timer rest sets as blocks of their own). Phase 4 delivers those.
- Correction semantics beyond what the pre-cutover test surface already covers for each mode. Phase 5 (deferred) owns the primary correction + same-UUID upsert proof.
- History queries that join through the new identity chain. Phase 5 (deferred) owns that.
- Driver consolidation (retiring the hand-coded driver-per-mode pattern in favor of parametric driving from timing/traversal/repeat cells). The spec explicitly defers consolidation as a follow-on spike. Phase 3 ships twelve hand-coded drivers reading the new contract, not four parametric drivers.
- Docs rewrites beyond test fixture content. Phase 6 (deferred) owns those.

## Constraints

- Every existing behavior assertion on the pre-cutover build has a corresponding assertion on the post-cutover build. Tests that exercised a specific behavior pre-cutover continue to exercise that behavior; the assertion text may change with the port but the behavior under assertion does not.
- The offline-first invariant holds for every mode. Execution of a pulled workout proceeds without network dependency.
- Idempotent upsert holds for every mode's log rows. A log-then-edit-then-re-push round-trips without duplication.
- Eric's felt experience running a workout of any mode must be indistinguishable from the pre-cutover experience, except where an intentional spec change is documented. Felt means: rest durations, screen states, rings, prompts, proposals — the user-observable surface.

## Ordering within the phase

1. Port the simpler drivers first — rest-block, continuous, accumulate — before the timer-anchored modes. The simpler drivers exercise the contract broadly enough to catch generic contract gaps; catching them early is cheaper than discovering them in EMOM.
2. Port the round-robin modes — superset, circuit — after the sequential modes. Round-robin cursor semantics are a new primitive-model shape this phase introduces; isolating the port prevents mixing round-robin debugging with simpler-driver debugging.
3. Port the timer-anchored modes — AMRAP, EMOM, Tabata, intervals, for-time — after the non-timed modes. Timer anchoring is the hardest surface in the phase; the other ports' proof surface validates the contract before timer semantics exercise it.
4. Port custom last. Custom switches on multiple prescription shapes and is the highest-risk port; its landing validates that the composition surface covers the edge cases that are otherwise invisible.

After each driver ports, its behavior baseline diff passes before the next driver begins. A failed baseline diff on one mode halts the phase — it is the signal that the contract has a gap or the port has a defect.

## Known hazards

- **Contract gap surfacing late.** A driver whose port reveals the contract doesn't carry a needed signal — EMOM's interval anchor, intervals' distance-based catchup, custom's multi-shape switch, round-robin's cursor state — forces either a contract amendment (which touches Phase 1's substrate) or a driver-internal workaround (which violates the "read against the contract" acceptance). The ordering above front-loads simpler drivers so generic gaps surface early; it does not eliminate the risk that a mode-specific gap surfaces on the last port.
- **Baseline capture fragility.** Baselines captured against the pre-cutover build must be byte-reproducible to diff against post-cutover runs. Any non-determinism in the pre-cutover tests — unordered dictionary iteration, timestamp capture, floating-point rest math — will produce false-positive diff failures. The implementer should confirm baseline stability across multiple pre-cutover runs before trusting the diff as a proof.
- **Intentional divergence disguising regression.** A failed baseline diff is legitimate grounds for declaring an intentional spec change. That's also the easiest way to hide a regression: "this used to be 2.3s rest and is now 2.5s rest — spec change, documented." The review loop must be willing to push back on divergence declarations that lack a clear spec-level justification.
- **Custom driver's multi-shape switch.** The pre-cutover custom driver switches on prescription-enum cases to determine total-set counts and active-content presentation. The primitive-model composition may force some of those cases into a narrower cell than they occupy today. The spec's carve-out for "custom with >1 heterogeneous segment is quarantined" names the escape hatch; the implementer should be prepared to use it if some custom fixture cannot be composed without extending primitives.
- **Round-robin batch-logging versus station-logging.** Superset and circuit modes today carry a `logging_mode` flag that affects UI presentation and cursor advancement. The primitive-model composition has to preserve both flavors as authored options; a port that collapses them to one behavior loses AC4.
- **Timer-drift on resume.** The pre-cutover app recovers minute-boundary anchors from persisted state, not wall-clock alone. A port that anchors on wall-clock at resume drifts against the authored schedule in ways that catch-up tests might not surface if the test's synthetic clock doesn't reproduce the relevant suspension window.

## Proof commands

Phase-close gate: the full per-mode integration suite runs green, including the behavior-baseline diff for every mode. The level is "every timing mode's proof is green," not a specific command.

RC gate: a manual simulator smoke on EMOM, Tabata, AMRAP, and one round-based mode before phase close.

## Handoff to implementation-planning

This phase spec is the input to `scoping:implementation-planning`. The implementation plan produced there carries the code-altitude decomposition (which drivers, in what order, against which behavior baselines, with which session-state extensions). An implementation plan that surfaces a contract gap during a driver port routes back to the spec aspect or to phase-planning before proceeding — not to requirements-planning, unless the gap reveals the durable requirement itself is under-specified.
