---
title: In-app Claude handoff
status: planned
last_reviewed: 2026-05-17
purpose: Target contract for future in-app Claude/chat workflows without turning the app into a programming agent.
covers:
  - docs/features/today.md
  - docs/features/workout-preview.md
  - docs/features/history.md
  - docs/sync.md
---

# In-app Claude Handoff

## Target behavior

The app may eventually let Eric ask Claude about the current workout, request a
change, review proposed edits, and accept or reject those edits in the app. That
surface is separate from History notes and from the current copy-to-Claude
adjustment prompt.

The durable rule is still **dumb app, smart conversation**. Claude proposes or
authors workout changes; the app displays them, asks for explicit acceptance
when they would mutate local workout state, and applies only accepted changes.
The app must not infer programming, periodization, progression, substitutions,
or readiness on its own.

## State and authority

- Claude remains the programming and plan-authoring authority.
- The app owns local execution state and completed workout results.
- A Claude proposal is not a mutation until Eric accepts it.
- Accepted workout-template changes must respect the sync contract in
  `docs/sync.md`: plans flow into the app from the plan authority; results flow
  out of the app.
- Notes are context, not a command channel. A note can be sent to Claude or
  attached to a workout, but a note does not silently mutate a workout.

## Required workflow shape

Future planning should preserve these user-visible steps:

1. **Ask or send context.** Eric can ask about the current plan, active workout,
   completed workout, or correction need.
2. **Claude proposes.** The proposal is inspectable before application. It names
   the affected workout, blocks, items, fields, and rationale.
3. **Eric accepts or rejects.** Applying a proposal is an explicit user action.
4. **The app applies only accepted changes.** The applied change uses the same
   state authority and persistence rules as any other workout edit or result
   correction.

## Non-goals

- No autonomous app-side programming logic.
- No unreviewed Claude mutation of local workout state.
- No hidden use of History notes as commands.
- No replacement of the current copy-to-Claude handoff until a concrete
  accepted workflow is planned and proven.
- No broad chat infrastructure requirement before a specific user workflow is
  selected.

## Current gaps

- `CHAT-GAP-001`: No accepted product/design surface exists for in-app Claude
  interaction. A future requirements/design pass must decide the first workflow:
  current-workout question, proposed edit, post-workout review, or note/context
  handoff.
- `CHAT-GAP-002`: No proposal data contract exists. Before implementation,
  define how a proposal identifies affected workouts/blocks/items/fields, how
  it represents rationale, and how it is accepted or rejected.
- `CHAT-GAP-003`: No trust boundary exists for app-applied Claude changes.
  Future planning must prove that Claude proposals cannot bypass explicit
  acceptance or mutate state through notes.

## Acceptance criteria

1. A future in-app Claude workflow keeps proposal, acceptance, and application
   as separate observable steps.
2. Rejected proposals leave local workout, execution, and history state
   unchanged.
3. Accepted proposals use the owning feature's normal mutation and sync path;
   no private side channel writes workout state.
4. Notes remain context unless a separately accepted proposal maps them to a
   concrete state change.
