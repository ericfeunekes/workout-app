---
title: Workout system implementation roadmap
status: backlog
last_reviewed: 2026-05-17
purpose: Connect the feedback, primitives, and watch phase tracks into one pickup map.
covers:
  - docs/plans/backlog/feedback-implementation-phases/
  - docs/plans/backlog/primitives-cutover-phases/
  - docs/specs/primitives-data-model.md
  - docs/watch-metrics.md
---

# Workout System Implementation Roadmap

This is the pickup map for the current workout-app arc. Do not treat the phase
directories as competing roadmaps. They are different delivery tracks inside
one product direction: make workout execution, review, correction, and watch
support match the way workouts are actually performed.

## Where we landed

The app feedback track has already produced implementation:

- Preview-first workout entry is implemented.
- Execution read-model seams and redesigned active/rest/transition surfaces are
  implemented.
- History review, exercise detail, post-workout correction, and the shared set
  edit sheet are implemented.
- History data-integrity fixes for edited sets are implemented.

The primitives track has not produced implementation yet:

- `docs/specs/primitives-data-model.md` is the accepted target spec.
- `docs/specs/primitives-data-model/` documents authoring shape, log shape,
  runtime resolution, and cutover posture.
- `docs/plans/backlog/primitives-cutover-phases/` decomposes the cutover into
  Phase 1 through Phase 4, with later history/docs phases deferred until the
  implementation creates real ground truth.

The watch track is still downstream:

- Watch authority, watch-primary offline execution, and watch metrics/directions
  UI are sketched in the feedback phase directory, but the backlog phases are
  provisional and have not been implemented.
- The watch UI should consume the corrected execution/history model and should
  be reconciled with the primitives slot model before implementation planning.

## How the tracks relate

1. **Feedback phases 1-6** make the current iPhone app usable and correct for
   workout preview, live execution, history review, and post-workout editing.
   This is where the history picker/review/correction work belongs.
2. **Primitives cutover phases** replace the underlying timing-mode-coupled
   data shape with Block > Set > Slot primitives. This is architectural
   substrate for future workout shapes, not a replacement for the feedback work.
3. **Watch phases 7-9** use the stabilized execution model and the future
   slot-oriented primitives model to deliver phone/watch authority, offline
   watch execution, metric slots, heart-rate persistence, and directions.
4. **Later product phases** such as in-app Claude/chat and richer modifier or
   equipment modeling stay after those foundations.

## Current track state

| Track | Owning docs | Implementation state | Next action |
| --- | --- | --- | --- |
| Feedback execution/history | `docs/plans/backlog/feedback-implementation-phases/` Phases 1-6 | Implemented in current code/docs | Treat as the current app baseline; file new defects in `docs/bugs.md` or a focused follow-up plan. |
| Transition alignment | `docs/plans/backlog/feedback-implementation-phases/transition-feedback-ripple-alignment.md` | Planning/docs alignment only | Keep its constraints in view when touching history, side semantics, audit trail language, or orphan behavior. |
| Primitives data model | `docs/plans/backlog/primitives-cutover-phases/` | Spec and phases documented; implementation not started | Start with primitives Phase 1 via `scoping:implementation-planning`, then review/challenge before coding. |
| Watch authority/offline/UI | `docs/plans/backlog/feedback-implementation-phases/` Phases 7-9 and `docs/watch-metrics.md` | Provisional backlog | Rerun requirements/phase planning against completed feedback work and primitives timing before implementation planning. |
| In-app Claude/chat and modifier modeling | Feedback Phases 10-11 | Provisional backlog | Rerun requirements/phase planning after execution/history/watch foundations are stable enough to consume. |

## Pickup rules

- When someone asks "what phase?", identify the track first. "Phase 1" in the
  primitives cutover is not the same as Phase 1 in the feedback plan.
- History picker, exercise review, and post-workout correction questions belong
  to the feedback execution/history track unless the question is explicitly
  about how those concepts should persist after the primitives cutover.
- Primitives work starts from
  `docs/plans/backlog/primitives-cutover-phases/README.md` and must not be
  reported as already implemented.
- Watch work starts from the feedback Phase 7-9 docs as source material, but
  those docs must be refreshed before implementation planning. The refresh must
  decide whether to wait for primitives or explicitly bridge the current model
  to the future slot contract.
- User-facing app changes still require simulator QA before signoff. Real
  Watch/HealthKit claims require real-device proof.
