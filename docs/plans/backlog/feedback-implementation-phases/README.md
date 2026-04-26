---
title: 2026-04-25 feedback implementation phases
status: backlog
last_reviewed: 2026-04-26
purpose: Directory of implementation-planning phases for carrying the 2026-04-25 workout feedback from docs alignment through app, watch, and QA.
covers:
  - FEEDBACK-AND-SPEC-2026-04-25.md
  - docs/feature-gap-map.md
  - docs/features/
  - docs/watch-metrics.md
  - docs/features/watch-primary-execution.md
---

# 2026-04-25 Feedback Implementation Phases

This directory is the durable implementation-planning map for the workout
feedback and watch redesign sequence. Each phase is a scoped delivery unit with
its own proof map and done criteria. A phase moves from backlog to
`docs/plans/active/` only when selected for implementation.

## Context

The implementation must not be screen-by-screen. The actual architecture is
boundary-driven:

- `CoreDomain` owns dumb value types.
- `CorePrescription` owns `prescription_json` and `timing_config_json` parsing.
- `CoreSession` owns pure live-session state and reducer transitions.
- `FeaturesExecution` owns execution read models, drivers, active/rest/complete
  UI, and live logging.
- `Persistence`, `Sync`, shared schema, and server must move together for
  persisted fields.
- `Shell` is the composition point for cross-feature and phone/watch wiring.
- `WatchBridge` owns phone/watch protocol vocabulary.
- `FeaturesWatchFaces` renders watch state but must not own server sync or the
  phone session reducer.

The phase order follows those boundaries: docs, schema, execution read models,
phone UX, history, watch authority, watch-primary durability, watch UI, then
future in-app Claude/chat.

## Phase Index

| Phase | Plan | Purpose |
|---|---|---|
| 1 | [phase-01-feature-doc-contracts.md](phase-01-feature-doc-contracts.md) | Convert feedback into target feature docs, current gaps, proof rules, and backlog plans. |
| 2 | [phase-02-schema-cutover-foundation.md](phase-02-schema-cutover-foundation.md) | Land `set_log.skipped`, `set_log.side`, and `block.intent` across server, schema, SwiftData, sync, and docs. |
| 3 | [phase-03-execution-read-model-seams.md](phase-03-execution-read-model-seams.md) | Build shared execution read models for current task, remaining/upcoming work, editability, and progress. |
| 4 | [phase-04-preview-edit-contract.md](phase-04-preview-edit-contract.md) | Implement workout preview, explicit start, current-block "what's next", and unified edit surface. |
| 5 | [phase-05-active-rest-transition-redesign.md](phase-05-active-rest-transition-redesign.md) | Redesign active/rest/transition execution surfaces with simulator proof. |
| 6 | [phase-06-history-post-workout-correction.md](phase-06-history-post-workout-correction.md) | Add full post-workout correction, per-side history, and duration/distance edit parity. |
| 7 | [phase-07-watch-protocol-foundation.md](phase-07-watch-protocol-foundation.md) | Prove Watch platform constraints, then replace weak watch messages with versioned identity and authority protocol. |
| 8 | [phase-08-watch-primary-offline-execution.md](phase-08-watch-primary-offline-execution.md) | Let the Watch start/run offline and replay events idempotently to the phone. |
| 9 | [phase-09-watch-metrics-directions-ui.md](phase-09-watch-metrics-directions-ui.md) | Build the three fixed watch views, metric slots, HR slot, target windows, and only proven route/directions states. |
| 10 | [phase-10-in-app-claude-chat-design.md](phase-10-in-app-claude-chat-design.md) | Design in-app Claude/chat as a separate future surface, not history notes. |
| 11 | [phase-11-modifier-equipment-modeling.md](phase-11-modifier-equipment-modeling.md) | Define authored modifier/equipment modeling so exercise variants stay explicit without app-side programming logic. |

## Shared Done Standard

A phase is done only when:

- Its implementation plan has been moved to `docs/plans/active/` or explicitly
  refreshed in place before work starts.
- Code/docs are implemented for that phase only.
- The proof map has run with the strongest practical boundary checks.
- iOS simulator QA has been captured for user-facing app changes.
- Real-device Watch/HealthKit proof is captured where the phase claims it.
- Independent Codex review returns clean or all real findings are addressed.
- `docs/feature-gap-map.md` and owning feature docs reflect closed and open gaps.

## What Is Not Generalized Yet

- No multi-user migration strategy.
- No legacy compatibility layer for old watch messages.
- No direct Watch-to-server sync.
- No route/directions work before watch authority and GPS ownership are proven.
- No in-app Claude/chat implementation until the separate design phase is done.
