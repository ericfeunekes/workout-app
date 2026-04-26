---
title: workout-execution-design-plan
status: draft
purpose: Pass-based plan for aligning workout execution requirements, then designing each user-facing flow.
covers:
  - docs/workout-taxonomy.md
  - docs/workout-execution-requirements.md
  - docs/prescription.md
  - docs/features/execute-loop.md
  - docs/features/timing-modes.md
---

# workout-execution-design-plan

## Purpose

This plan keeps the workout execution work from turning into one large ambiguous redesign. We will move in passes:

1. Align vocabulary and intent.
2. Clean up cross-doc contradictions.
3. Design each athlete-facing flow.
4. Translate flows into implementation units.
5. Build simulator QA coverage from the accepted flows.

The plan is requirements-first. Do not start implementation from a flow until its behavior is documented and reviewed against `docs/workout-execution-requirements.md`.

## Pass 0: Alignment

Status: accepted baseline.

Goal: make sure the docs use one vocabulary and separate user intent from implementation.

Accepted decisions:

- Domains are lenses, not execution contracts.
- Blocks carry human titles and goals.
- Goal type drives timer, transition, and result display.
- Execution archetypes are `set_based`, `round_robin`, `task_for_time`, `time_boxed_max_work`, `scheduled_intervals`, `continuous_target`, `accumulate_target`, and `rest_transition`.
- `max_effort_test` is a goal overlay, not a separate archetype.
- Holds/isometrics are work target kinds, not a separate archetype.
- Segmented continuous work composes from continuous target blocks for now.
- `custom` is an escape hatch, not a primary authoring concept.
- RIR is a strength/hypertrophy target. It is authored per exercise/set when relevant and should not be forced onto non-strength work.

Carry-forward cleanup:

- Pass 1 handles cross-doc contradictions and target-vs-current labeling.
- Passes 2-11 design the athlete-facing flows and QA matrix.

Done when:

- The core vocabulary is stable enough to design flows without re-litigating taxonomy.
- Any later vocabulary change is explicit and updates this pass.

## Pass 1: Cross-Doc Alignment Cleanup

Status: drafted.

Goal: make target behavior, current implementation behavior, and authoring vocabulary point in the same direction without pretending the app already supports the full target model.

Scope:

- Mark `docs/features/execute-loop.md` and `docs/features/timing-modes.md` as current implementation behavior where they conflict with the new target requirements.
- Add a target-vs-current note where `prescription.md` still describes older mode behavior.
- Add a schema-neutral block-result contract to the requirements before deciding persistence.
- Resolve round-robin logging default in the flow design pass.
- Update `docs/AGENTS.md` so agents start from the design plan before changing execution behavior.

Working rule:

- `docs/features/*.md` describe what the code does today.
- `docs/workout-taxonomy.md` and `docs/workout-execution-requirements.md` describe the target execution model.
- `docs/prescription.md` is the bridge: it should only describe authoring shapes the app is expected to execute, and should call out target-only gaps while the implementation catches up.

Done when:

- A reader can tell which document is target behavior vs current implementation.
- No durable doc implies RIR/autoreg applies universally.
- `custom` is consistently described as fallback/escape hatch.
- Known target-vs-current gaps are tracked as implementation units or QA gaps, not hidden contradictions.

## Pass 2: Set-Based Flow

Status: drafted.

Scope:

- Normal strength/hypertrophy sets.
- Explicit `Set Start`.
- `Done` as set-end boundary.
- Automatic rest start.
- Over-rest.
- Rest-screen logging/editing.
- Composite sets.
- RIR targets when authored.
- Autoreg implications.

Key behavior to design:

- Ready state.
- Active set state.
- Rest/log state.
- Composite set collapsed state.
- Composite set guided state.
- Forgotten start recovery.
- Editing just-finished set.
- Completion summary for set-based blocks.

Open implementation questions:

- How to persist composite slot actuals.
- Whether set duration matters enough to edit later.
- How autoreg reads composite-set RIR and actuals.

Done when:

- The flow can be drawn as screens/states.
- QA can validate every timer boundary without inspecting code.
- Implementation can be decomposed into state, UI, persistence, and tests.

## Pass 3: Round-Robin Flow

Status: drafted.

Scope:

- Supersets.
- Circuits.
- Giant sets.
- Non-scored station work.
- Strength-like stations with optional RIR targets.
- Duration/distance/reps stations.
- Between-station and between-round rest.

Key behavior to design:

- Station-by-station transition.
- Shared round rest.
- Whether actual entry is station-by-station or deferred to shared rest.
- What the rest screen shows after a paired/grouped round.
- Completion summary for non-scored round-robin work.

Working assumption:

- Transition through stations happens in order.
- Actual-entry can be deferred to shared rest when authored as batch logging.
- RIR appears only for strength-like stations where authored.

Done when:

- Superset and circuit are clear variants of the same archetype.
- Current `superset`/`circuit` docs can be aligned without ambiguity.

## Pass 4: Task-For-Time Flow

Status: drafted.

Scope:

- For-time blocks.
- Rounds for time.
- Chippers.
- Ladders / rep schemes.
- Optional station/split tracking.
- Optional time cap with partial capture.

Key behavior to design:

- Finish-only mode.
- Station/split tracking mode.
- Detectable station auto-transition.
- Manual station transition.
- Cap partial result sheet.
- End summary with total time and splits.

Working assumption:

- Station/split tracking is author-controlled and usually enabled for metcon/benchmark pieces.

Done when:

- For Time is no longer ambiguous between whole-task finish and station-level tracking.
- AMRAP partial logic is not incorrectly reused where for-time cap semantics differ.

## Pass 5: Time-Boxed Max Work Flow

Status: drafted.

Scope:

- AMRAP.
- Density strength.
- Max calories/distance/reps in cap.
- Single-effort and station-based variants.

Key behavior to design:

- Global cap as primary timer.
- Station completion.
- Partial current station at buzzer.
- Single repeated effort accumulation.
- End early.
- Summary: rounds + reps / total work.

Done when:

- AMRAP and density work share the same goal model but keep appropriate displays.

## Pass 6: Scheduled Intervals Flow

Status: drafted.

Scope:

- EMOM.
- E2MOM / every-N-minute.
- Tabata.
- Time intervals.
- Distance intervals.
- Attached interval goals.

Key behavior to design:

- Time-owned boundaries.
- Sensor-detectable boundaries.
- Manual boundaries for reps/user-judged work.
- Auto-transition notification.
- No hidden grace periods.
- Transition/rest slots.
- Missed interval logging.
- Split summary.

Done when:

- Interval behavior is fully determined by boundary detectability and attached goal.

## Pass 7: Continuous Target Flow

Status: drafted.

Scope:

- Easy/base runs.
- Target duration/distance efforts.
- Pace/zone guidance.
- Standalone continue behavior.
- Auto-transition when part of a composed sequence.

Key behavior to design:

- Target progress.
- Continue vs complete at target.
- Secondary target display.
- Composed continuous blocks for progression/tempo structures.
- Overall timer alongside current block timer when a larger composed thing is timed.

Done when:

- Running/endurance flows do not require `custom` unless no stricter block composition fits.

## Pass 8: Accumulate Target Flow

Status: drafted.

Scope:

- Accumulate duration.
- Accumulate reps.
- Accumulate distance.
- Free-rest bouts.
- Detectable and non-detectable chunks.

Key behavior to design:

- Accumulated / target display.
- `Break`.
- Chunk rows.
- Inline chunk editing.
- Resume.
- Completion summary.

Done when:

- Dead hang, push-up, and carry examples all have clear behavior.

## Pass 9: Rest / Transition Flow

Status: drafted.

Scope:

- Strength between-set rest.
- Clock-driven transition rest.
- Rest inside scored work.
- Standalone rest blocks.

Key behavior to design:

- Manual-start rest.
- Auto-transition rest.
- Over-rest.
- Add time.
- Rest labels: rest, transition, easy, recovery.

Done when:

- Rest behavior is determined by context and does not require special-case guessing.

## Pass 10: Completion And Result Flow

Status: drafted.

Scope:

- Per-block results.
- Overall session stats.
- Non-scored completion.
- Detail drill-down.
- Notes.
- Corrections.

Key behavior to design:

- Per-block result cards.
- Scored vs non-scored block order.
- Split/detail display.
- Strength progression summaries.
- What requires first-class block result vs reconstructed logs.

Done when:

- The block-result persistence decision has enough flow evidence to decide.

## Pass 11: QA Matrix

Status: drafted.

Scope:

- Convert accepted flows into simulator scenarios.
- Add debug fixtures for archetype coverage.
- Separate current-implementation QA from target-flow QA.

Done when:

- Every archetype has at least one happy path and one boundary path.
- Every timer boundary has a visible expected state.
- Every user override has a reproducible simulator scenario.
