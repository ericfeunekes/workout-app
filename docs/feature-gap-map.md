---
title: Feature gap index
status: living
last_reviewed: 2026-05-17
purpose: Cross-feature index of unresolved implementation/proof gaps, keyed to owning requirement docs.
covers:
  - docs/features/
  - docs/modifier-equipment.md
  - docs/sync.md
  - docs/watch-metrics.md
  - docs/specs/primitives-data-model.md
---

# Feature Gap Index

Owning feature, domain, or aspect docs are the source of truth. Their
`Current gaps` sections describe what target behavior is not implemented or not
proven. This file is only the index: it gives those gaps stable IDs so future
phase plans can cite specific gaps and close them cleanly.

Do not put implementation steps, phase order, proof history, or resolved bugs
here. When a gap is closed, remove the row and remove or revise the corresponding
gap in the owning doc. Git history is the archive.

## Gap Fields

| Field | Meaning |
| --- | --- |
| `gap_id` | Stable ID used by phase and implementation plans. |
| `owning_doc` | Requirement doc that owns the gap. |
| `gap` | Short statement of the missing behavior or proof. |
| `planning_trigger` | The next kind of work that should address it. |

## Current Gaps

| gap_id | owning_doc | gap | planning_trigger |
| --- | --- | --- | --- |
| `TODAY-GAP-001` | `docs/features/today.md` | Today still uses the current preview/detail sheet; richer dedicated preview behavior is target. | Workout preview implementation plan. |
| `TODAY-GAP-002` | `docs/features/today.md` | Preview tap targets and Start affordance need simulator proof. | UI proof or preview implementation plan. |
| `TODAY-GAP-003` | `docs/features/today.md` | Today's preview/detail does not yet render current-block remaining work from the execution projection. | Workout preview implementation plan. |
| `PREVIEW-GAP-001` | `docs/features/workout-preview.md` | Preview editability is not proven for every target field. | Workout preview/edit planning. |
| `PREVIEW-GAP-002` | `docs/features/workout-preview.md` | Preview edit persistence is not implemented and must respect whole-tree server replacement semantics. | Workout preview/edit planning. |
| `PREVIEW-GAP-003` | `docs/features/workout-preview.md` | Preview does not yet directly consume the shared execution projection seam. | Workout preview/read-model planning. |
| `SWAP-GAP-001` | `docs/features/exercise-swap.md` | Exercise swap is item-scoped; there is no per-set swap behavior. | Exercise swap planning if promoted. |
| `SWAP-GAP-002` | `docs/features/exercise-swap.md` | Exercise swap cannot move work across blocks. | Exercise swap planning if promoted. |
| `SWAP-GAP-003` | `docs/features/exercise-swap.md` | Exercise swap has no undo path. | Exercise swap planning if promoted. |
| `SWAP-GAP-004` | `docs/features/exercise-swap.md`, `docs/open-questions.md` | Alternative override shape is not validated against the block timing mode. | Product/design decision before implementation. |
| `SWAP-GAP-005` | `docs/features/exercise-swap.md` | Alternative autoreg step overrides are parsed but not consumed by drivers. | Autoreg/swap planning if promoted. |
| `SETEDIT-GAP-001` | `docs/set-edit-sheet.md` | Preview, active, and History still use different visual editing surfaces. | Set edit unification plan. |
| `SETEDIT-GAP-002` | `docs/set-edit-sheet.md` | Apply-to-remaining scope for preview/future and active setup edits is not implemented. | Set edit unification plan. |
| `SETEDIT-GAP-003` | `docs/set-edit-sheet.md` | Bodyweight editing is a `user_parameters` correction problem without a selected UI. | Bodyweight correction plan. |
| `SETEDIT-GAP-004` | `docs/set-edit-sheet.md` | Mode-specific field combinations need visual proof across active and preview contexts. | UI proof or set edit implementation plan. |
| `EXEC-GAP-001` | `docs/features/execute-loop.md` | Primary CTA contrast and tap targets need simulator proof. | Execution UI proof pass. |
| `EXEC-GAP-002` | `docs/features/execute-loop.md` | Bodyweight editability needs proof through the shared edit surface. | Set edit/bodyweight plan. |
| `EXEC-GAP-003` | `docs/features/execute-loop.md` | Active/rest focal hierarchy and scrolling need proof across non-straight-set modes. | Execution UI proof pass. |
| `EXEC-GAP-004` | `docs/features/execute-loop.md` | Rest timer continuity needs simulator or pinned UI proof. | Execution UI proof pass. |
| `EXEC-GAP-005` | `docs/features/execute-loop.md` | Carry/distance/duration active editing needs preview/active unification and mode-specific proof. | Set edit unification plan. |
| `EXEC-GAP-006` | `docs/features/execute-loop.md` | ETA remaining remains later polish. | Later execution polish. |
| `EXEC-GAP-007` | `docs/features/execute-loop.md`, `docs/open-questions.md` | Starting workout B while workout A is active has no selected behavior. | Product decision before implementation. |
| `EXEC-GAP-008` | `docs/features/execute-loop.md` | Cluster/rest-pause expanded per-slot actual editing is deferred; current app logs one top-level row per composed set. | Primitive model or cluster execution planning. |
| `EXEC-GAP-009` | `docs/features/execute-loop.md` | Numeric-entry flashes and log/rest transition flicker have visual reports but no deterministic repro. | Simulator evidence before sheet/router changes. |
| `AUTO-GAP-001` | `docs/features/autoreg.md` | Settings vs prescription precedence is unresolved. | Autoreg/settings decision. |
| `AUTO-GAP-002` | `docs/features/autoreg.md` | `sets_detail` pyramids and tempo-heavy shapes do not propose autoreg unless a driver later promotes support. | Timing-mode/autoreg planning if promoted. |
| `AUTO-GAP-003` | `docs/features/autoreg.md` | No per-item proposal history or audit trail exists. | Autoreg audit planning if promoted. |
| `HISTORY-GAP-001` | `docs/features/history.md` | Cross-variant/unilateral aggregation is undefined beyond authored exercise identity. | Modifier/equipment or history taxonomy plan. |
| `HISTORY-GAP-002` | `docs/features/history.md`, `docs/features/past-set-edit.md` | Past corrections overwrite same logical row and are not audit-grade. | Correction provenance plan only if promoted. |
| `HISTORY-GAP-003` | `docs/features/history.md` | Block intent display is not complete across history surfaces. | History display plan. |
| `PASTEDIT-GAP-001` | `docs/features/past-set-edit.md` | Active-session past correction is limited to the last logged set. | Active edit expansion plan if promoted. |
| `SAVE-GAP-001` | `docs/features/save-and-done.md` | Dictation or richer note capture is deferred; completion note entry is plain text. | Save-and-done polish if promoted. |
| `SAVE-GAP-002` | `docs/features/save-and-done.md` | Save-and-done does not validate that every prescribed set was logged before completion. | Completion validation decision. |
| `PERSIST-GAP-001` | `docs/features/persistence.md` | SwiftData transaction rollback caveat is documented and tested but not lint-enforced. | Persistence guardrail planning if needed. |
| `PERSIST-GAP-002` | `docs/features/persistence.md` | Live session snapshot bytes have no explicit schema version. | Persistence migration planning if needed. |
| `PERSIST-GAP-003` | `docs/features/persistence.md` | Persist pipeline encode/save failures are swallowed; bounded loss is accepted but not surfaced. | Persistence diagnostics planning if promoted. |
| `PUSH-GAP-001` | `docs/features/push-queue.md` | Offline completion atomicity is not guaranteed when set logs and status updates flush separately. | Push/sync planning. |
| `PUSH-GAP-002` | `docs/features/push-queue.md` | No background push path exists; push waits until app resumes if the user locks the phone before foreground flush. | Push/sync planning. |
| `BOOT-GAP-001` | `docs/features/bootstrap.md` | No general manual sync trigger exists outside bootstrap and Today refresh. | Settings/sync planning. |
| `FIRST-GAP-001` | `docs/features/firstrun.md` | Trailing-slash normalization is not built. | FirstRun cleanup if needed. |
| `FIRST-GAP-002` | `docs/features/firstrun.md` | QR/unified connection-string setup remains deferred. | FirstRun/QR planning. |
| `TELEM-GAP-001` | `docs/features/telemetry.md` | Emit coverage is partial. | Telemetry requirements cleanup. |
| `TELEM-GAP-002` | `docs/features/telemetry.md` | No export/share surface exists in Settings. | Telemetry settings planning. |
| `TELEM-GAP-003` | `docs/features/telemetry.md` | No local debug overlay exists. | Telemetry diagnostics planning. |
| `TELEM-GAP-004` | `docs/features/telemetry.md` | Local event retention is only a 10k ring buffer; pushed events are not deleted on acknowledgement. | Telemetry retention planning if needed. |
| `TIMING-GAP-001` | `docs/features/timing-modes.md` | Superset, circuit, and custom autoreg need explicit remaining-round semantics before enablement. | Timing-mode/autoreg planning. |
| `TIMING-GAP-002` | `docs/features/timing-modes.md` | Distance-based intervals require manual lap/advance until GPS/sensor support exists. | Sensor/watch/cardio planning. |
| `TIMING-GAP-003` | `docs/features/timing-modes.md` | Background/resume view distortion is a visual watchlist without deterministic proof. | UI proof before timer changes. |
| `TRANS-GAP-001` | `docs/features/block-transition.md` | Block intent display needs authoring/display cutover before transition can show intent beyond timing mode and setup lines. | Block intent display planning. |
| `TRANS-GAP-002` | `docs/features/block-transition.md` | Same-setup adjacent blocks still show transition when the next work block has item setup. | Transition polish if promoted. |
| `TRANS-GAP-003` | `docs/features/block-transition.md` | Route/direction integration is deferred to a later mapping feature. | Route/watch planning if promoted. |
| `SYNC-GAP-001` | `docs/sync.md` | Stale live-session expiry remains undecided. | Product decision before execution/sync changes. |
| `SYNC-GAP-002` | `docs/sync.md` | CloudKit replication needs a record-family spike with authority, account, conflict, and Claude readback proof. | CloudKit replication spike. |
| `SYNC-GAP-003` | `docs/sync.md` | Cloudflare Access endpoint needs a narrow endpoint spike with identity and capability proof. | Cloudflare endpoint spike. |
| `WATCHKIT-GAP-001` | `docs/features/watch-workoutkit-handoff.md` | Final per-archetype WorkoutKit mapping table is missing. | WorkoutKit handoff spike. |
| `WATCHKIT-GAP-002` | `docs/features/watch-workoutkit-handoff.md` | Real-device open/schedule proof is missing. | WorkoutKit handoff spike. |
| `WATCHKIT-GAP-003` | `docs/features/watch-workoutkit-handoff.md` | Completion reconciliation identity path is unsettled. | WorkoutKit/HealthKit completion spike. |
| `WATCHCUSTOM-GAP-001` | `docs/features/watch-primary-execution.md` | Custom Watch protocol/platform identity, stale-action rejection, and phone inbox need future proof if custom Watch is promoted. | Just-in-time custom Watch phase planning. |
| `WATCHCUSTOM-GAP-002` | `docs/features/watch-primary-execution.md` | Watch-primary offline event replay and reconnect idempotency are unimplemented. | Just-in-time custom Watch phase planning. |
| `WATCHCUSTOM-GAP-003` | `docs/watch-metrics.md` | Custom Watch metric slots, HR slot states, target windows, and route/directions UI are unimplemented. | Just-in-time custom Watch phase planning. |
| `CHAT-GAP-001` | `docs/features/in-app-claude.md` | No accepted in-app Claude workflow exists. | Requirements/design pass. |
| `CHAT-GAP-002` | `docs/features/in-app-claude.md` | No proposal identity/acceptance contract exists. | Requirements/design pass. |
| `CHAT-GAP-003` | `docs/features/in-app-claude.md` | No trust boundary exists for app-applied Claude changes. | Requirements/design pass. |
| `MOD-GAP-001` | `docs/modifier-equipment.md` | Modifier/equipment vocabulary is not fully reflected in authoring docs. | Modifier/equipment requirements pass. |
| `MOD-GAP-002` | `docs/modifier-equipment.md` | Canonical examples across strength, carries, substitutions, unilateral variants, and labels are incomplete. | Modifier/equipment requirements pass. |
| `MOD-GAP-003` | `docs/modifier-equipment.md` | Cross-variant history aggregation is undefined. | History/modifier taxonomy decision. |
| `MOD-GAP-004` | `docs/modifier-equipment.md` | No schema change is justified until a concrete query/sync/UI behavior requires it. | Schema decision only if promoted. |
| `PDM-GAP-001` | `docs/specs/primitives-data-model.md` | Primitive data model is accepted but not implemented. | Primitives cutover planning. |
| `PDM-GAP-002` | `docs/specs/primitives-data-model/authoring-shape.md` | Authoring-shape open questions need disposition before code relies on them. | Primitives cutover planning. |
| `PDM-GAP-003` | `docs/specs/primitives-data-model/log-shape.md` | Log/result roles must stay query-safe without competing aggregates from slot rows. | Primitives storage/history planning. |
| `PDM-GAP-004` | `docs/specs/primitives-data-model/runtime-resolution.md` | Runtime resolution must preserve offline execution and seed-time parameter pinning. | Primitives execution planning. |
| `PDM-GAP-005` | `docs/specs/primitives-data-model/cutover.md` | Completed local workout logs are the preservation constraint during cutover. | Primitives migration planning. |

## Maintenance

When a slice closes a gap:

1. Update the owning doc's `Current gaps` section.
2. Remove the row here or narrow it to the remaining unresolved behavior.
3. If a new gap is discovered during implementation, add it to the owning doc
   first, then add an index row here.
