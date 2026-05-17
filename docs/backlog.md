---
title: Backlog
status: living
last_reviewed: 2026-05-17
purpose: Lightweight lane and gap router for WorkoutDB. Defines current work lanes and the gap IDs each lane owns; not a phase plan.
covers:
  - docs/feature-gap-map.md
  - docs/features/
  - docs/specs/primitives-data-model.md
  - docs/modifier-equipment.md
  - docs/sync.md
  - docs/watch-metrics.md
---

# Backlog

This is the current work router. It is not a phase plan and does not preserve
old phase order.

Durable requirements live in the owning feature, domain, or aspect docs. Exact
unresolved gaps live in `docs/feature-gap-map.md`. This file groups those gaps
into lanes so the next implementation pass can pick a coherent slice without
reviving stale plans.

## Rules

- Start with a lane and exact gap IDs.
- Read the owning docs named by `docs/feature-gap-map.md`.
- Use `scratch/` for ephemeral implementation notes if a selected slice needs
  decomposition.
- Do not create durable phase-plan files. If a lane changes, update this file
  and the owning docs or gap map.
- When a gap closes, remove or narrow it in the owning doc, remove or narrow it
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
| Primitive data model cutover | Active trunk | `PDM-*`, `EXEC-GAP-008`, related timing/autoreg gaps when touched | Replaces the current timing-mode shape with composable primitives that can express the workout types Setmark needs. | Start from `docs/specs/primitives-data-model.md` and its aspect files. Build an implementation plan from the current code state, not old phase files. |
| Today and workout preview | Parallel app lane | `TODAY-*`, `PREVIEW-*` | Makes the workout entry path clear, editable where intended, and backed by the same execution projection used by Active. | Select the preview/read-model or edit-persistence gaps and prove the flow in simulator. |
| Execute loop, timing, and transitions | Parallel app lane | `EXEC-*`, `TIMING-*`, `AUTO-*`, `SWAP-*`, `TRANS-*` | Keeps the core workout flow aligned with current requirements while primitives are being prepared. | Pick one behavior cluster, especially deterministic UI proof or mode semantics, before changing drivers. |
| Set editing and corrections | Parallel app lane | `SETEDIT-*`, `PASTEDIT-*`, `EXEC-GAP-002`, `EXEC-GAP-005`, `HISTORY-GAP-002` | Unifies preview, active, and history correction behavior instead of maintaining separate editing surfaces. | Define the shared edit contract first, then implement only the selected scopes. |
| History and review | Parallel app lane | `HISTORY-*`, `MOD-GAP-003`, related correction gaps | Makes completed workout data useful after the fact, including variant aggregation and block intent display. | Resolve taxonomy/aggregation questions before changing history queries. |
| Save, persistence, and push | Parallel reliability lane | `SAVE-*`, `PERSIST-*`, `PUSH-*`, `SYNC-GAP-001` | Protects logged workout data across completion, relaunch, offline use, and foreground/background sync. | Choose atomicity, expiry, or diagnostics gaps explicitly; avoid broad sync rewrites. |
| Bootstrap and first run | Parallel polish lane | `BOOT-*`, `FIRST-*` | Covers connection setup and manual recovery affordances. | Promote only if first-run or sync recovery blocks real use. |
| Telemetry and diagnostics | Parallel proof lane | `TELEM-*` | Gives enough local and server-side evidence to answer whether actions landed. | Add coverage/export/debug surfaces only when they improve real QA or incident recovery. |
| Early WorkoutKit handoff | Evidence lane | `WATCHKIT-*`, plus primitive mapping dependencies | Shorter Apple Watch path: push eligible workouts to Apple's Workout app, then reconcile completion facts. | Spike the per-archetype mapping, real-device open/schedule behavior, and completion identity path. |
| CloudKit replication | Spike lane | `SYNC-GAP-002` | May reduce custom transport work if iCloud can move plan/result records reliably enough for the app and Claude readback. | Spike record families, authority, account model, conflict behavior, and readback proof. |
| Cloudflare protected endpoint | Spike lane | `SYNC-GAP-003` | Reuses existing OAuth/Access posture for narrow app-facing sync or data endpoints when CloudKit is insufficient. | Spike one Access-protected endpoint and prove identity plus capability boundaries. |
| Modifier and equipment modeling | Requirements lane | `MOD-*`, `HISTORY-GAP-001` | Captures variants, equipment, setup context, substitutions, and cross-variant history behavior without premature schema changes. | Tighten authoring examples and aggregation rules before any schema work. |
| In-app Claude | Requirements lane | `CHAT-*` | Future proposal/review/acceptance workflow for Claude-assisted changes inside the app. | Requirements and trust-boundary pass before implementation. |
| Custom Setmark Watch | Later capability | `WATCHCUSTOM-*` | Setmark-owned Watch execution remains valuable if WorkoutKit cannot cover the needed experience. | Re-plan from then-current requirements only if WorkoutKit handoff is insufficient. |

## Maintenance

When a work slice closes or discovers a gap:

1. Update the owning requirement doc first.
2. Update `docs/feature-gap-map.md`.
3. Update this backlog only if lane ownership, posture, or next planning move
   changed.

Git history is the archive. Do not keep completed or superseded phase plans in
`docs/`.
