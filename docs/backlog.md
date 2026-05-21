---
title: Backlog
status: living
last_reviewed: 2026-05-17
purpose: Lightweight lane and gap router for WorkoutDB. Defines current work lanes and the gap IDs each lane owns; not a phase plan.
covers:
  - docs/sdlc.md
  - docs/feature-gap-map.md
  - docs/features/
  - docs/specs/primitives-data-model.md
  - docs/modifier-equipment.md
  - docs/sync.md
  - docs/TESTING.md
  - docs/watch-metrics.md
  - docs/healthkit-data-access.md
---

# Backlog

This is the current work router. It is not a phase plan and does not preserve
old phase order. Read `docs/sdlc.md` for the full lifecycle around this file.

Durable requirements live in the owning feature, domain, or aspect docs. Exact
unresolved gaps live in `docs/feature-gap-map.md`. This file groups those gaps
into lanes so the next implementation pass can pick a coherent slice without
reviving stale plans.

## Rules

- Start with a lane and exact primary gap IDs.
- Read the owning docs named by `docs/feature-gap-map.md`.
- Select the active work tree: one lane, a series of phases inside a lane, or
  one phase inside a lane.
- Use `scratch/` for ephemeral phase specs or implementation plans if the
  selected work tree needs decomposition.
- Do not create durable phase-plan files. If a lane changes, update this file
  and the owning docs or gap map.
- When a gap closes, remove or narrow it in the owning docs, remove or narrow it
  in `docs/feature-gap-map.md`, then update this lane table if the router changed.

## Current emphasis

The primitive data model is the trunk lane. It unlocks the workout shapes Eric
actually wants to author, and it creates the stable mapping surface for the
WorkoutKit handoff lane.

In parallel, short evidence or implementation slices can move on feedback app
surfaces, WorkoutKit feasibility, and sync/auth work. Those lanes should stay
small: pick the gap cluster, prove it, then update the gaps.

## Lanes

| Lane | Posture | Owns | Why it exists | Next planning move |
| --- | --- | --- | --- | --- |
| Primitive data model cutover | Closed trunk | _None_ | Replaced the timing-mode-shaped contract with composable primitives that can express the workout types Setmark needs. | Closed by the primitive wire/schema/cache/sync/reset cutover, completion/history remediation, no-work rejection, result-role query-safety, grouped completion push proof, repeatable workout-type matrix, and closeout QA. No production migration or data-preservation lane remains: the next deployment may delete and recreate the server database, and local QA cache data may be reset. Residual user-facing work now lives in the owning app lanes: History correction, shared edit surfaces, taxonomy/aggregation, unsupported future primitive cells, and runtime-cost proof. |
| Today and workout preview | Parallel app lane | `PREVIEW-GAP-001`, `PREVIEW-GAP-002` | Makes the workout entry path clear, editable where intended, and backed by shared CoreSession execution semantics. | Next move is preview editability proof across target fields, then planned-workout edit persistence against the server whole-tree replacement contract. |
| Execute loop, timing, and transitions | Parallel app lane | `EXEC-GAP-001`, `EXEC-GAP-003`, `EXEC-GAP-004`, `EXEC-GAP-006`, `EXEC-GAP-007`, `EXEC-GAP-009`, `EXEC-GAP-010`, `EXEC-GAP-012`, `TIMING-GAP-001`, `TIMING-GAP-002`, `TIMING-GAP-003`, `AUTO-GAP-001`, `AUTO-GAP-002`, `AUTO-GAP-003`, `SWAP-GAP-001`, `SWAP-GAP-002`, `SWAP-GAP-003`, `SWAP-GAP-004`, `SWAP-GAP-005`, `TRANS-GAP-001`, `TRANS-GAP-002`, `TRANS-GAP-003` | Keeps the core workout flow aligned with current requirements while primitives are being prepared. | Pick one behavior cluster. Continue extracting component seams before expanding interactions; use ETTrace for timer-runtime claims. |
| Set editing and corrections | Parallel app lane | `SETEDIT-GAP-001`, `SETEDIT-GAP-002`, `SETEDIT-GAP-003`, `SETEDIT-GAP-004`, `SETEDIT-GAP-005`, `EXEC-GAP-002`, `EXEC-GAP-005`, `PASTEDIT-GAP-001`, `HISTORY-GAP-002` | Unifies preview, active, complete, and history correction behavior instead of maintaining separate editing surfaces. | Define the shared edit presentation/routing contract first, then implement only the selected scopes. |
| History and review | Parallel app lane | `HISTORY-GAP-001`, `HISTORY-GAP-003`, `MOD-GAP-003` | Makes completed workout data useful after the fact, including variant aggregation and block intent display. | Resolve taxonomy/aggregation questions before changing history queries. |
| Save, persistence, and push | Parallel reliability lane | `SAVE-GAP-001`, `SAVE-GAP-002`, `PERSIST-GAP-001`, `PERSIST-GAP-002`, `PERSIST-GAP-003`, `PUSH-GAP-002`, `SYNC-GAP-001` | Protects logged workout data across completion, relaunch, offline use, and eventual background push. | Choose expiry, background push, or diagnostics gaps explicitly; avoid broad sync rewrites. Foreground lifecycle is now routed through the app-sync ownership lane. |
| App sync ownership and foreground lifecycle | Parallel sync proof lane | `TEST-GAP-004`, `SYNC-GAP-004` | Foreground pull, cache writeback, push flusher lifecycle, token recovery, and stage telemetry now have one Shell-owned coordinator; remaining work is proving the running app's lifecycle hook. Later APNs/silent-push support belongs here as an inbound server-nudged pull lane, not in the HealthKit export slice. `SYNC-GAP-004` is only a stub today; expected requirements topics are APNs capability setup, app device-token registration, server token storage/rotation, silent-push payload contract, background pull handling, diagnostics, and foreground catch-up. | First prove `scenePhase` active/background transitions invoke `AppSyncCoordinator` correctly. Later, run requirements planning for `SYNC-GAP-004`; no spike or external research is currently required just to establish that APNs/silent-push can enable opportunistic workout delivery. |
| Bootstrap and first run | Parallel polish lane | `BOOT-GAP-001`, `FIRST-GAP-001`, `FIRST-GAP-002` | Covers connection setup and manual recovery affordances. | Promote only if first-run or sync recovery blocks real use. |
| Settings and recovery surfaces | Parallel app lane | `SETTINGS-GAP-002`, `SETTINGS-GAP-003`, `SETTINGS-GAP-004`, `SETTINGS-GAP-005` | Gives sync recovery, server changes, reset, units, HealthKit archive export controls, telemetry diagnostics, and autoreg defaults one coherent user-facing surface. HealthKit archive settings now expose descriptor scope, manual export, automatic toggle, next-attempt status, current-server status, and simulator proof for automatic/manual status interactions. | Keep section-as-type; next HealthKit Settings work is richer schedule/status UX and real OS/device scheduled-wake evidence, not new export plumbing. Related telemetry, bootstrap, autoreg, and HealthKit export gaps stay in their owning lanes. |
| Telemetry and diagnostics | Parallel proof lane | `TELEM-GAP-001`, `TELEM-GAP-002`, `TELEM-GAP-003`, `TELEM-GAP-004`, `TELEM-GAP-005` | Gives enough local and server-side evidence to answer whether actions landed. | Add coverage/export/debug surfaces only when they improve real QA or incident recovery. |
| Release hardening | Parallel release lane | `RELEASE-GAP-001`, `RELEASE-GAP-002`, `RELEASE-GAP-003` | Manifest-backed local release automation now builds from a committed ref in a temporary worktree, runs preflight/gates, uploads only the manifest-bound IPA, assigns TestFlight, and records App Store Connect readiness. | Run a real committed-ref TestFlight upload through `make release-testflight` and use the manifest/readback to close the remaining proof gaps. |
| DesignSystem and accessibility foundation | Parallel foundation lane | `DS-GAP-001`, `DS-GAP-002`, `DS-GAP-003`, `DS-GAP-004` | Centralizes scalable type, accessibility metadata, hit targets, and material/glass posture before feature views keep diverging. | Update primitives first, then prove Active, Rest, edit sheets, and History with `snapshot_ui` plus Dynamic Type screenshots. |
| Testing proof infrastructure | Parallel proof lane | `TEST-GAP-002`, `TEST-GAP-003`, `TEST-GAP-004`, `TEST-GAP-005` | Builds the app-hosted, lifecycle, runtime-cost, and object-lifetime harnesses that pre-QA needs before simulator/device QA can be trusted for boundary claims. The real HTTP sync harness for `TEST-GAP-001` now exists for primitive slot and aggregate result sync plus server-persistence proof and should be extended by future sync work when needed. | Promote when a selected implementation depends on a missing proof harness; otherwise keep the gap explicit. Feature-specific proof gaps stay in their feature lanes. |
| HealthKit data access | Proof/follow-on lane | `HKDATA-GAP-003`, `HKDATA-GAP-005`, `HKDATA-GAP-006`, `TEST-GAP-003` | HealthKit batch/archive core is implemented for the first supported registry through `HealthKitBridge` and the local SwiftData archive projection. The personal archive export now covers all-supported/manual, explicit subsets, shared foreground catch-up, request-set cursor authority, Settings controls, BGTask registration/scheduling/handler proof, local projection proof, and server-side SQLite ingestion proof. | Run independent review for the expanded archive loop. Next HealthKit archive loop is richer schedule/status UX plus real OS/device evidence for scheduled daily wake, not APNs. |
| Early WorkoutKit handoff | Evidence lane | `WATCHKIT-GAP-002`, `WATCHKIT-GAP-004` | Shorter Apple Watch path: push eligible workouts to Apple's Workout app. | The pure export profile/classifier and `WorkoutKitAdapter` backend now exist. The adapter has proof-gated production APIs and DEBUG diagnostics, and production push blocks descriptor-incomplete payloads until exact target values and interval steps exist. Product export still waits on export tracking persistence and real-device schedule/open proof from a trusted iPhone paired to a real Apple Watch. |
| Workout results reconciliation | Requirements lane | `WATCHKIT-GAP-003` | Separate future module for deciding whether any target completion facts should come back into Setmark. | Keep this decoupled from WorkoutKit push. Requirements should start only when we want imported results, HealthKit queries, or user-confirmed completion behavior. |
| Cloudflare protected endpoint | Spike lane | `SYNC-GAP-003` | Reuses existing OAuth/Access posture for narrow app-facing sync or data endpoints if REST-over-Tailscale becomes inconvenient or needs a safer external callback/API surface. | Spike one Access-protected endpoint and prove identity plus capability boundaries. |
| Modifier and equipment modeling | Requirements lane | `MOD-GAP-001`, `MOD-GAP-002`, `MOD-GAP-004` | Captures variants, equipment, setup context, substitutions, and app-display-only behavior without premature schema changes. | Tighten authoring examples and schema justification before any schema work. |
| In-app Claude | Requirements lane | `CHAT-GAP-001`, `CHAT-GAP-002`, `CHAT-GAP-003` | Future proposal/review/acceptance workflow for Claude-assisted changes inside the app. | Requirements and trust-boundary pass before implementation. |
| Apple system surfaces / App Intents | Requirements lane | `APPINTENT-GAP-001`, `APPINTENT-GAP-002`, `APPINTENT-GAP-003`, `APPINTENT-GAP-004` | Future Shortcuts/Siri/Spotlight/widget/control entry points for opening WorkoutDB safely without app-side programming or accidental mutation. | Specify open-app handoff routes and entity identity first; defer mutation intents until persistence/sync/telemetry semantics are accepted. |
| Custom Setmark Watch | Later capability | `WATCHCUSTOM-GAP-001`, `WATCHCUSTOM-GAP-002`, `WATCHCUSTOM-GAP-003` | Setmark-owned Watch execution remains valuable if WorkoutKit cannot cover the needed experience. | Re-plan from then-current requirements only if WorkoutKit handoff is insufficient. |

## Maintenance

When a work slice closes or discovers a gap:

1. Update the owning requirement docs first.
2. Update `docs/feature-gap-map.md`.
3. Update this backlog only if lane ownership, posture, or next planning move
   changed.
4. Delete scratch planning artifacts that no longer describe active work. If
   their rationale must survive, promote the durable conclusion to the owning
   doc or an ADR.

Git history is the archive. Do not keep completed or superseded phase plans in
`docs/`.
