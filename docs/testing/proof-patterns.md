---
title: Testing Proof Patterns
status: accepted
last_reviewed: 2026-05-18
purpose: Reusable proof selection by change shape for implementation plans, reviews, and test audits.
covers:
  - docs/TESTING.md
  - docs/QA.md
  - docs/feature-gap-map.md
---

# Testing Proof Patterns

Use this when a plan, review, or testing audit needs to decide which proof
surface should carry confidence. The goal is not to document every example. The
goal is to name reusable proof patterns future work can cite.

## How To Pick Proof

Start from the claim, not the file touched.

1. Name the behavior the change claims to alter.
2. Classify the strongest risk shape below.
3. Pick the deterministic or realistic-local harness that can prove that risk.
4. Add QA only for the user-visible or device/runtime behavior that tests cannot
   prove.
5. If the right harness does not exist, record a capability gap instead of
   downgrading to a mock.

Implementation plans should name the proof pattern, the concrete test files or
targets, the failure modes exercised, and any remaining QA or real-device gap.

## Proof Pattern Matrix

| Change shape | Required pre-QA proof | Failure modes to exercise | QA follow-up |
|---|---|---|---|
| Pure helper or formatter | Unit tests in the owning stack | nil/empty, invalid input, boundary values, stable formatting | None unless visible copy/layout changes |
| Server schema or migration | Server model tests, idempotent migration test, cross-stack contract test | repeated migration, missing/extra fields, nullability/type mismatch | Only if app behavior depends on the schema |
| New or changed API endpoint | FastAPI route tests against local SQLite state; auth/header behavior when relevant | rejected auth, invalid payload, duplicate/idempotent write, readback | API result may feed visible QA, but video is not backend proof |
| Sync protocol or real HTTP seam | Swift package tests plus realistic-local FastAPI/SQLite/URLSession probe | offline, stale token, retry, duplicate push, same-UUID upsert, local/server readback | Simulator QA for visible sync/offline/auth state |
| SwiftData persistence or local store | Package or app-hosted tests against local containers/fixtures | failed encode/save, rollback, migration, relaunch, destructive reset | Relaunch/navigation QA when user-facing survival is claimed |
| App lifecycle or background work | Coordinator/state-machine tests plus app-hosted or simulator proof for app-root wiring | foreground pull, background/foreground transition, task restart/stop, stale live session | Simulator QA plus logs/telemetry/readback |
| Execution, timers, and transitions | Clock-controlled reducer/driver tests and fixture matrices | active/rest/complete, skip/done, route change, first/last item, elapsed-time edge | Simulator QA for actual visible route and gestures |
| Shared edit or correction surface | Shared invariant tests across preview/active/history contexts | apply-to-remaining, cancel, commit, invalid edit, audit/overwrite semantics | Simulator QA for sheets, navigation, and destructive confirmations |
| Mapper or export target | Vendor-neutral input/output contract tests with degradation assertions | unsupported facts, target limits, no target-specific inference without source authority | External app/device verification only for target visibility/startability |
| Telemetry or diagnostics | Event truthfulness tests comparing event payloads to the real state rows/actions | missing event, false event, partial failure, retry/de-dupe | QA can inspect surfaced diagnostics, not event truth alone |
| DesignSystem or accessibility surface | Component-level tests/snapshots or UI hierarchy assertions where available | labels/traits, disabled state, hit target, Dynamic Type, clipping | Visual/accessibility QA for important screens |
| Runtime cost or object lifetime | ETTrace, memgraph, leaks, or lifecycle-specific harness | retained view model/task/store, hot render path, sheet loop, save/reset leak | Video can show symptoms only; it cannot prove cause |
| Apple/API/device boundary | Fake/unit tests for app logic plus simulator/API-contract or real-device proof depending on claim | denied permission, unavailable API, missing sample, simulator capability limit | Real device required for sensors, haptics, sleep/wake, Fitness/Workout UX |
| Architecture boundary | Import-linter contract, code-boundary test, or explicit structural check | wrong dependency direction, duplicate side-effect owner, target-specific leak into core | None unless architecture change affects visible behavior |

## Review And Audit Feedback Loop

When a review or testing audit finds a bug that escaped existing tests, ask:

- Did we miss a one-off regression test, or a reusable proof pattern?
- Would future work in the same risk class be under-specified without new
  guidance?
- Does the guidance belong in this matrix or in a more specific subdoc?

Update the framework only when the answer is reusable. Keep narrow examples in
the test suite, fixture names, or bug regression notes.
