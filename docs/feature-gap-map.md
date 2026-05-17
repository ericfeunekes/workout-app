---
title: Feature gap map
status: living
last_reviewed: 2026-05-17
purpose: Cross-feature index of target behavior that is not implemented or not yet proven.
covers:
  - docs/features/
  - FEEDBACK-AND-SPEC-2026-04-25.md
---

# Feature Gap Map

Feature docs describe the target behavior. Their `Current gaps` sections are the
source of truth for what has not landed or has not been proven yet. This map is
the sequencing view: it groups those gaps into implementation-sized phases so
planning can happen without re-reading every feature doc.

Do not put implementation steps here. Those belong in `docs/plans/active/` once
a phase is selected.

## Status Fields

| Field | Meaning |
|---|---|
| `current_state` | `open`, `partially_built`, `built_unproven`, or `resolved`. |
| `proof_type` | Strongest proof currently available: `none`, `code_inspection`, `test_result`, `simulator_observation`, or `inspection_inconclusive`. |
| `phase` | Proposed implementation grouping. The docs pass fills this from feedback priority and obvious delivery clusters; implementation planning may reshuffle. This is not approval to build. |

## Phase Authoring

The first version of this map uses priority-as-default:

- P0 proof and fixes come first.
- P1 UX clusters are grouped by delivery shape: preview/edit, active/rest redesign, transition, execution data, and history/edit.
- Schema cutovers stay grouped when they share the same migration and parity work.
- P2/P3 items stay as later polish or future design unless a selected implementation plan pulls them forward.

When implementation planning starts, update `phase` to match the selected slice
instead of preserving this initial ordering by habit.

## 2026-04-25 Feedback Gaps

| gap_id | feature_doc | target_section | feedback_ids | current_state | proof_type | phase | notes |
|---|---|---|---|---|---|---|---|
| FG-001 | `docs/features/execute-loop.md` | Rest face state copy | #5 | resolved | simulator_observation + test_result + codex_review | P0 proof + fixes | Dead "waiting to start" copy is removed from execution surfaces; explicit-start active work uses `READY` as the prep timer. Proof: `ExecutionTimerPresentation` tests, Codex thread `019dcbb2-85e7-7340-ba0c-eb4ee8a8007f`, and `scratch/qa-runs/phase-05-transition-active-after-start-final.jpg`. |
| FG-002 | `docs/features/today.md`, `docs/features/workout-preview.md` | Preview CTA hit targets | #12 | open | none | P0 proof + fixes | Needs simulator observation or UI test; code inspection is not enough. |
| FG-003 | `docs/features/execute-loop.md`, `docs/set-edit-sheet.md` | Primary CTA enabled/disabled contrast | #16 | open | none | P0 proof + fixes | Same likely shared-button root as FG-002; needs visual proof. |
| FG-004 | `docs/features/execute-loop.md`, `docs/set-edit-sheet.md` | Bodyweight editability | #21 | open | none | P0 proof + fixes | Schema likely supports this; active/edit surfaces must prove nil bodyweight is editable. |
| FG-005 | `docs/features/execute-loop.md` | Skip action and skip persistence | #4 | resolved | simulator_observation + test_result + codex_review | Active/rest redesign | Skip is built for eligible active row-based routes: it advances cursor/rest/transition progress, persists `skipped=true` with empty performance metrics, caches completion logs without metrics, and Rest displays `SKIPPED SET` instead of editable performed-work pills. Proof: `phase-05-skip-contract.md`, `phase-05-skip-rest-screen-final.jpg`, and Codex thread `019dcbb2-85e7-7340-ba0c-eb4ee8a8007f` for zero-rest transition coverage. |
| FG-006 | `docs/features/workout-preview.md`, `docs/features/today.md` | Open workout without starting | #1, #2, #3 | partially_built | code_inspection | Preview/edit slice | Today card-body tap opens the preview/detail path and Start is explicit. Remaining work is richer dedicated preview UI, editability/persistence proof, and simulator tap-target proof. |
| FG-007 | `docs/set-edit-sheet.md` | Unified edit surface | #6, #7, #15, #26 | partially_built | simulator_observation + test_result + codex_review | Preview/edit slice | Shared edit intent plus History visual adapter are built for set-log correction fields. Preview and active visual parity, apply-to-remaining scope, and bodyweight/user-parameter correction remain open. |
| FG-008 | `docs/features/execute-loop.md` | Scrolling active column and focal hierarchy | #8, #15, #17 | partially_built | simulator_observation + test_result + codex_review | Active/rest redesign | Active now shows bounded whole-block position (`BLOCK n / m`, `N / M DONE`) from `ExecutionProjection.blockProgress`, with simulator proof on straight sets. Remaining work is focal hierarchy/scrolling proof across non-straight-set modes. |
| FG-009 | `docs/features/execute-loop.md` | Rest progress grid | #14 | resolved | simulator_observation + test_result + codex_review | Active/rest redesign | Rest now shows a bounded block progress grid with performed/skipped/pending dots, hides fake progress for standalone rest/unbounded/sentinel/batch-rest states, and keeps skipped rows visually distinct while counting them as progress. Proof: `PostLogUnitDisplayTests` progress-grid helpers, Codex thread `019dcae9-e8ba-7760-9daa-2ceb9faa2fb7`, and simulator screenshots in `scratch/qa-runs/phase-05-rest-progress-grid.jpg` plus `phase-05-rest-progress-skip-regression.jpg`. |
| FG-010 | `docs/features/execute-loop.md` | Superset logging boundary | #11, #20 | resolved | simulator_observation + test_result + codex_review | Active/rest redesign | Round-robin batch logging no longer opens a mid-superset log sheet; final station enters round-log rest and final-round rest advances to Complete. Proof: `scratch/qa-runs/phase-05-superset-round-log.md` and Codex thread `019dcaff-97c6-7811-8d1a-69ae073c31a9`. |
| FG-011 | `docs/features/execute-loop.md` | Rest timer continuity | #23 | open | none | Active/rest redesign | Requires simulator observation or UI test; code inspection is not enough. |
| FG-012 | `docs/features/execute-loop.md`, `docs/features/workout-preview.md` | "What's next?" includes current block remaining | #13 | partially_built | code_inspection + test_result | P0 proof + fixes | Execution exposes projection-backed current-block remaining and future-work queues. Today's preview/detail still needs simulator-visible proof that the current block's remaining work is rendered before future blocks. |
| FG-013 | `docs/features/block-transition.md` | Full next-block setup view | #10 | resolved | simulator_observation + test_result + codex_review | Transition slice | Between-block transition now shows finished block, next block, timing mode, first task, timing setup, and all station setup lines before `start block`. Proof: `scratch/qa-runs/phase-05-transition-screen.md` and Codex thread `019dcbb2-85e7-7340-ba0c-eb4ee8a8007f`. |
| FG-014 | `docs/features/execute-loop.md`, `docs/features/history.md`, `docs/prescription.md` | Unilateral work logging/history | #19 | open | none | History/edit slice + future taxonomy | Eric's correction makes unilateral work exercise-level by default, e.g. separate left/right exercise items. `set_log.side` exists as a shipped/reserved field but is not the active authoring or grouping model. History display can use exercise-level identity in Phase 6; cross-variant aggregation needs a later taxonomy decision if real analysis needs it. |
| FG-015 | `docs/features/execute-loop.md` | Carries and distance/duration fields | #18 | partially_built | simulator_observation + test_result + codex_review | Execution data slice | Active/transition display, log-time capture, and History correction parity exist for logged distance/duration/carry fields. Remaining work, if needed, belongs to preview/active edit unification and mode-specific proof. |
| FG-016 | `docs/features/history.md` | Full-field post-workout correction | #26 | resolved | simulator_observation + test_result + codex_review | History/edit slice | History edit sheet covers set-log load/unit, reps, RIR set/clear, duration, distance, skipped/performed state, side round-trip, and notes by same-ID overwrite. Skipped metrics are cleared and skipped-only rows are excluded from by-exercise aggregation. Proof: FeaturesHistory/Persistence/DesignSystem/Sync tests, simulator QA on 2026-04-26, and Codex thread `019dcc18-01af-7ef0-9a81-11d9cb0a4b2c`. |
| FG-017 | `docs/prescription.md`, `docs/features/workout-preview.md`, `docs/features/execute-loop.md`, `docs/features/history.md` | Block intent display and persistence | #25 | partially_built | simulator_observation | Schema cutover | `block.intent` schema/payload foundation exists in Phase 2 with server/contract/package proof and simulator launch proof; authoring/display surfaces remain later. |
| FG-018 | `docs/features/execute-loop.md` | ETA remaining | #9 | open | none | Later polish | Nice-to-have after the main screen contracts are stable. |
| FG-019 | `docs/prescription.md` | Equipment/modifier modeling | #22 | open | none | Future design | Keep as documented feedback; no ADR or migration in this pass. |
| FG-020 | `docs/open-questions.md`, future `docs/design/in-app-chat.md` | In-app Claude/chat path | #24 | open | none | Future design | Standalone design surface; do not collapse this into history notes or set-note behavior. |

## Maintenance

When a slice closes a gap:

1. Update the owning feature doc's target section and `Current gaps`.
2. Change the row here to `resolved` or remove it if the feature doc now carries
   enough status detail.
3. Link the proof: test name, simulator run, or file/line evidence.
