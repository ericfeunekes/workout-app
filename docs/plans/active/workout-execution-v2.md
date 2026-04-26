---
title: Workout execution v2 implementation plan
status: active
purpose: Build the accepted workout execution target flows in small, reviewable slices.
covers:
  - docs/workout-execution-design-plan.md
  - docs/workout-execution-requirements.md
  - app/Packages/Core/Session/
  - app/Packages/Features/Execution/
---

# Workout execution v2 implementation plan

## Unit Statement

Bring the iOS execution surface into alignment with the target workout-flow model: explicit set boundaries, mode-appropriate transitions, result capture, completion summaries, and simulator QA coverage.

This is an umbrella plan made of small build slices. Each slice must be independently implemented, tested, and reviewed before the next slice starts.

## Recovery Context

Implementation owner: main agent or a worker subagent briefed from this file.

Review owner: independent Codex/cxd read-only review at every milestone, plus focused simulator QA when UI behavior changes.

Primary target docs:

- `docs/workout-execution-requirements.md`
- `docs/workout-execution-design-plan.md`
- `docs/prescription.md`

Primary code surfaces:

- `app/Packages/Core/Session/Sources/CoreSession/`
- `app/Packages/Features/Execution/Sources/FeaturesExecution/`
- `app/Packages/Features/Execution/Tests/FeaturesExecutionTests/`

Expected proof:

- Focused Swift package tests for the touched execution package.
- Xcode simulator build/run and manual QA for user-facing timer/transition changes.
- Independent read-only review before marking any milestone complete.

Closeout:

- Feature docs updated when current implementation behavior changes.
- `docs/bugs.md` updated only for current bugs, not unbuilt target behavior.
- This plan's milestone checklist updated after proof and review.

## Current Gap Summary

The target requirements are drafted and M1-M7 are implemented. These are follow-on gaps outside this slice.

Remaining implementation gaps:

- Composite set slots are not a session primitive.
- For-time result capture is basic and not yet split-tracking/cap-partial complete.
- Composite for-time split rows are not yet modeled.
- Distance-target accumulate work is represented in schema/display, but real loaded-carry style entry still needs sensor/manual metric-entry UX.

## Milestone Checklist

- [x] M1: Set-based work-boundary slice implemented, tested, reviewed, and simulator-checked.
- [x] M2: Metcon result slice covers AMRAP and for-time result/cap behavior.
- [x] M3: Round-robin slice resolves station-log vs batch-log behavior.
- [x] M4: Scheduled interval and rest-transition slice resolves manual/detectable/auto boundaries.
- [x] M5: Continuous and accumulate-target slice covers endurance and free-bout work.
- [x] M6: Completion/result summary slice gives every block a visible result state.
- [x] M7: QA fixture matrix covers every archetype happy path and boundary path in simulator.

## M1: Set-Based Work Boundary

Goal: `straight_sets` must have an explicit work boundary. Broader set-like modes stay unchanged until their own milestones.

Behavior to deliver:

- After starting a straight-sets workout, Active shows a ready/prep timer and `Set Start`.
- `Done` is unavailable until the current set has started.
- Tapping `Set Start` stamps the current set's work start time.
- Active set shows elapsed set time and `Done`.
- Tapping `Done` opens the existing actual-entry sheet for this first slice.
- Actual logging remains the commit moment for now; do not create default/draft logs that would push or autoreg against fake actuals.
- Rest expiry becomes red over-rest and continues until the next `Set Start`.
- Clock-owned and round-robin modes keep their own boundary behavior; this slice must not break AMRAP, for-time, EMOM, Tabata, intervals, continuous, superset, circuit, or custom.

Likely approach:

- Add a session-level ready/prep anchor that can run while `workStartedAt` is nil.
- Add a mutation/view-model intent for `startCurrentSet`.
- Guard straight-sets logging so it cannot commit before `startCurrentSet`.
- Keep the existing `LogSetSheet` commit path for actuals in M1a.
- Update timer presentation so active set-like ready state is a prep/ready count-up, while active started state is set elapsed.

Proof map:

- Feature test: straight-sets `start()` does not stamp set work start until `startCurrentSet`.
- Feature test: `startCurrentSet` stamps work start and timer presentation switches to set elapsed.
- Feature test: straight-sets `logSet` before `startCurrentSet` is ignored.
- Feature test: straight-sets `Done`/log sheet affordance is unavailable before set start and becomes available after.
- Feature test: rest expiry presentation remains red over-rest and add-time still works.
- Regression tests: AMRAP `Next`, for-time `Finish`, EMOM boundary, Tabata work window, intervals cardio logging still pass.
- Simulator QA: one straight-sets workout from start through over-rest and next set.

Review gate:

- Run independent read-only review focused on state-machine correctness, accidental breakage to non-strength modes, persistence/relaunch behavior, and whether tests prove the target behavior rather than the old behavior.

Completion evidence:

- Implemented for `straight_sets` only: Active starts in READY with `set start`; `workStartedAt` is nil until `startCurrentSet`; logging is guarded until Set Start; `Done` opens the existing actual-entry sheet after Set Start.
- Added restore back-compat marker so legacy active straight-set snapshots normalize to READY, while current post-Set-Start restores preserve `workStartedAt`.
- Proof: `swift test` in `app/Packages/Features/Execution` passed 312 tests.
- Review: independent M1a review found a legacy restore bypass; follow-up review was clean after the marker/normalization fix.
- Simulator: `build_run_sim` succeeded, then debug launch with `--start-active --debug-mode=straight_sets` verified READY → set start → SET ELAPSED/done → log sheet → Rest → next set READY.

Escalation triggers:

- If immediate rest requires first-class partial/default logs that conflict with push semantics, stop and decide whether to introduce draft logs or delay push until rest-time commit.
- If too many existing tests encode old `start() == workStartedAt` semantics, update only after confirming intended behavior; do not blindly align tests to code.

## M2: Metcon Results

Goal: AMRAP and for-time blocks produce goal-level results, not just incidental set rows.

Behavior to deliver:

- AMRAP global cap remains primary.
- `Next` stamps current station complete.
- Buzzer partial captures only current unfinished station.
- For-time supports finish-only total duration.
- For-time split-tracking and cap partial behavior are implemented or explicitly deferred with a narrower current contract.

Proof:

- Unit tests for AMRAP station rows, partial sheet model, and summary result.
- Unit tests for for-time finish result and cap behavior.
- Simulator QA for AMRAP and for-time.
- Independent review before moving on.

Completion evidence:

- AMRAP `next` remains station completion, but the VM now refuses post-cap station logs so the global cap owns the boundary even before the next SwiftUI timer tick.
- AMRAP partial save appends a goal-level `AMRAP result: N rounds + M reps` note derived from completed prior stations plus current partial reps.
- AMRAP stale/duplicate result callbacks are mode-guarded so they cannot mutate the next block after routing.
- For Time is explicitly narrowed to finish-only for M2: tapping `finish` immediately logs one total-duration result; expired caps no longer auto-complete or silently drop the score. Cap partial/split tracking remains deferred to a later slice.
- Proof: `swift test` in `app/Packages/Features/Execution` passed 316 tests.
- Review: independent M2 challenge found the For Time silent-cap loss and two-step finish behavior; post-fix review found an AMRAP post-cap `next` race; follow-up review was clean after the VM-level cap guard and stale-callback guards.
- Simulator: `build_run_sim` succeeded. Debug launch with `--start-active --debug-mode=for_time` verified `TIME CAP` + direct `finish` to completion with a total-duration row. Debug launch with `--start-active --debug-mode=amrap` verified `AMRAP CAP`, `next` station advancement, partial result sheet with completed/current rows, and completion ledger after saving.

## M3: Round-Robin Logging

Goal: supersets/circuits have an explicit station-log vs batch-log behavior.

Behavior to deliver:

- Station cursor remains ordered through rounds.
- Batch-log mode exposes group actuals at shared round rest.
- Station-log mode stamps each station when advanced.
- RIR/load controls appear only for authored strength-like stations.

Proof:

- Superset fixture and tests for shared rest batch logging.
- Circuit fixture and tests for station logging.
- Simulator QA on 2-station and 3-station examples.
- Independent review.

Completion evidence:

- Added `timing_config_json.logging_mode` for round-robin strength work: `superset` defaults to `batch_at_round_rest`, `circuit` defaults to `station_by_station`, and both accept explicit overrides.
- Superset batch mode now advances station-to-station without opening the set sheet. Shared round rest exposes every station in the completed round for load/reps/RIR corrections; `next` commits those rows before advancing.
- Final superset rounds commit before completion so the no-rest tail does not drop the last round.
- Circuit station mode remains the default and keeps the existing one-row-per-station logging path.
- Independent review: first pass found the batch timestamp blocker; follow-up review returned no concrete M3-blocking findings.
- Simulator QA: 2-station superset defaulted to batch-at-round-rest, advanced with `next station` / `finish round`, exposed `ROUND LOG` for both stations, committed on `next`, and resumed round 2. 3-station circuit defaulted to station-by-station, opened the per-station log sheet from `log station`, logged one station, rested, and advanced to the next station.
- UX cleanup from simulator QA: batch round rest now labels the shared rest as `ROUND N COMPLETE` instead of showing the last station name, with the primary `next` action pinned above the tab bar.
- Automated proof: `swift test` in `app/Packages/Features/Execution` passed 319 tests; `swift run CorePrescriptionTests` passed 60 parser cases; `swift run CoreSessionTests` passed 46 reducer cases.

## M4: Scheduled Intervals And Rest Transitions

Goal: automatic boundaries are only automatic when time/sensor-detectable; manual work never silently logs success.

Behavior to deliver:

- Time-owned intervals transition at zero with no grace period.
- Reps/user-judged intervals never fabricate a completed `0 reps` row if the boundary passes.
- First-class missed/partial interval rows remain a later data-model/result-state slice.
- EMOM-style set work can have a running interval clock while still requiring set start/done.
- Strength rest over-rest and interval rest auto-transition are derived from context.

Proof:

- Automated proof: `swift test` in `app/Packages/Features/Execution` passed 328 tests after the final M4 fix.
- Focused proof covered EMOM boundaries/catchup, interval work/rest transitions, Tabata auto-log/rest, and clock-owned rest add-time rejection.
- Simulator QA: strength rest exposes add-time; Tabata clock-owned rest hides add-time and auto-transitions to the next work window; EMOM and interval scenarios were checked in the simulator.
- Independent review/challenge found the clock-owned rest extension bug; fix landed in VM and UI before M4 was marked complete.

## M5: Continuous And Accumulate

Goal: endurance and free-bout work have first-class user-facing flows.

Behavior to deliver:

- Continuous targets notify at duration/distance target and allow complete/continue when standalone.
- Composed continuous blocks auto-transition only when detectable.
- Accumulate target shows accumulated/target, break, editable chunk rows, resume, and end early.

Proof:

- Unit tests for continuous target presentation and completion state.
- Unit tests for accumulate chunks and total update.
- Simulator QA for run/ride style and dead-hang/push-up/carry style examples.
- Independent review.

Completion evidence:

- Continuous duration targets now stamp a visible `TARGET` countdown from workout start. Standalone continuous blocks wait for `complete` or `continue` at target expiry; composed continuous duration blocks route to the next block because the duration boundary is detectable. Distance targets remain manual until sensor-derived distance exists.
- Accumulate is first-class across server schema, Swift schema, parser, execution domain, and debug fixtures. Reps/duration accumulation requires `Set Start`, logs editable chunks, returns to a ready/free-rest state, and routes to the next block or completion when the accumulated target is reached.
- Accumulate uses a target sentinel that cannot be shrunk by swap `sets` overrides; the independent review found this as a blocker and the regression test now pins it.
- Simulator QA verified `--debug-mode=continuous` shows `CONTINUOUS` + `TARGET` + pace guidance, and `--debug-mode=accumulate` shows `ACCUMULATE`, ready/set-start behavior, `BOUT ELAPSED`, and the mode-native `log chunk` sheet.
- Proof: focused `swift test --filter 'AccumulateDriverTests|ExecutionViewModelTickBlockTimerTests|CompleteViewLedgerSwapTests'`, full `swift test` in `app/Packages/Features/Execution`, `swift run CoreSessionTests`, `swift run CorePrescriptionTests`, `swift test` in `schema`, and simulator `build_run_sim`.

## M6: Completion And Results

Goal: every block has a visible result state that matches its goal.

Behavior to deliver:

- Scored blocks show score first.
- Non-scored blocks show completion state first.
- Capped, ended-early, skipped, and completed are distinguishable.
- Corrections update result summaries without live timer/autoreg side effects.

Proof:

- Completion view model tests for representative block results.
- Simulator QA for a mixed workout.
- Independent review.

Completion evidence:

- CompleteView now shows block-level result summaries before the per-exercise ledger, so scored/timed/completion-style blocks have a visible result state at the block level.
- Completion summaries distinguish rest completion, set completion counts, AMRAP result notes, for-time/continuous/cardio duration rows, and accumulate progress against target.
- The legacy per-exercise ledger remains below the block results so load/reps/RIR corrections and review are still visible.
- Simulator QA with `--jump-complete --debug-scenario=timer_gauntlet_strength` verified the `block results` section renders ahead of the ledger and shows per-block completion states.
- Proof: `CompleteViewLedgerSwapTests` covers block-result entries and performed-name ledger behavior; full `swift test` in `app/Packages/Features/Execution` passed after the M6 work.

## M7: QA Matrix

Goal: every accepted archetype has simulator coverage.

Behavior to deliver:

- Debug fixture catalog for all archetypes and boundary paths.
- `scratch/qa-runs/` evidence for each scenario.
- `docs/bugs.md` contains only active current defects found during QA.

Proof:

- XcodeBuildMCP build/run.
- Simulator pass through every matrix row in `docs/workout-execution-requirements.md`.
- Independent QA/challenge review.

Completion evidence:

- DEBUG simulator fixtures now include composed gauntlets for the main execution archetypes:
  `timer_gauntlet_strength` (rest block, straight sets, superset, circuit),
  `timer_gauntlet_clocked` (EMOM, AMRAP, for-time, Tabata), and
  `timer_gauntlet_endurance` (intervals, continuous, custom, accumulate, rest).
- Simulator QA verified the endurance gauntlet starts on an interval with `INTERVAL 1 OF 2`, a visible `WORK` timer, target pace guidance, and a mode-native `log interval 1` action.
- QA evidence is recorded in `scratch/qa-runs/2026-04-25-m5-m7.md`.
- Independent review for M5-M7 found one accumulate target blocker; it was fixed before this milestone was checked.

## Native Checklist Sync

This document is the canonical checklist. Update it at each milestone:

- Leave a milestone unchecked until implementation, proof, review, and docs closeout are complete.
- Record review thread IDs or QA evidence paths under the relevant milestone before checking it.
- If a milestone splits, add a new milestone rather than overloading an existing checkbox.
