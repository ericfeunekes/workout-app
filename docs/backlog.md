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
  - docs/watch-metrics.md
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
surfaces, WorkoutKit feasibility, and sync/auth spikes. Those lanes should stay
small: pick the gap cluster, prove it, then update the gaps.

## Lanes

| Lane | Posture | Owns | Why it exists | Next planning move |
| --- | --- | --- | --- | --- |
| Primitive data model cutover | Active trunk | `PDM-GAP-001`, `PDM-GAP-002`, `PDM-GAP-003`, `PDM-GAP-004`, `PDM-GAP-005`, `EXEC-GAP-008` | Replaces the current timing-mode shape with composable primitives that can express the workout types Setmark needs. | Start from `docs/specs/primitives-data-model.md` and its aspect files. Build an implementation plan from the current code state, not old phase files. |
| Today and workout preview | Parallel app lane | `TODAY-GAP-001`, `TODAY-GAP-002`, `TODAY-GAP-003`, `PREVIEW-GAP-001`, `PREVIEW-GAP-002`, `PREVIEW-GAP-003` | Makes the workout entry path clear, editable where intended, and backed by the same execution projection used by Active. | Select the preview/read-model or edit-persistence gaps and prove the flow in simulator. |
| Execute loop, timing, and transitions | Parallel app lane | `EXEC-GAP-001`, `EXEC-GAP-003`, `EXEC-GAP-004`, `EXEC-GAP-006`, `EXEC-GAP-007`, `EXEC-GAP-009`, `TIMING-GAP-001`, `TIMING-GAP-002`, `TIMING-GAP-003`, `AUTO-GAP-001`, `AUTO-GAP-002`, `AUTO-GAP-003`, `SWAP-GAP-001`, `SWAP-GAP-002`, `SWAP-GAP-003`, `SWAP-GAP-004`, `SWAP-GAP-005`, `TRANS-GAP-001`, `TRANS-GAP-002`, `TRANS-GAP-003` | Keeps the core workout flow aligned with current requirements while primitives are being prepared. | Pick one behavior cluster, especially deterministic UI proof or mode semantics, before changing drivers. |
| Set editing and corrections | Parallel app lane | `SETEDIT-GAP-001`, `SETEDIT-GAP-002`, `SETEDIT-GAP-003`, `SETEDIT-GAP-004`, `EXEC-GAP-002`, `EXEC-GAP-005`, `PASTEDIT-GAP-001`, `HISTORY-GAP-002` | Unifies preview, active, and history correction behavior instead of maintaining separate editing surfaces. | Define the shared edit contract first, then implement only the selected scopes. |
| History and review | Parallel app lane | `HISTORY-GAP-001`, `HISTORY-GAP-003`, `MOD-GAP-003` | Makes completed workout data useful after the fact, including variant aggregation and block intent display. | Resolve taxonomy/aggregation questions before changing history queries. |
| Save, persistence, and push | Parallel reliability lane | `SAVE-GAP-001`, `SAVE-GAP-002`, `PERSIST-GAP-001`, `PERSIST-GAP-002`, `PERSIST-GAP-003`, `PUSH-GAP-001`, `PUSH-GAP-002`, `SYNC-GAP-001` | Protects logged workout data across completion, relaunch, offline use, and foreground/background sync. | Choose atomicity, expiry, or diagnostics gaps explicitly; avoid broad sync rewrites. |
| Bootstrap and first run | Parallel polish lane | `BOOT-GAP-001`, `FIRST-GAP-001`, `FIRST-GAP-002` | Covers connection setup and manual recovery affordances. | Promote only if first-run or sync recovery blocks real use. |
| Telemetry and diagnostics | Parallel proof lane | `TELEM-GAP-001`, `TELEM-GAP-002`, `TELEM-GAP-003`, `TELEM-GAP-004` | Gives enough local and server-side evidence to answer whether actions landed. | Add coverage/export/debug surfaces only when they improve real QA or incident recovery. |
| Early WorkoutKit handoff | Evidence lane | `WATCHKIT-GAP-001`, `WATCHKIT-GAP-002`, `WATCHKIT-GAP-003` | Shorter Apple Watch path: push eligible workouts to Apple's Workout app, then reconcile completion facts. | Spike the per-archetype mapping, real-device open/schedule behavior, and completion identity path. |
| CloudKit replication | Spike lane | `SYNC-GAP-002` | May reduce custom transport work if iCloud can move plan/result records reliably enough for the app and Claude readback. | Spike record families, authority, account model, conflict behavior, and readback proof. |
| Cloudflare protected endpoint | Spike lane | `SYNC-GAP-003` | Reuses existing OAuth/Access posture for narrow app-facing sync or data endpoints when CloudKit is insufficient. | Spike one Access-protected endpoint and prove identity plus capability boundaries. |
| Modifier and equipment modeling | Requirements lane | `MOD-GAP-001`, `MOD-GAP-002`, `MOD-GAP-004` | Captures variants, equipment, setup context, substitutions, and app-display-only behavior without premature schema changes. | Tighten authoring examples and schema justification before any schema work. |
| In-app Claude | Requirements lane | `CHAT-GAP-001`, `CHAT-GAP-002`, `CHAT-GAP-003` | Future proposal/review/acceptance workflow for Claude-assisted changes inside the app. | Requirements and trust-boundary pass before implementation. |
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
