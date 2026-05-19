---
title: App State And Persistence Testing
status: accepted
last_reviewed: 2026-05-18
purpose: Proof patterns for SwiftData, local stores, sync ownership, app lifecycle, and realistic-local persistence probes.
covers:
  - app/
  - docs/sync.md
  - docs/TESTING.md
---

# App State And Persistence Testing

Use this when a change affects local state survival, SwiftData, queued writes,
sync ownership, app-root lifecycle, destructive reset, or realistic-local
server/app behavior.

## What Needs More Than Unit Tests

State and persistence claims need readback from the state owner. A screen that
looks correct is not enough proof that the store, queue, or server has the right
row.

Use package or app-hosted tests against local containers when the claim depends
on:

- SwiftData model writes, updates, deletes, migrations, or rollback behavior
- session snapshots, completion records, primitive logs, or local archives
- queued push, retry, duplicate handling, or idempotent same-UUID upsert
- `lastSyncAt`, sync status, token rejection, or offline fallback
- foreground/background lifecycle that starts, stops, or restarts work
- destructive reset or change-server flows

## Required Proof Shapes

### SwiftData and local stores

Tests should create a controlled local container or fixture store, perform the
same write path production uses, and read the persisted objects back through the
owning repository/store API.

Exercise:

- successful write and readback
- invalid or partial payload rejection
- failed encode/save path when the implementation can surface it
- relaunch or rebuild when the claim is state survival
- destructive reset when data should be removed
- migration path when schema changes

### Sync and queue ownership

Use deterministic transports for package-level logic and realistic-local probes
for boundary claims.

`make test-sync-real-http` is the current realistic-local harness. It starts
FastAPI against a temporary SQLite database, seeds primitive workout data
through real HTTP, drives the Swift Sync stack through `URLSessionTransport`,
writes through SwiftData, pushes slot and aggregate primitive results back, and
reads the server database to prove persistence plus same-UUID upsert for the
slot row.

Run this harness when the claim depends on:

- real URLSession behavior
- auth headers or token rejection
- primitive result push plus server persistence
- FastAPI request/response behavior
- local SwiftData write followed by server readback

Aggregate rows are currently proven for persistence, not repeated upsert. If a
change claims aggregate idempotency, extend the harness instead of assuming the
slot proof covers it.

### App lifecycle

Lifecycle proof must include the owner that actually receives app-root signals.
Package tests can pin coordinator behavior, but app-root scene phase wiring
needs app-hosted or simulator evidence.

Exercise:

- foreground pull
- cache writeback
- `lastSyncAt` update
- push flusher start, restart, and stop posture
- token rejection and offline fallback
- lifecycle telemetry that matches the state transition

Current gap `TEST-GAP-004`: package tests cover the Shell app-sync coordinator,
but simulator/app-root evidence does not yet prove the running app's
`scenePhase` path invokes that coordinator correctly.

## QA Boundary

Simulator QA can prove the visible response to persistence and sync: pending
state, retry affordance, offline/auth messaging, navigation survival, or relaunch
behavior. It cannot prove the invisible write, queue, server row, or telemetry
truth. Pair the video with store, queue, API, database, or event readback for
those claims.
