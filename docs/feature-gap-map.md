---
title: Feature gap index
status: living
last_reviewed: 2026-05-17
purpose: Cross-feature index of unresolved implementation/proof gaps, keyed to owning requirement docs.
covers:
  - docs/features/
  - docs/modifier-equipment.md
  - docs/sync.md
  - docs/TESTING.md
  - docs/watch-metrics.md
  - docs/healthkit-data-access.md
  - docs/specs/primitives-data-model.md
---

# Feature Gap Index

Owning feature, domain, or aspect docs are the source of truth. Their
`Current gaps` sections describe what target behavior is not implemented or not
proven. This file is only the index: it gives those gaps stable IDs so future
backlog lanes and implementation work can cite specific gaps and close them
cleanly.

Do not put implementation steps, phase order, proof history, or resolved bugs
here. When a gap is closed, remove the row and remove or revise the corresponding
gap in the owning docs. Git history is the archive.

## Gap Fields

| Field | Meaning |
| --- | --- |
| `gap_id` | Stable ID used by backlog lanes and implementation notes. |
| `owning_docs` | Requirement docs that own the gap. Most gaps have one owner; rows with multiple docs require all named docs to stay consistent. |
| `gap` | Short statement of the missing behavior or proof. |
| `gap_kind` | One of `requirements`, `decision`, `implementation`, `proof`, or `spike`. Routing and sequencing live in `docs/backlog.md`. |

## Current Gaps

| gap_id | owning_docs | gap | gap_kind |
| --- | --- | --- | --- |
| `PREVIEW-GAP-001` | `docs/features/workout-preview.md` | Preview editability is not proven for every target field. | `proof` |
| `PREVIEW-GAP-002` | `docs/features/workout-preview.md` | Preview edit persistence is not implemented and must respect whole-tree server replacement semantics. | `implementation` |
| `SWAP-GAP-001` | `docs/features/exercise-swap.md` | Exercise swap is item-scoped; there is no per-set swap behavior. | `implementation` |
| `SWAP-GAP-002` | `docs/features/exercise-swap.md` | Exercise swap cannot move work across blocks. | `implementation` |
| `SWAP-GAP-003` | `docs/features/exercise-swap.md` | Exercise swap has no undo path. | `implementation` |
| `SWAP-GAP-004` | `docs/features/exercise-swap.md` | Alternative override shape is not validated against the block timing mode; any unresolved product decision belongs in `docs/open-questions.md`. | `decision` |
| `SWAP-GAP-005` | `docs/features/exercise-swap.md` | Alternative autoreg step overrides are parsed but not consumed by drivers. | `implementation` |
| `SETEDIT-GAP-001` | `docs/set-edit-sheet.md` | Preview, active, and History still use different visual editing surfaces. | `implementation` |
| `SETEDIT-GAP-002` | `docs/set-edit-sheet.md` | Apply-to-remaining scope for preview/future and active setup edits is not implemented. | `implementation` |
| `SETEDIT-GAP-003` | `docs/set-edit-sheet.md` | Bodyweight editing is a `user_parameters` correction problem without a selected UI. | `decision` |
| `SETEDIT-GAP-004` | `docs/set-edit-sheet.md` | Mode-specific field combinations need visual proof across active and preview contexts. | `proof` |
| `SETEDIT-GAP-005` | `docs/set-edit-sheet.md` | Shared presentation and sheet-routing model is missing across preview, active, complete, and History edit contexts. | `implementation` |
| `EXEC-GAP-001` | `docs/features/execute-loop.md` | Primary CTA contrast and tap targets need simulator proof. | `proof` |
| `EXEC-GAP-002` | `docs/features/execute-loop.md` | Bodyweight editability needs proof through the shared edit surface. | `proof` |
| `EXEC-GAP-003` | `docs/features/execute-loop.md` | Active/rest focal hierarchy and scrolling need proof across non-straight-set modes. | `proof` |
| `EXEC-GAP-004` | `docs/features/execute-loop.md` | Rest timer continuity needs simulator or pinned UI proof. | `proof` |
| `EXEC-GAP-005` | `docs/features/execute-loop.md` | Carry/distance/duration active editing needs preview/active unification and mode-specific proof. | `implementation` |
| `EXEC-GAP-006` | `docs/features/execute-loop.md` | ETA remaining remains later polish. | `implementation` |
| `EXEC-GAP-007` | `docs/features/execute-loop.md` | Starting workout B while workout A is active has no selected behavior; any unresolved product decision belongs in `docs/open-questions.md`. | `decision` |
| `EXEC-GAP-008` | `docs/features/execute-loop.md` | Cluster/rest-pause expanded per-slot actual editing is deferred; current app logs one top-level row per composed set. | `implementation` |
| `EXEC-GAP-009` | `docs/features/execute-loop.md` | Numeric-entry flashes and log/rest transition flicker have visual reports but no deterministic repro. | `proof` |
| `EXEC-GAP-010` | `docs/features/execute-loop.md` | Active, Rest, and Complete need smaller component seams before adding more interactions. | `implementation` |
| `EXEC-GAP-012` | `docs/features/execute-loop.md`, `docs/TESTING.md` | Timer and transition runtime claims need ETTrace-backed timer-gauntlet proof. | `proof` |
| `AUTO-GAP-001` | `docs/features/autoreg.md` | Settings vs prescription precedence is unresolved. | `decision` |
| `AUTO-GAP-002` | `docs/features/autoreg.md` | `sets_detail` pyramids and tempo-heavy shapes do not propose autoreg unless a driver later promotes support. | `implementation` |
| `AUTO-GAP-003` | `docs/features/autoreg.md` | No per-item proposal history or audit trail exists. | `implementation` |
| `HISTORY-GAP-001` | `docs/features/history.md` | Cross-variant/unilateral aggregation is undefined beyond authored exercise identity. | `decision` |
| `HISTORY-GAP-002` | `docs/features/history.md`, `docs/features/past-set-edit.md` | Past corrections overwrite same logical row and are not audit-grade. | `implementation` |
| `HISTORY-GAP-003` | `docs/features/history.md` | Block intent display is not complete across history surfaces. | `implementation` |
| `PASTEDIT-GAP-001` | `docs/features/past-set-edit.md` | Active-session past correction is limited to the last logged set. | `implementation` |
| `SAVE-GAP-001` | `docs/features/save-and-done.md` | Dictation or richer note capture is deferred; completion note entry is plain text. | `implementation` |
| `SAVE-GAP-002` | `docs/features/save-and-done.md` | Save-and-done does not validate that every prescribed set was logged before completion. | `decision` |
| `PERSIST-GAP-001` | `docs/features/persistence.md` | SwiftData transaction rollback caveat is documented and tested but not lint-enforced. | `proof` |
| `PERSIST-GAP-002` | `docs/features/persistence.md` | Live session snapshot bytes have no explicit schema version. | `implementation` |
| `PERSIST-GAP-003` | `docs/features/persistence.md` | Persist pipeline encode/save failures are swallowed; bounded loss is accepted but not surfaced. | `implementation` |
| `PUSH-GAP-002` | `docs/features/push-queue.md` | No background push path exists; push waits until app resumes if the user locks the phone before foreground flush. | `implementation` |
| `BOOT-GAP-001` | `docs/features/bootstrap.md` | No general manual sync trigger exists outside bootstrap and Today refresh. | `implementation` |
| `SETTINGS-GAP-002` | `docs/features/settings.md` | Sync now, change server, reset, units, telemetry export/debug, token recovery, and autoreg defaults need one visible behavior surface with proof. | `implementation` |
| `SETTINGS-GAP-003` | `docs/features/settings.md`, `docs/architecture/hotspots.md` | Section-as-type Settings architecture lacks feature-level acceptance and QA proof. | `proof` |
| `SETTINGS-GAP-004` | `docs/features/settings.md`, `docs/features/telemetry.md` | Diagnostics/export rows remain target behavior only where telemetry gaps call for them. | `implementation` |
| `SETTINGS-GAP-005` | `docs/features/settings.md`, `docs/healthkit-data-access.md` | HealthKit personal archive export controls now include descriptor subset selection, manual export, automatic toggle, next-attempt status, current-server status, BGTask schedule-hook proof, and Settings UI interaction proof. Remaining work: richer last-run summary, clearer failure display, and real OS/device evidence for scheduled background wake behavior. | `implementation` |
| `FIRST-GAP-001` | `docs/features/firstrun.md` | Trailing-slash normalization is not built. | `implementation` |
| `FIRST-GAP-002` | `docs/features/firstrun.md` | QR/unified connection-string setup remains deferred. | `implementation` |
| `TELEM-GAP-001` | `docs/features/telemetry.md` | Emit coverage is partial. | `proof` |
| `TELEM-GAP-002` | `docs/features/telemetry.md` | No export/share surface exists in Settings. | `implementation` |
| `TELEM-GAP-003` | `docs/features/telemetry.md` | No local debug overlay exists. | `implementation` |
| `TELEM-GAP-004` | `docs/features/telemetry.md` | Local event retention is only a 10k ring buffer; pushed events are not deleted on acknowledgement. | `implementation` |
| `TELEM-GAP-005` | `docs/features/telemetry.md` | Save & Done has stage-level proof telemetry, and app-sync lifecycle has basic stage outcomes; app-sync still lacks richer redacted server identity / queue counts, and other multi-surface flows still need explicit stage events across local cache, push queue, sync metadata, auth recovery, and server boundaries. | `proof` |
| `TIMING-GAP-001` | `docs/features/timing-modes.md` | Superset, circuit, and custom autoreg need explicit remaining-round semantics before enablement. | `decision` |
| `TIMING-GAP-002` | `docs/features/timing-modes.md` | Distance-based intervals require manual lap/advance until GPS/sensor support exists. | `implementation` |
| `TIMING-GAP-003` | `docs/features/timing-modes.md` | Background/resume view distortion is a visual watchlist without deterministic proof. | `proof` |
| `TRANS-GAP-001` | `docs/features/block-transition.md` | Block intent display needs authoring/display cutover before transition can show intent beyond timing mode and setup lines. | `implementation` |
| `TRANS-GAP-002` | `docs/features/block-transition.md` | Same-setup adjacent blocks still show transition when the next work block has item setup. | `implementation` |
| `TRANS-GAP-003` | `docs/features/block-transition.md` | Route/direction integration is deferred to a later mapping feature. | `implementation` |
| `SYNC-GAP-001` | `docs/sync.md` | Stale live-session expiry remains undecided. | `decision` |
| `SYNC-GAP-003` | `docs/sync.md` | Cloudflare Access endpoint needs a narrow endpoint spike with identity and capability proof. | `spike` |
| `SYNC-GAP-004` | `docs/sync.md` | APNs/silent-push server-nudged sync is an unplanned stub; future requirements should define app token registration, server token storage, silent-push payloads, background pull handling, telemetry, and foreground catch-up. | `requirements` |
| `TEST-GAP-002` | `docs/TESTING.md` | App-hosted Xcode tests are only compile/link smoke; no real launch-time or composition invariant exists. | `proof` |
| `TEST-GAP-003` | `docs/TESTING.md` | No real-device proof harness exists for Watch, HealthKit, and device-only behavior. | `proof` |
| `TEST-GAP-004` | `docs/TESTING.md`, `docs/sync.md` | App-sync foreground/background lifecycle has package proof for the Shell coordinator, but no simulator/app-root lifecycle evidence proving the `scenePhase` path in a running app. | `proof` |
| `TEST-GAP-005` | `docs/TESTING.md`, `docs/QA.md`, `docs/ios-dev-loop.md` | Runtime cost and object-lifetime baselines need ETTrace/memgraph proof lanes. | `proof` |
| `RELEASE-GAP-001` | `docs/WORKFLOW.md` | Manifest-backed TestFlight release automation exists, but still needs an end-to-end upload proof from a committed ref before the manual-command gap can close. | `proof` |
| `RELEASE-GAP-002` | `docs/WORKFLOW.md` | Dedicated non-login signing keychain and least-privilege App Store Connect key are configured; still needs end-to-end proof that the path runs with no Eric password prompts. | `proof` |
| `RELEASE-GAP-003` | `docs/WORKFLOW.md` | Build-number bumping and duplicate preflight checks exist; close after a real manifest-backed TestFlight upload proves the guard. | `proof` |
| `HKDATA-GAP-003` | `docs/healthkit-data-access.md`, `docs/TESTING.md` | Real Watch-backed live metric delivery is unproven until a physical iPhone + Apple Watch diagnostic run succeeds. | `proof` |
| `HKDATA-GAP-005` | `docs/healthkit-data-access.md`, `docs/TESTING.md` | WatchOS simulator live-workout diagnostic now proves HealthKit authorization, HKWorkoutSession/HKLiveWorkoutBuilder lifecycle, simulated metric delivery, and builder save through XcodeBuildMCP; watch UI and phone execution consume the typed metric/message path locally. Remaining implementation scope is richer metric coverage and a more deterministic watch simulator trigger; real sensors/sync stay in `HKDATA-GAP-003`. | `implementation` |
| `HKDATA-GAP-006` | `docs/healthkit-data-access.md`, `docs/features/settings.md` | Personal archive export to the home server now covers all-supported/manual export, explicit subsets, foreground catch-up through the shared runtime, BGTask registration/scheduling/handler proof, server endpoint/schema/storage, Sync upload, local export state, Settings trigger/status controls, local projection proof, and server-side SQLite ingestion proof. Remaining work: richer schedule/status copy, real HTTP app-client readback, and real OS/device evidence for scheduled daily wake behavior. | `implementation` |
| `DS-GAP-001` | `docs/design-system.md` | Semantic/scalable typography and hero/timer Dynamic Type rules are incomplete. | `implementation` |
| `DS-GAP-002` | `docs/design-system.md` | Interactive primitives do not centrally guarantee accessibility metadata and 44 pt target expectations. | `implementation` |
| `DS-GAP-003` | `docs/design-system.md`, `docs/QA.md` | Active, Rest, LogSetSheet, SetEditSheet, and History need Dynamic Type and accessibility proof using `snapshot_ui`. | `proof` |
| `DS-GAP-004` | `docs/design-system.md` | Material/glass usage is not centralized behind approved Shell/DesignSystem wrappers with no-glass defaults for workout surfaces. | `implementation` |
| `APPINTENT-GAP-001` | `docs/features/app-intents.md` | No accepted Apple system-surface contract exists beyond the planned feature shell. | `requirements` |
| `APPINTENT-GAP-002` | `docs/features/app-intents.md` | Handoff routes for Today, Active, and History are not specified in app routing or debug launch terms. | `requirements` |
| `APPINTENT-GAP-003` | `docs/features/app-intents.md` | Mutation intents are deferred until offline, auth, persistence, telemetry, and confirmation semantics are defined. | `requirements` |
| `APPINTENT-GAP-004` | `docs/features/app-intents.md` | App entity identity for workouts/sessions is not specified. | `requirements` |
| `WATCHKIT-GAP-002` | `docs/features/watch-workoutkit-handoff.md` | `paceTargetRun` now maps a single scheduled running distance+duration slot to WorkoutKit `PacerWorkout`; `WorkoutKitHandoff` owns the TestFlight proof-collection `Watch` action, latest-attempt/receipt persistence for schedule/block/repeat outcomes, and telemetry. Remaining work is real-device schedule visibility/startability and duplicate/update proof before marking delivery complete. | `proof` |
| `WATCHKIT-GAP-003` | `docs/features/watch-workoutkit-handoff.md` | Results/reconciliation is a separate future lane, not part of push-only WorkoutKit handoff. | `requirements` |
| `WATCHKIT-GAP-004` | `docs/features/watch-workoutkit-handoff.md` | Local watch simulator build/install/launch and iOS-to-Watch custom content push proof exist; scratch real-device WorkoutKit schedule/open probes typecheck, but no physical iPhone/Watch is visible to Xcode yet. | `spike` |
| `WATCHCUSTOM-GAP-001` | `docs/features/watch-primary-execution.md` | Custom Watch protocol/platform identity, stale-action rejection, and phone inbox need future proof if custom Watch is promoted. | `spike` |
| `WATCHCUSTOM-GAP-002` | `docs/features/watch-primary-execution.md` | Watch-primary offline event replay and reconnect idempotency are unimplemented. | `implementation` |
| `WATCHCUSTOM-GAP-003` | `docs/watch-metrics.md` | Custom Watch metric slots, HR slot states, target windows, and route/directions UI are unimplemented. | `implementation` |
| `CHAT-GAP-001` | `docs/features/in-app-claude.md` | No accepted in-app Claude workflow exists. | `requirements` |
| `CHAT-GAP-002` | `docs/features/in-app-claude.md` | No proposal identity/acceptance contract exists. | `requirements` |
| `CHAT-GAP-003` | `docs/features/in-app-claude.md` | No trust boundary exists for app-applied Claude changes. | `requirements` |
| `MOD-GAP-001` | `docs/modifier-equipment.md` | Modifier/equipment vocabulary is not fully reflected in authoring docs. | `requirements` |
| `MOD-GAP-002` | `docs/modifier-equipment.md` | Canonical examples across strength, carries, substitutions, unilateral variants, and labels are incomplete. | `requirements` |
| `MOD-GAP-003` | `docs/modifier-equipment.md` | Cross-variant history aggregation is undefined. | `decision` |
| `MOD-GAP-004` | `docs/modifier-equipment.md` | No schema change is justified until a concrete query/sync/UI behavior requires it. | `decision` |

## Maintenance

When a slice closes a gap:

1. Update the owning docs' `Current gaps` sections.
2. Remove the row here or narrow it to the remaining unresolved behavior.
3. If a new gap is discovered during implementation, add it to the owning docs
   first, then add an index row here.
