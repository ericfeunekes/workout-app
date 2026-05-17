---
title: 2026-04-25 feedback implementation phases
status: historical source material
last_reviewed: 2026-05-17
purpose: Historical implementation-planning source material for the completed feedback arc; current work starts from feature gaps, not deferred phases.
covers:
  - FEEDBACK-AND-SPEC-2026-04-25.md
  - docs/feature-gap-map.md
  - docs/features/
  - docs/watch-metrics.md
  - docs/features/watch-primary-execution.md
---

# 2026-04-25 Feedback Implementation Phases

This directory is historical source material for the 2026-04-25 workout
feedback pass. It is no longer the durable implementation-planning map for
future work.

Current requirements and gaps live in the owning feature/aspect docs and are
indexed by `docs/feature-gap-map.md`. New phase plans are created just in time
under `docs/plans/active/` and must cite the exact gaps they intend to close.

## Current Landing Status (2026-05-17)

Phases 1-6 have been implemented in the current app/code/docs baseline. That
includes preview-first workout entry, execution read-model seams, redesigned
active/rest/transition surfaces, history review, exercise detail, post-workout
correction, shared set editing, and history data-integrity fixes.

T1 is a transition alignment note that constrains later history/watch work; it
does not add app behavior by itself.

Deferred Phase 7-11 plans have been retired as active backlog authority. Their
durable requirements now live in:

- `docs/features/watch-workoutkit-handoff.md`
- `docs/features/watch-primary-execution.md`
- `docs/watch-metrics.md`
- `docs/features/in-app-claude.md`
- `docs/modifier-equipment.md`
- `docs/sync.md`
- `docs/feature-gap-map.md`

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

The completed phases followed those boundaries through phone execution and
history. Future Watch, in-app Claude, and modifier/equipment work should start
from current requirements and gap IDs, not this historical phase order.

## Phase Index

| Phase | Plan | Purpose |
|---|---|---|
| 1 | [phase-01-feature-doc-contracts.md](phase-01-feature-doc-contracts.md) | Convert feedback into target feature docs, current gaps, proof rules, and backlog plans. |
| 2 | [phase-02-schema-cutover-foundation.md](phase-02-schema-cutover-foundation.md) | Land `set_log.skipped`, reserved `set_log.side`, and `block.intent` across server, schema, SwiftData, sync, and docs. |
| 3 | [phase-03-execution-read-model-seams.md](phase-03-execution-read-model-seams.md) | Build shared execution read models for current task, remaining/upcoming work, editability, and progress. |
| 4 | [phase-04-preview-edit-contract.md](phase-04-preview-edit-contract.md) | Implement workout preview, explicit start, current-block "what's next", and unified edit surface. |
| 5 | [phase-05-active-rest-transition-redesign.md](phase-05-active-rest-transition-redesign.md) | Redesign active/rest/transition execution surfaces with simulator proof. |
| T1 | [transition-feedback-ripple-alignment.md](transition-feedback-ripple-alignment.md) | Historical feedback-ripple alignment note: side semantics, audit-trail limits, verify sweep, and orphan-preservation disposition. |
| 6 | [phase-06-history-post-workout-correction.md](phase-06-history-post-workout-correction.md) | Add full post-workout correction, unilateral history display, and duration/distance edit parity inside the current non-audit-grade provenance contract. |

Future Watch, in-app Claude, and modifier/equipment work is intentionally not
listed here as deferred phases. Use `docs/feature-gap-map.md` to find the owning
gap IDs, then create a fresh phase or implementation plan when the work is
selected.

## Historical Done Standard

These were the done standards for this completed phase arc:

- Its implementation plan had been moved to `docs/plans/active/` or explicitly
  refreshed in place before work started.
- Code/docs are implemented for that phase only.
- The proof map has run with the strongest practical boundary checks.
- iOS simulator QA has been captured for user-facing app changes.
- Real-device Watch/HealthKit proof is captured where the phase claims it.
- Independent Codex review returns clean or all real findings are addressed.
- `docs/feature-gap-map.md` and owning feature docs reflect closed and open gaps.

## Transition Gates

Transition plans were short cleanup units between numbered phases. They did not
add app behavior. T1 is kept here as historical context for the Phase 6 history
scope and the current non-audit-grade provenance contract; it is not a standing
gate for future work.

## What Is Not Generalized Yet

- No multi-user migration strategy.
- No legacy compatibility layer for old watch messages.
- No direct Watch-to-server sync.
- No route/directions work before watch authority and GPS ownership are proven.
- No in-app Claude/chat implementation until the requirements/design workflow in
  `docs/features/in-app-claude.md` is selected and planned.
- No CloudKit replication or Cloudflare Zero Trust endpoint replacement until
  `docs/sync.md` future replication and endpoint directions are spiked
  independently.
