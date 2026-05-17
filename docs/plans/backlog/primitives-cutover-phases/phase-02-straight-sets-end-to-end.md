---
title: Phase 2 — Straight-sets block executes end-to-end under primitives
status: backlog
last_reviewed: 2026-05-17
purpose: Second phase of the primitives-data-model cutover. After this phase, Eric can run a straight-sets workout on the branch build under the primitive model — the full loop from pull through execution through log through push works for one representative timing mode.
parent: ./README.md
spec:
  - docs/specs/primitives-data-model.md
  - docs/specs/primitives-data-model/runtime-resolution.md
  - docs/specs/primitives-data-model/log-shape.md
---

# Phase 2 — Straight-sets block executes end-to-end under primitives

## Unit statement

After this phase, a straight-sets block authored in the primitive vocabulary can be pulled to the app, driven to completion by the user, logged to local storage, and pushed to the server — end to end under the new model. Other timing modes do not yet execute; the branch intentionally fails or stubs those modes until Phase 3. This phase proves the execution pattern works for one representative mode before Phase 3 fans the pattern out to the remaining eleven.

## Why

Straight sets are the most common timing mode Eric runs today (the 2026-04-25 feedback session was dominated by straight-sets work). If the execution pattern under primitives doesn't work for straight sets, it doesn't work at all — the pattern is wrong, not a driver bug.

Straight sets are also the simplest case of the new composition: sequential traversal, set-bounded timing, one slot per set, no repeat at the block level, no work+rest siblings, no cap, no round-robin. A straight-sets execution proof exercises the load-bearing seams (pull → seed → cursor advancement → rest timing → log row → push → server ingest) without the timing-mode complexity that Phase 3 will stress (minute boundaries, round-robin, cap escapes, distance-based intervals, etc.). Breaking the pattern on those edge cases is expected in Phase 3; breaking it on straight sets means the primitives can't support execution at all.

The stakeholder is Eric as user on the branch build: after this phase, he can run a straight-sets workout through the branch and see the log land correctly. Anything else he tries is expected to fail visibly — the phase is not lying about its scope.

## Acceptance criteria

1. **Authored straight-sets round-trip through execution.** A primitive-vocabulary straight-sets workout pulled to the app can be driven from first-slot to last-slot to completion without the user hitting an error, a crash, or an unexpected state transition. Every slot commit produces a log row; the workout's completion produces whatever aggregate rows the log-shape aspect prescribes for a no-repeat, no-rounds block.

2. **Rest timing matches the authored configuration.** Between-set rest duration, between-exercise rest duration, and completion behavior on the final slot of the block all derive from the authored primitive configuration (set-level `post_rest_sec`, slot-level `post_rest_sec`, block timer absence) rather than from hardcoded fallbacks. Two workouts authored with different rest values produce different observed rest durations.

3. **Load resolution carries through to the log row.** A slot authored with a relative load (percent-of-1RM) executes with the resolved absolute load on the active screen and logs the resolved absolute value. A slot authored with an absolute load preserves the authored value. A slot authored with implicit bodyweight logs without a load field.

4. **Autoreg proposals fire on the straight-sets path.** When a slot is authored with an autoreg rule tied to an RIR stimulus and the user logs an RIR that triggers the rule, the autoreg proposal appears and its accept/undo behavior matches pre-cutover observable behavior. When no autoreg rule is authored or the trigger condition is not met, no proposal appears.

5. **Local log rows push to the server.** A logged straight-sets workout's log rows are encoded into the push queue and delivered to the server's sync endpoint. The server's stored rows carry the composite identity (slot, set-repeat, block-repeat, role) that the log-shape aspect specifies. A client-side edit of a past slot re-pushes against the same composite identity and the server replaces the row in place rather than duplicating it.

6. **Other timing modes fail visibly without crashing.** A workout authored with any non-straight-sets block (superset, circuit, AMRAP, EMOM, Tabata, intervals, continuous, for-time, accumulate, cluster, or custom) fails to start with a clear "not yet supported" state that names the mode. It does not crash and it does not silently execute under the wrong semantics. This criterion is an honesty gate: the branch must not pretend to run modes it has not yet ported.

## QA contract

**Phase gate — deterministic, fast, blocks Phase 2 close.**

- **AC1, AC2, AC3** are proven by a straight-sets execution test that seeds a known fixture, drives the session through every slot to completion, and asserts the observed rest durations, cursor transitions, and log-row shape match both the authored configuration and the behavior baseline captured from the pre-cutover build. Reverse-patch: changing a rest duration in the driver without updating the authored fixture breaks the test; dropping a log field on commit breaks the log-row shape assertion; regressing rest timing silently breaks the baseline diff.
- **AC4** is proven by an autoreg-on-straight-sets test that seeds a fixture with an RIR autoreg rule, logs sequences of RIR values that do and do not trigger the rule, and asserts the proposal appears exactly in the expected cases. Reverse-patch: a change that fires autoreg on every commit breaks the non-trigger case; a change that skips autoreg always breaks the trigger case.
- **AC5** is proven by a push-round-trip test that logs a straight-sets workout, drains the push queue to the server, and asserts the server's stored rows match the client-pushed payload. A follow-on edit test repeats the push with a modified value on one row and asserts the server's row count is unchanged and the values are updated. Reverse-patch: a change that duplicates rows on edit breaks the row-count assertion; a change that drops a composite-identity component breaks the match assertion.
- **AC6** is proven by a negative test per non-straight-sets timing mode: attempt to start a workout of that mode, assert the app routes to a "not yet supported" state and remains stable. Reverse-patch: a crash or silent fallback to the straight-sets driver on an un-ported mode breaks the assertion that the mode fails visibly and safely.

**RC gate — one manual smoke.** A real straight-sets workout executed on the iOS simulator end-to-end, with rest-ring timings and log rows observed in the local store, is run once before the phase closes. The smoke is not a deterministic phase gate, but it is required before the phase's QA declaration is honest about what "works end-to-end" means for the user.

## Scope

**In scope**:
- The execution path for straight-sets workouts under the primitive model: pull, seed, cursor advancement, rest timing, log-row production, push.
- The one representative driver for straight-sets timing (whatever it's called after the cutover — the driver stays hand-coded, per the spec's OQ-1 deferral).
- The execution state that the straight-sets driver reads and the execution view-model that orchestrates it — enough of each to support this mode.
- The push queue's encoding of a straight-sets log row and the server's ingest of that shape.
- Behavior baselines captured from the pre-cutover build for the assertions that compare observable behavior across the cutover.
- The visible-failure surface for un-ported timing modes.

**Out of scope**:
- The remaining eleven timing modes. Phase 3 ports them.
- New compositional patterns (cluster, sibling work+rest, compound work targets, zero-slot rest sets). Phase 4 delivers those.
- History queries, correction semantics beyond same-row upsert on one slot, aggregate-row writes for cap-bounded or round-based blocks. Phase 5 (deferred) owns those.
- Docs describing the new execution model. Phase 6 (deferred) owns that.

## Constraints

- The repo's complete-cutover philosophy still applies at the merge boundary. On the branch mid-phase, un-ported timing modes may fail — that's the honesty gate in AC6. At merge, every timing mode works and no unsupported-mode scaffold remains (that's what Phases 3 and 4 deliver before merge).
- The offline-first invariant holds. Execution of a pulled straight-sets workout does not depend on the server being reachable.
- The idempotent-upsert invariant holds for the one mode this phase ports. A logged-then-edited slot round-trips without duplication.
- The single-user dev posture holds. No multi-user conflict resolution is introduced.

## Ordering within the phase

1. The behavior baselines are captured first, against the pre-cutover build, before any execution code changes. Without the baselines, AC1 and AC2's assertions have nothing to compare against.
2. The execution state and view-model changes land next — the substrate the driver reads and writes against.
3. The straight-sets driver port happens against the new substrate. This is the load-bearing change of the phase.
4. Push + server ingest for the straight-sets log shape lands last, closing the loop.
5. The visible-failure surface for un-ported modes can land any time before phase close, but should land with enough dignity that Phase 3's implementer reads it as a scaffold, not a hack.

## Known hazards

- **Baseline capture against a moving target.** If the pre-cutover behavior baseline is captured mid-implementation (after some speculative changes have already landed on the branch), the baseline will include those changes and the behavior-equivalence claim becomes meaningless. The baseline must come from a clean pre-cutover commit; confirming which commit is "pre-cutover" before capture is the first operational step.
- **Rest timing regression from driver-intrinsic defaults.** The pre-cutover straight-sets driver has specific handling for last-set-of-item-with-next-item-in-block using between-exercise rest instead of between-sets rest. A port that doesn't preserve this regresses observable rest timing in a way the behavior baseline will catch but that a cursory test pass will not.
- **Autoreg proposal timing is subtle.** The pre-cutover driver skips autoreg on the last set of a sequence. A port that forgets this fires autoreg at the wrong moment. AC4's test needs to include both "fires on non-last set" and "does not fire on last set" cases.
- **Push-queue envelope shape change.** The push queue today persists payloads in the legacy shape. A pushed-but-not-yet-drained queue at the moment of cutover would attempt to deliver legacy payloads against the new server endpoint — those payloads will fail ingest. In dev-mode single-user, the mitigation is to drain the queue against the pre-cutover server before deploying, or accept that any queued pre-cutover payloads are lost. This is an operational note for the implementer, not a code change.
- **Un-ported-mode failure surface is where shortcuts hide.** The easiest way to make un-ported modes "fail visibly" is a fallthrough to the straight-sets driver with a warning. The easiest way to make AC6's test pass against that implementation is to assert on the warning. This satisfies the letter of AC6 and violates its spirit — the un-ported mode silently executes under wrong semantics while looking "handled." The implementer should avoid the fallthrough and route un-ported modes to a clear unsupported state.

## Proof commands

Phase-close gate: the full contract + schema + straight-sets execution suite runs green, including behavior-baseline diffs.

RC gate: one manual straight-sets simulator smoke before phase close.

## Handoff to implementation-planning

This phase spec is the input to `scoping:implementation-planning`. The implementation plan produced there carries the code-altitude decomposition (which execution-state types change, which driver is ported, which view-model responsibilities move, which test fixtures land). An implementation plan that needs this phase spec to resolve an ambiguity about outcome — what functionality ships, what proof binds it — routes back here.
