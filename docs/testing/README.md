---
title: Testing Subdocs
status: accepted
last_reviewed: 2026-05-18
purpose: Index for detailed proof-pattern guidance under docs/testing/.
covers:
  - docs/TESTING.md
  - docs/testing/
---

# Testing Subdocs

`docs/TESTING.md` is the entry point for the repo proof contract. These subdocs
hold reusable proof patterns for implementation plans, reviews, and testing
audits.

## Index

- `proof-patterns.md` — reusable proof selection by change shape. Start here
  when deciding what kind of test or harness a plan needs.
- `app-state-and-persistence.md` — SwiftData, local stores, session snapshots,
  destructive reset, sync ownership, background/foreground lifecycle, and
  local-service probes.
- `execution-and-editing.md` — primitive execution, timers, route transitions,
  current/remaining/upcoming projections, set edits, preview edits, history
  corrections, and shared edit invariants.
- `external-boundaries.md` — HealthKit, WorkoutKit, WatchConnectivity,
  Cloudflare Access, real HTTP, simulator vs real-device proof, and
  capability-gap language.
- `runtime-and-ui-proof.md` — ETTrace, memgraph/leaks, XCUITest action identity,
  snapshot UI, DesignSystem/accessibility proof, and what visual QA can and
  cannot prove.

## Maintenance Rule

Add guidance here when a review, QA run, or testing audit finds a reusable proof
gap. Keep one-off examples in tests or bug regressions. These docs should stay
small enough that implementation plans can cite the relevant proof pattern
without creating a new mini testing policy every time.
