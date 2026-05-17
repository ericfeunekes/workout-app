---
title: app-intents
status: planned
last_reviewed: 2026-05-17
purpose: Future Apple App Intents and system-surface contract for opening WorkoutDB flows safely.
covers:
  - app/
  - docs/features/today.md
  - docs/features/execute-loop.md
  - docs/features/history.md
  - docs/sync.md
---

# app-intents

## Target behavior

Apple App Intents are future system entry points for opening useful WorkoutDB
surfaces from Shortcuts, Siri, Spotlight, widgets, controls, or other
intent-driven Apple surfaces. They are not the same thing as WorkoutDB block
intent, workout intent, or Claude programming intent.

The first accepted shape is open-app handoff only:

- open Today
- continue the current active workout
- open History or a selected completed session when identity is safe

Mutation intents are deferred. Logging a set, saving a workout, changing body
weight, swapping exercises, editing prescriptions, or resetting data from an
App Intent would cross offline, auth, persistence, telemetry, and accidental
activation boundaries that are not yet specified.

## State and authority

App Intents may read enough lightweight state to route into the app, but they do
not become a second execution engine. The app remains the authority for local
live-session state and logged results. Claude/server remains the authority for
planned workouts. If a later intent mutates state, that requirement must name
the same persistence, sync, telemetry, and user-confirmation guarantees as the
in-app flow.

## Deliberate non-goals

- No direct "log set" or "save workout" intent in the first pass.
- No workout programming, exercise selection, progression, or analysis.
- No broad personal-data export through App Intents.
- No widget/control mutation until the in-app mutation contract is proven.

## Current gaps

- `APPINTENT-GAP-001`: No accepted Apple system-surface contract exists beyond
  this planned feature shell.
- `APPINTENT-GAP-002`: Handoff routes for Today, Active, and History are not
  specified in app routing or debug launch terms.
- `APPINTENT-GAP-003`: Mutation intents are explicitly deferred until offline,
  auth, persistence, telemetry, and confirmation semantics are defined.
- `APPINTENT-GAP-004`: App entity identity for workouts/sessions is not
  specified; do not expose entity shortcuts until identity and privacy posture
  are written.

## Proof expectations

Future implementation must use the `ios-app-intents` skill. Proof must include:

- package/app target wiring for the App Intents extension or app-integrated
  intents
- simulator/device invocation proof for each open-app route
- telemetry or log readback proving the route opened the intended app surface
- no mutation side effects for open-only intents
