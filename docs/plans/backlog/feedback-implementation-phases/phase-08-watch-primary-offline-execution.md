---
title: Phase 8 — watch-primary offline execution implementation plan
status: backlog
last_reviewed: 2026-04-26
purpose: Let the Watch start and run a workout as primary from cached executable data, then replay events to the phone.
covers:
  - app/Packages/WatchBridge/
  - app/Packages/Features/WatchFaces/
  - app/Packages/HealthKitBridge/
  - app/WorkoutDBWatch/
  - app/Packages/Shell/
  - app/Packages/Features/Execution/
---

# Phase 8 — Watch-Primary Offline Execution

## Unit Statement

Implement watch-primary start, offline execution event logging, and idempotent
reconnect replay to the phone.

## Boundaries Touched

- Watch executable workout cache.
- Watch-side event log and timers.
- Authority handoff/start rules.
- Phone replay inbox and idempotent application.
- HealthKit HR/workout-session integration.

## Dependencies And Preconditions

- Phase 7 platform spike and protocol foundation are complete.
- Phase 9 UI is not required; simple watch faces may drive the event path.
- This phase still requires end-to-end real-device watch-primary proof; Phase 7
  platform notes do not substitute for disconnect/reconnect QA.

## Uncertainty Reduction Summary

- Architecture/history: Watch currently mirrors only and does not run reducer.
- Blast radius: watch-primary creates a second execution authority and must
  replay to phone without duplicate logs.
- Platform: Simulator cannot prove queued delivery or HealthKit behavior.

## Approach

Keep the Watch event-sourced. Do not sync directly to server. The Watch records
events; the phone validates and applies them, then uses existing sync.

## Steps

1. Define executable workout package and deterministic spec revision.
2. Cache latest executable package on Watch.
3. Add watch-primary start from cache.
4. Add watch event log with event IDs, authority epoch, cursor/spec snapshot.
5. Implement manual transitions and timer events on Watch.
6. Implement phone reconnect replay, duplicate suppression, and stale rejection.
7. Add HealthKit HR capture for watch-primary sessions.
8. Run real-device and simulator proof.

## Good

- Watch can start a cached workout without phone reachability.
- Watch can continue timers and manual transitions disconnected.
- Reconnect replay produces one set of phone logs/status updates.
- Phone remains the only server-sync owner.

## Done

- Real-device proof shows watch start, disconnect period, reconnect replay.
- Replaying the same event batch twice is idempotent.
- Stale epoch/spec/cursor events are rejected safely.

## Proof Map

- Check: pure event-replay tests.
  - Boundary: pure computation.
  - Proves: idempotency, ordering, stale rejection.
- Check: Watch cache persistence tests.
  - Boundary: persistence.
  - Proves: package/event log survive Watch app restart.
- Check: real-device active-workout termination/relaunch QA.
  - Boundary: external platform + persistence.
  - Proves: Watch event log survives app termination/relaunch during an active
    workout before reconnect replay.
- Check: Shell replay integration tests.
  - Boundary: cross-module.
  - Proves: phone applies valid events and queues normal sync payloads.
- Check: real-device WatchConnectivity/HealthKit QA.
  - Boundary: external platform/user-facing.
  - Proves: disconnected watch-primary behavior.
- Check: iOS simulator regression QA.
  - Boundary: app integration.
  - Proves: phone-primary flow still works.

## Independent Review

- Artifact: watch-primary/cache/event replay diff and real-device evidence.
- Reviewer: Codex focused on duplicate logs, stale authority, and platform-proof
  overclaims.
- Reopen condition: duplicate replay mutates twice, or real-device proof is
  absent while claiming watch-only readiness.

## Closeout

- Update watch feature docs, gap map, and QA notes.
- Record real-device hardware/OS versions in QA evidence.

## Recovery Context

This phase makes Watch primary. It does not build the final metric/directions UI
unless needed as a minimal driver for proof.

## Residual Uncertainty / Accepted Risks

- Programmable double tap may require watchOS 11.
  - Accepted only if manual tap path works and target is documented.
  - Signal: double-tap acceptance criteria cannot be met on deployment target.

## Escalation Triggers

- Real-device WatchConnectivity cannot deliver the required replay semantics.
- Watch local persistence cannot safely retain event logs across termination.
