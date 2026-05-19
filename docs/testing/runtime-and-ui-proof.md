---
title: Runtime And UI Proof
status: accepted
last_reviewed: 2026-05-18
purpose: Proof patterns for runtime cost, object lifetime, UI automation identity, DesignSystem, and accessibility.
covers:
  - app/
  - docs/design-system.md
  - docs/QA.md
  - docs/TESTING.md
---

# Runtime And UI Proof

Use this when a change claims better performance, safer object lifetime,
correct UI action identity, DesignSystem behavior, accessibility, or simulator
UI coverage.

## Runtime Proof

Runtime proof is still pre-QA when the claim is about cost, object lifetime, or
app lifecycle behavior. Simulator video can show a symptom; it cannot prove the
cause.

Use ETTrace when changing or claiming performance for:

- ticking timer routes, especially Active/Rest flows with `TimelineView` or
  frequent state updates
- launch, bootstrap, and first visible render latency
- scroll-heavy Today and History lists
- any SwiftUI refactor whose purpose is fewer view updates, less CPU, or less
  layout churn

Use memgraph/leaks proof when changing or claiming object lifetime for:

- save-and-done, reset/change-server, and next-workout rebuild flows
- sheet open/dismiss loops
- History list -> detail -> back navigation
- foreground/background task lifetime, especially push flusher and sync tasks
- closures that retain view models, stores, or async pipelines

Store raw runtime artifacts under `scratch/qa-runs/<YYYY-MM-DD>-<slug>/` while
the run is active. A durable closeout should summarize the focused flow,
simulator/device, app build, app-owned hot types or leaked types, and whether
the trace/memgraph actually proves the claim. Do not promote runtime behavior
to `verified` from source inspection alone.

Run `make qa-runtime-ready` before trace/memgraph work. It verifies the local
XcodeBuildMCP, `xctrace`, `simctl`, and `leaks` tool surface and creates the
scratch artifact root. It does not capture traces by itself.

## UI Automation Identity

UI tests should prove that the right production action happened, not just that
a screen opened.

For action-heavy UI tests, make the matrix or helper assert:

- each row declares the required runtime action
- direct actions and sheet-opening actions use different helpers
- sheet-opening actions commit the sheet when commit is part of the behavior
- expected route changes are asserted directly
- force-ending a workout is not used as a substitute for the target action

`make test-execution-ui` and `make test-workout-type-ui` are the current named
targets for execution-route UI proof.

## DesignSystem And Accessibility

DesignSystem and accessibility work should have component-level proof where the
repo has a practical harness, plus simulator QA for the screens that matter.

Pre-QA proof should cover:

- accessibility labels, traits, enabled state, and identity where testable
- hit target size for reusable controls
- Dynamic Type behavior for reusable text or controls
- disabled/loading/error state semantics
- stable component APIs that do not leak feature-specific behavior

Simulator QA should inspect text clipping, overlap, contrast, spacing, hierarchy
and whether controls are possible to hit in the actual screen flow.

## What Visual QA Can And Cannot Prove

Visual QA can prove:

- visible UX state
- gesture flow
- navigation and sheet presentation
- text clipping or overlap
- obvious accessibility/hit-target problems
- visible timer or route behavior

Visual QA cannot prove by itself:

- store writes or rollback
- server persistence
- queued push or duplicate handling
- event truthfulness
- CPU/render cost
- object lifetime
- external API correctness

For invisible claims, pair QA with tests, readbacks, logs, probes, traces, or
memgraphs that inspect the owner of the state.
