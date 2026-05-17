---
title: Primitives data model cutover — phase plan
status: backlog
last_reviewed: 2026-05-17
purpose: Decompose the primitives-data-model spec into phases, each an outcome-level deliverable that implementation-planning consumes one at a time.
spec:
  - docs/specs/primitives-data-model.md
  - docs/specs/primitives-data-model/authoring-shape.md
  - docs/specs/primitives-data-model/log-shape.md
  - docs/specs/primitives-data-model/runtime-resolution.md
  - docs/specs/primitives-data-model/cutover.md
covers:
  - docs/plans/backlog/primitives-cutover-phases/phase-*.md
supersedes_plans:
  - docs/plans/archive/cluster-rest-pause-architecture.md (cluster becomes a structural multi-slot composition under the new model; that plan's slot/intra-set-rest design is subsumed by Phase 4)
---

# Primitives data model cutover — phase plan

This directory decomposes the primitives-data-model spec into phases. The spec itself is accepted; what remains is the delivery sequence.

Each phase is a deliverable unit at outcome altitude — it names what must be true when the phase is done, not how the code will change to make it true. Implementation-planning takes one phase spec and turns it into a proof-mapped plan at code altitude. A phase spec that needs struct fields, file paths, or method signatures to be readable is at the wrong altitude and should be pushed down.

This directory is one track in the broader `docs/plans/backlog/workout-system-roadmap.md`. It should be read after the completed feedback execution/history phases, because those phases describe the current app baseline that the primitives cutover must replace without losing user-facing behavior.

## The feature in one sentence

Replace today's 12-case timing-mode coupling (per-mode prescription shape + per-mode driver + per-mode log shape) with a composable primitive hierarchy — Block > Set > Slot — so that every workout pattern Eric authors becomes a composition of existing primitives rather than a new enum case.

## Current landing status (2026-05-17)

This documentation unit has landed the target direction, not the implementation.

What is now documented:

- `docs/specs/primitives-data-model.md` is the accepted target spec for the primitives shape.
- `docs/specs/primitives-data-model/` breaks the target into authoring shape, log shape, runtime resolution, and cutover posture.
- `docs/AGENTS.md` and `docs/specs/v2-architecture.md` now route future data-model readers to the primitives spec where it supersedes the older v2 data-model section.
- This directory defines the delivery sequence through Phase 4, with Phases 5 and 6 deliberately deferred until implementation ground truth exists.

What has not landed:

- No server schema, API, OpenAPI, Swift DTO, SwiftData, execution reducer, push-queue, sync, fixture, or simulator-facing implementation has changed for primitives yet.
- No compatibility path is intended. The implementation remains a future complete cutover: old-shape prescriptions and result payloads stop being accepted, while completed local workout history is preserved through an explicit migration path.
- No phase has gone through `scoping:implementation-planning`, implementation, review, or QA yet.

The next operating loop is:

1. Convert Phase 1 into a proof-mapped implementation plan.
2. Challenge/review that plan before coding.
3. Implement Phase 1 through storage round-trip proof across server, shared schema, and app persistence.
4. Run the phase's local test proof and simulator QA before moving to Phase 2.
5. Repeat the same plan -> review -> implement -> review -> QA loop for Phases 2, 3, and 4.
6. Re-plan Phases 5 and 6 only after Phase 4 shows the real correction, history, aggregate-row, and docs-drift surface.

The current proof state is documentation-only. The meaningful implementation proof starts with Phase 1.

## Relationship to feedback and watch work

The history picker, exercise review, post-workout correction, and set editing
work belong to the feedback implementation track, where Phases 1-6 are already
implemented. This primitives directory does not reopen that work; it defines the
future storage and execution substrate that must preserve those behaviors after
the cutover.

Watch work is downstream of both tracks. The watch authority and watch-primary
phases consume the execution baseline from the feedback track. The watch
metrics/directions UI should be reconciled with the primitives slot model before
implementation, because fixed watch slots and primitive workout slots need to
remain conceptually aligned.

## Why this is phased

The cutover spans server schema, shared DTOs, the prescription parser, the session seed, all 12 timing drivers, the execution view model, the persistence layer, the push queue, the sync endpoint, and several feature docs. A single review cycle cannot hold that surface area coherently — a reviewer asked to read every change at once will either rubber-stamp or livelock.

Phasing lets each review loop exercise a coherent slice: one phase's outcome becomes the substrate the next phase consumes. The full cutover lands as one PR per the repo's complete-cutover philosophy, but the execution proceeds gate-by-gate on the branch with each phase's outcome exercisable on its own before the next begins. These are branch checkpoints, not deployable releases; the only mergeable state is the complete cutover across storage, API, schema, execution, sync, fixtures, tests, and docs.

## Stakeholder map

Different phases improve the system for different stakeholders. Naming the stakeholder per phase keeps the acceptance question honest: would this stakeholder notice the improvement?

- **Claude as author** — the conversational partner that composes workouts. Improves when the authoring vocabulary aligns with primitives.
- **Eric as user** — the sole runner of workouts today. Improves when he can execute the workouts he writes; improves further when new patterns become authorable.
- **Eric as developer / future reader** — the person reading docs and code to change the system later. Improves when docs reflect the model that's actually shipped.
- **Named downstream phase** — the next phase in the list. A phase whose only stakeholder is a later phase is valid substrate as long as that consumer is named.

## Phase list

| # | Phase | Stakeholder | Status |
|---|---|---|---|
| 1 | Primitive workouts round-trip through storage (server + shared schema + app SwiftData — both persistent stores cut over) | Claude as author + Phase 2 | ready for implementation-planning |
| 2 | Straight-sets block executes end-to-end under primitives (execution layer ports against the already-cut-over storage substrate) | Eric (user, branch build) | ready for implementation-planning |
| 3 | All twelve current timing modes execute with behavior parity | Eric (user, branch build) | ready for implementation-planning |
| 4 | Compositional patterns unlocked by primitives become authorable | Eric (user, branch build) | ready for implementation-planning |
| 5 | Correction + history + aggregate-row persistence work under the new shape | Eric (user, branch build) | **deferred** — re-plan after Phase 4 lands |
| 6 | Docs reflect the shipped model; cutover merges to main | Eric (dev / future reader) | **deferred** — re-plan after Phase 5 lands |

Phases 5 and 6 are deliberately deferred. They depend on ground truth the first four phases haven't established yet: Phase 5's correction + aggregate-row story depends on what the driver ports actually produced in Phase 3; Phase 6's docs sweep and merge-ready state depends on what docs genuinely need rewriting vs. what turned out to still apply. Writing concrete phase specs for 5 and 6 today against a hypothetical branch state would miss the details that matter. When Phase 4 lands, re-enter phase-planning with the real state.

### Revision note (2026-04-29, mid-Phase-1; clarified 2026-05-17)

An earlier version of Phase 1 scoped the SwiftData V6 cutover to Phase 2, letting the server's schema advance while the app's persistent store stayed on the legacy shape during Phase 1. The `plan-and-implement` review node correctly flagged this as a storage-surface cutover violation per `CLAUDE.md` § "Development philosophy". The phase plan was revised so Phase 1 includes the SwiftData cutover and the removal of any `MappedWorkout`-style legacy adapter. Phase 2's scope narrows to straight-sets execution on top of an already-cut-over storage substrate.

The 2026-05-17 scoping review narrowed that statement: complete-cutover applies
to the surfaces each phase owns, while the phase itself remains a branch
checkpoint. Phase 1 is not a deployable release because execution has not been
ported yet; it is done only when the storage contract is fully primitive-shaped
with no legacy adapter in that storage path.

## Sequencing

Phases run in order. The dependency graph forces this:

1. Phase 1 establishes the wire format + storage shape. Nothing after Phase 1 has a stable contract to read until Phase 1 closes.
2. Phase 2 establishes the execution pattern against that contract for one timing mode. The pattern becomes the template Phase 3 applies to the rest.
3. Phase 3 fans out the Phase 2 pattern to the remaining timing modes. Phase 4 depends on every driver being portable against the new contract.
4. Phase 4 exercises the primitives' new expressive power. Compositional patterns (cluster, sibling work+rest, compound work targets) exist only after the driver pattern is proven broadly enough to compose cleanly.

Within each phase, the implementing agent produces a proof-mapped plan via `scoping:implementation-planning` and the branch advances only when that phase's proof is green.

## What each phase spec carries

The per-phase files in this directory follow the outcome-altitude contract from `scoping:phase-planning`:

- **Unit statement** — one sentence carrying what the phase delivers.
- **Why** — the concrete pressure driving this phase.
- **Acceptance criteria** — outcomes that must be observable when the phase is done.
- **QA contract** — the proof that each criterion is met, tiered into merge-gate and RC-gate where relevant.
- **Scope / out-of-scope** — what the phase owns; what it deliberately doesn't own.
- **Constraints** — repo invariants that must hold.
- **Ordering within the phase** — internal sequencing, if any.
- **Known hazards** — gotchas an implementer needs to know.
- **Proof commands** — the level of "full suite passes," not specific test names.

Implementation-planning reads one phase spec and produces the proof-mapped code-altitude plan. If a phase spec reads as ambiguous or contradictory to implementation-planning, the route is back here, not down to the code.

## Constraints that cross all phases

These are invariants from `CLAUDE.md` and `docs/MIGRATIONS.md` that every phase must respect:

- **Single-user dev posture.** The cutover drops server-side prescriptions and old-shape acceptance. Completed local workout history must survive. If a broader preservation constraint appears before the cutover lands, the entire phase plan is invalid and must be rewritten.
- **Complete cutover on merge.** The final PR ships the whole cutover at once. No feature flags, no parallel code paths, no legacy acceptance shims. Mid-branch state during phases 1–6 is allowed to be incomplete; the merged state must be whole.
- **Phase gates are not merge gates.** A phase may close on the branch with later surfaces still unsupported, as long as the phase's owned surfaces do not carry compatibility fallbacks and the next phase has a named consumer relationship.
- **Claude owns exercise identity.** No phase introduces server-side exercise-name canonicalization.
- **Offline-first execution.** The app must execute a pulled workout with no network calls. A phase that introduces a network dependency inside the execution loop is an invariant violation.
- **Idempotent upserts.** Log rows keyed on composite identity round-trip without duplication or loss. A phase that breaks this is not done.

## Supersedes / subsumes

- `docs/plans/archive/cluster-rest-pause-architecture.md` — that plan designed cluster/rest-pause as a small new session primitive layered onto the existing timing-mode model. Under the primitives model, cluster is a structural composition (one set with N slots, same exercise, per-slot reps, post-slot rest). Phase 4 delivers the primitive-compositional version; the superseded plan is retained as reference for intra-slot rest and composite-set risks.
