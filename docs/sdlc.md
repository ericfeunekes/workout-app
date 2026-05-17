---
title: Software development lifecycle
status: living
last_reviewed: 2026-05-17
purpose: Progressive-disclosure workflow from durable requirements to backlog lanes, phase planning, implementation planning, and gap closeout.
covers:
  - docs/backlog.md
  - docs/feature-gap-map.md
  - docs/runbooks/closeout.md
  - docs/WORKFLOW.md
---

# Software Development Lifecycle

This repo uses progressive disclosure for planning. Requirements stay durable.
The backlog routes gaps into lanes. Phase and implementation plans are working
artifacts in `scratch/`, created only for the active work tree.

## The Work Tree

A work tree is the scoped body of work being planned or implemented. It can be:

- a full backlog lane, when the lane is small enough to reason about as one unit
- a series of phases inside a lane, when the lane needs sequencing
- one phase inside a lane, when implementation is ready to start

Do not create durable plan directories under `docs/`. Durable docs answer what
the system must do. `scratch/` answers how this selected work tree will move
right now.

## Lifecycle

```
request or gap
  -> requirements planning
  -> backlog lane routing
  -> active lane selection
  -> phase planning when needed
  -> implementation planning
  -> implement / review / verify
  -> close gaps and update backlog
```

### 1. Requirements Planning

Use `scoping:requirements-planning` when a feature, domain, or user need is not
captured durably, or when an existing requirement is too thin to govern future
work.

Requirements belong with the feature, domain, or aspect they describe:

- user-visible behavior in `docs/features/`
- cross-cutting domain contracts in files such as `docs/sync.md`,
  `docs/watch-metrics.md`, `docs/modifier-equipment.md`, or
  `docs/workout-execution-requirements.md`
- architecture and schema contracts in `docs/specs/`, `docs/ARCHITECTURE.md`,
  or `docs/MIGRATIONS.md`

If the requirement is incomplete, update the owning docs first. If the gap is
known but not implemented or not proven, add it to the relevant docs'
`Current gaps` sections and index it in `docs/feature-gap-map.md`.

### 2. Backlog Documentation

`docs/backlog.md` is the lane router. It does not define implementation steps,
phase order, historical state, or proof history.

Each backlog lane should say:

- which exact gap IDs it primarily owns
- why the lane exists
- whether it is active, parallel, spike, requirements, or later capability work
- what kind of planning should happen next

The backlog can name broad lanes. It should not freeze the shape of deferred
work. If a deferred feature changes before implementation, update requirements
and the lane row at that time.

### 3. Active Lane Selection

Before building, pick the active work tree:

- one lane if the lane is small
- a phase series if the lane needs sequencing
- one phase if the series is already clear

Active lanes are identified in `docs/backlog.md` by posture and exact primary
gap IDs. The
selected work tree can then use `scratch/` for temporary phase or
implementation planning. If multiple lanes can move in parallel, keep their
scratch artifacts separate and cite the gap IDs each one owns.

### 4. Phase Planning

Use `scoping:phase-planning` only when a selected lane or requirement is too
large for one implementation loop.

Phase planning works at outcome altitude. A phase says what must be true when a
chunk ships and how proof will close it. It does not carry implementation
detail, field names, file rewrites, or stale future guesses.

For this repo, phase plans are ephemeral:

- write them under `scratch/<lane-or-unit>-phase-<slug>.md`
- cite the owning requirement docs and exact gap IDs
- overwrite the scratch phase spec as the plan changes
- delete the scratch file when the work is shipped or abandoned; if a decision
  must survive, promote the durable conclusion to all affected owning docs or
  an ADR

One lane can be one phase. If decomposition adds no clarity, skip phase planning
and go straight to implementation planning.

### 5. Implementation Planning

Use `scoping:implementation-planning` for one phase or one small requirement
unit. The output is an executable plan under
`scratch/<unit-slug>-impl-plan.md`.

Implementation planning binds the durable requirements and phase outcome to:

- concrete code surfaces
- proof map entries tied to `docs/TESTING.md` and `docs/QA.md`
- review gates
- closeout expectations
- stop conditions for missing contracts or wrong phase boundaries

If implementation planning discovers a missing durable invariant, state
authority rule, identity contract, or acceptance criterion, stop and route back
to requirements planning. Do not hide durable truth inside scratch.

### 6. Implementation, Review, and Verification

Implement from the selected scratch plan or from the conversation for trivial
work. Non-trivial work follows the implementer/reviewer loop in
`docs/WORKFLOW.md`: implement, run local gates, dispatch independent review,
fix, and repeat until clean.

Verification must match the touched surfaces:

- `make check` for repo-wide server/schema gates
- simulator or device proof for user-facing iOS behavior
- real-device proof for Watch or HealthKit claims
- targeted docs validation for documentation-only changes

### 7. Closeout

Use `docs/runbooks/closeout.md` before declaring work done.

When work closes or changes gaps:

1. Update the owning requirement docs' `Current gaps` sections.
2. Remove, narrow, or add rows in `docs/feature-gap-map.md`.
3. Update `docs/backlog.md` only if lane ownership, posture, or next planning
   move changed.
4. Delete any scratch phase or implementation plan that no longer describes
   active work. If its rationale must survive, promote the durable conclusion
   to all affected owning docs or an ADR.
5. Run the relevant verification gates and record any residual risk in the
   final handoff.

Backlog rows are not completion records. If a gap is closed, remove it or narrow
it to the remaining missing behavior. Git history is the archive.
