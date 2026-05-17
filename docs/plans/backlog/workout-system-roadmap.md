---
title: Workout system roadmap
status: backlog
last_reviewed: 2026-05-17
purpose: Route current requirement lanes and gap indexes without maintaining stale deferred phase plans.
covers:
  - docs/feature-gap-map.md
  - docs/specs/primitives-data-model.md
  - docs/watch-metrics.md
  - docs/features/watch-workoutkit-handoff.md
  - docs/features/watch-primary-execution.md
  - docs/features/in-app-claude.md
  - docs/modifier-equipment.md
  - docs/sync.md
---

# Workout System Roadmap

This is the pickup map for the current workout-app arc. It is not a phase plan.
Deferred capabilities remain as requirements and gaps in their owning docs.
When a lane is selected for implementation, create a fresh phase or
implementation plan against the app and requirements as they exist then.

## Current Working Model

- Requirements live in feature/domain/aspect docs.
- `docs/feature-gap-map.md` indexes unresolved gaps by stable ID.
- `docs/open-questions.md` holds product/design decisions only.
- Phase plans are just-in-time artifacts under `docs/plans/active/`.
- Stale or completed phase plans are provenance, not current direction.

## Lanes

| Lane | Owning docs | Gap IDs | Planning posture |
| --- | --- | --- | --- |
| iPhone execution, preview, edit, history | `docs/features/today.md`, `docs/features/workout-preview.md`, `docs/features/execute-loop.md`, `docs/features/autoreg.md`, `docs/features/exercise-swap.md`, `docs/features/block-transition.md`, `docs/set-edit-sheet.md`, `docs/features/save-and-done.md`, `docs/features/history.md`, `docs/features/past-set-edit.md`, `docs/features/persistence.md`, `docs/features/push-queue.md`, `docs/features/bootstrap.md`, `docs/features/firstrun.md`, `docs/features/telemetry.md`, `docs/features/timing-modes.md` | `TODAY-*`, `PREVIEW-*`, `EXEC-*`, `AUTO-*`, `SWAP-*`, `TRANS-*`, `SETEDIT-*`, `SAVE-*`, `HISTORY-*`, `PASTEDIT-*`, `PERSIST-*`, `PUSH-*`, `BOOT-*`, `FIRST-*`, `TELEM-*`, `TIMING-*` | Plan only the selected gap cluster; do not revive old feedback phases. |
| Primitives data model | `docs/specs/primitives-data-model.md` and aspect files | `PDM-*` | Create fresh cutover planning from the accepted spec when selected. |
| Early Apple Watch | `docs/features/watch-workoutkit-handoff.md` | `WATCHKIT-*` | Spike WorkoutKit mapping/open/schedule/completion before custom Watch work. |
| Custom Setmark Watch | `docs/features/watch-primary-execution.md`, `docs/watch-metrics.md`, `docs/sync.md` | `WATCHCUSTOM-*` | Later capability; generate a new phase plan only if WorkoutKit handoff is insufficient. |
| CloudKit replication | `docs/sync.md` | `SYNC-GAP-002` | Spike as replication/data-model work, not a transport swap. |
| Cloudflare protected endpoint | `docs/sync.md` | `SYNC-GAP-003` | Spike as a narrow Access-protected endpoint, not a broad write proxy. |
| In-app Claude | `docs/features/in-app-claude.md` | `CHAT-*` | Requirements/design pass before implementation. |
| Modifier/equipment modeling | `docs/modifier-equipment.md`, `docs/prescription.md`, `docs/workout-generation.md` | `MOD-*` | Requirements pass before schema or app implementation. |

## Pickup rules

- When someone asks "what phase?", identify the lane and gap IDs first. Then
  decide whether phase planning is needed.
- A phase plan must cite the exact owning docs and gap IDs it intends to close.
- Do not start from deferred phase files. Start from requirements and current
  app/code state.
- If phase planning discovers a missing invariant, state authority, identity
  rule, or acceptance criterion, stop and update the owning requirement doc
  before writing the phase.
- User-facing app changes still require simulator QA before signoff. Real
  Watch/HealthKit claims require real-device proof.
