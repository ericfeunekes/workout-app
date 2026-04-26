---
title: block-transition
status: implemented
last_reviewed: 2026-04-26
purpose: Target contract and QA scenarios for the between-block setup surface.
covers:
  - docs/features/execute-loop.md
  - app/Packages/Features/Execution/
---

# block-transition

## Target behavior

When one block ends and the next block requires a different physical setup, the
app shows a transition surface before entering the next active task.

The transition answers:

- what just finished
- what block is next
- what equipment, load, side, distance, duration, or timing setup is needed
- what the first action in the next block will be

This is not a motivational or filler screen. Every visible field should help the
athlete prepare for the next block.

## State surface

- **Inputs:** current block summary, next block prescription, timing config,
  exercise catalog, authored block intent, and any carry/duration/distance
  targets.
- **Outputs:** transition read model and a single advance action into the next
  active route.
- **State transitions:** active/rest completion may route to transition before
  the next block. Advancing from transition moves to the next block's correct
  starting route.

## Deliberate non-goals

- No plan mutation from transition.
- No editing sets here unless the shared SetEditSheet is explicitly invoked by
  a later implementation phase.
- No duplicate rest timer if the next block starts with a rest block; the route
  should be one coherent state.

## Current gaps

- Block intent display needs `block.intent` authoring/display cutover before the
  transition can show intent beyond timing mode and setup lines.
- Same-setup adjacent blocks currently still show transition when the next work
  block has item setup. Skipping low-value same-setup transitions remains polish.
- Route/direction integration is deferred to the later mapping feature.

## Proof

- Codex review thread `019dcbb2-85e7-7340-ba0c-eb4ee8a8007f` returned clean
  after transition, skip, composite, setup-detail, and `READY` timer fixes.
- Simulator QA: `scratch/qa-runs/phase-05-transition-screen.md`.
- Screenshots:
  `scratch/qa-runs/phase-05-transition-screen-final.jpg` and
  `scratch/qa-runs/phase-05-transition-active-after-start-final.jpg`.

## QA scenarios

### S1. Strength block to conditioning block

- **setup:** workout has a straight-set strength block followed by an AMRAP or
  For Time block.
- **steps:** finish the final strength set and advance.
- **expected:** transition shows next block name/intent, equipment/setup, and
  first task before entering the conditioning timer.

### S2. Same-setup adjacent blocks

- **setup:** two adjacent blocks use the same equipment and no special setup.
- **steps:** finish block one.
- **expected:** implementation may skip transition if there is no useful setup
  information, or show a minimal transition with only purposeful content.

### S3. Rest block transition

- **setup:** next block is a standalone rest block.
- **steps:** finish prior block.
- **expected:** app does not show dead active content; it enters a coherent rest
  state or transition-to-rest state with the rest countdown visible.

### S4. Carry/distance setup

- **setup:** next block includes carries or distance/duration targets.
- **steps:** reach the transition.
- **expected:** transition shows the target distance/duration/load details that
  are needed before starting.
