---
title: Feature gap map
status: living
last_reviewed: 2026-04-26
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
| FG-001 | `docs/features/execute-loop.md` | Rest face state copy | #5 | open | none | P0 proof + fixes | Remove in-workout "waiting to start"; valid mid-workout states are rest countdown or transition. |
| FG-002 | `docs/features/today.md`, `docs/features/workout-preview.md` | Preview CTA hit targets | #12 | open | none | P0 proof + fixes | Needs simulator observation or UI test; code inspection is not enough. |
| FG-003 | `docs/features/execute-loop.md`, `docs/set-edit-sheet.md` | Primary CTA enabled/disabled contrast | #16 | open | none | P0 proof + fixes | Same likely shared-button root as FG-002; needs visual proof. |
| FG-004 | `docs/features/execute-loop.md`, `docs/set-edit-sheet.md` | Bodyweight editability | #21 | open | none | P0 proof + fixes | Schema likely supports this; active/edit surfaces must prove nil bodyweight is editable. |
| FG-005 | `docs/features/execute-loop.md` | Skip action and skip persistence | #4 | open | none | Schema cutover | Requires `set_log.skipped` and active/rest affordances. |
| FG-006 | `docs/features/workout-preview.md`, `docs/features/today.md` | Open workout without starting | #1, #2, #3 | open | none | Preview/edit slice | Today tap opens preview; Start is explicit; preview allows scoped structural edits. |
| FG-007 | `docs/set-edit-sheet.md` | Unified edit surface | #6, #7, #15, #26 | open | none | Preview/edit slice | One sheet serves preview edits, active/future edits, past-set corrections, and history corrections. |
| FG-008 | `docs/features/execute-loop.md` | Scrolling active column and focal hierarchy | #8, #15, #17 | open | none | Active/rest redesign | Active surface shows full context plus exact current position. |
| FG-009 | `docs/features/execute-loop.md` | Rest progress grid | #14 | open | none | Active/rest redesign | Dot grid replaces dead rest copy and shows block structure + current position. |
| FG-010 | `docs/features/execute-loop.md` | Superset logging boundary | #11, #20 | open | none | Active/rest redesign | No log sheet mid-superset; log at rest or from explicit history/edit surface. |
| FG-011 | `docs/features/execute-loop.md` | Rest timer continuity | #23 | open | none | Active/rest redesign | Requires simulator observation or UI test; code inspection is not enough. |
| FG-012 | `docs/features/execute-loop.md`, `docs/features/workout-preview.md` | "What's next?" includes current block remaining | #13 | open | none | P0 proof + fixes | Preview shows remaining work in the current block before future blocks; it is not only a next-block shortcut. |
| FG-013 | `docs/features/block-transition.md` | Full next-block setup view | #10 | open | none | Transition slice | Between-block transition shows everything needed to physically prepare. |
| FG-014 | `docs/features/execute-loop.md`, `docs/features/history.md` | Per-side logging | #19 | open | none | Schema cutover | Requires `set_log.side` with `left` / `right` / `bilateral`, app two-row semantics, and server aggregate semantics. |
| FG-015 | `docs/features/execute-loop.md` | Carries and distance/duration fields | #18 | open | none | Execution data slice | Needs active/log/history edit parity for weight, distance, and duration as applicable. |
| FG-016 | `docs/features/history.md` | Full-field post-workout correction | #26 | open | none | History/edit slice | Fold into history doc; no separate post-workout feature doc unless history becomes too broad. |
| FG-017 | `docs/prescription.md`, `docs/features/workout-preview.md`, `docs/features/execute-loop.md`, `docs/features/history.md` | Block intent display and persistence | #25 | open | none | Schema cutover | Requires freeform `block.intent`; server accepts null, authoring docs require new block intent, and the app displays nothing when intent is null. |
| FG-018 | `docs/features/execute-loop.md` | ETA remaining | #9 | open | none | Later polish | Nice-to-have after the main screen contracts are stable. |
| FG-019 | `docs/prescription.md` | Equipment/modifier modeling | #22 | open | none | Future design | Keep as documented feedback; no ADR or migration in this pass. |
| FG-020 | `docs/open-questions.md`, future `docs/design/in-app-chat.md` | In-app Claude/chat path | #24 | open | none | Future design | Standalone design surface; do not collapse this into history notes or set-note behavior. |

## Maintenance

When a slice closes a gap:

1. Update the owning feature doc's target section and `Current gaps`.
2. Change the row here to `resolved` or remove it if the feature doc now carries
   enough status detail.
3. Link the proof: test name, simulator run, or file/line evidence.
