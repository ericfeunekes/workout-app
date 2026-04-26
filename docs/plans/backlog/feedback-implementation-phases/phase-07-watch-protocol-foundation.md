---
title: Phase 7 — watch platform and protocol foundation implementation plan
status: backlog
last_reviewed: 2026-04-26
purpose: Prove real Watch platform constraints, then establish versioned, authority-aware phone/watch protocol before watch-primary execution or watch UI redesign.
covers:
  - docs/plans/backlog/watch-authority-protocol-foundation.md
  - app/Packages/WatchBridge/
  - app/Packages/Features/WatchFaces/
  - app/Packages/Shell/
  - app/Packages/Features/Execution/
---

# Phase 7 — Watch Platform And Protocol Foundation

## Unit Statement

Prove the real-device Watch platform constraints, then replace the current
rendered-string watch bridge with versioned, identity-bearing, authority-aware
display and action messages while keeping the phone primary.

## Existing Plan

This phase incorporates and supersedes the older parked plan:

- `docs/plans/backlog/watch-authority-protocol-foundation.md`

Refresh that plan against Phases 1-6 before moving this phase to active.

## Boundaries Touched

- `WatchBridge` wire vocabulary and Codable tests.
- `FeaturesWatchFaces` display snapshot consumption and action emission.
- `Shell` watch mirror controller/inbox.
- `FeaturesExecution` projection seam only; no `WatchBridge` dependency.

## Dependencies And Preconditions

- Phase 3 execution projection exists.
- Phase 5 execution surfaces have stable current/upcoming semantics.
- Watch remains secondary in this phase.
- Real-device WatchConnectivity, background/wake behavior, HealthKit access, and
  watchOS deployment target assumptions are spiked before protocol fields are
  frozen.

## Approach

Run the platform spike first so protocol decisions are shaped by observed
WatchConnectivity and HealthKit constraints. Then make protocol identity and
stale-action rejection real before allowing the Watch to mutate workout state.

## Steps

1. Run real-device platform spike for WatchConnectivity delivery, background
   wake behavior, HealthKit workout/HR access, and watchOS double-tap target.
2. Freeze protocol assumptions and deployment-target notes from the spike.
3. Define v2 envelope, session identity, authority epoch, cursor identity, spec
   revision, action ID, display snapshot, primary action, action ack.
4. Replace v1 rendered messages.
5. Update fake and live WatchBridge.
6. Update WatchFaces to render snapshots and emit identity-bearing actions.
7. Add Shell-owned mirror controller and inbox.
8. Reject mutating watch actions while phone-primary.
9. Add protocol, fake bridge, Shell, and simulator proof.

## Good

- Watch messages are versioned and reject stale actions.
- Watch no longer fabricates workout item IDs.
- Execution does not import WatchBridge.
- Phone-primary mirror works without giving Watch mutation authority.
- Protocol and deployment-target decisions reflect observed real-device
  constraints, not assumptions.

## Done

- Existing watch faces compile against v2 snapshots.
- Real-device platform spike is recorded before protocol implementation is
  called ready.
- Stale/duplicate/secondary-authority actions are acknowledged and rejected.
- iOS simulator QA proves phone execution still works with watch mirror wiring.

## Proof Map

- Check: real-device platform spike notes.
  - Boundary: external platform.
  - Proves: WatchConnectivity, background/wake, HealthKit, and watchOS target
    assumptions that shape the protocol.
- Check: WatchBridge Codable tests.
  - Boundary: wire contract.
  - Proves: envelope/version/message compatibility and fail-closed behavior.
- Check: FakeWatchBridge tests.
  - Boundary: transport abstraction.
  - Proves: messages flow and actions carry identity.
- Check: Shell tests.
  - Boundary: cross-module composition.
  - Proves: snapshots sent, inbox rejects stale/secondary actions.
- Check: `rg -n "WatchBridge" app/Packages/Features/Execution`.
  - Boundary: architecture.
  - Proves: dependency direction preserved.
- Check: simulator QA.
  - Boundary: user-facing integration.
  - Proves: app still starts/runs execution.

## Independent Review

- Artifact: WatchBridge/Shell/WatchFaces diff.
- Reviewer: Codex focused on stale-action safety and dependency direction.
- Reopen condition: Watch can mutate phone-primary state or Execution imports
  WatchBridge.

## Closeout

- Update watch docs and this phase index.
- Keep real-device WatchConnectivity limits explicit.

## Recovery Context

Phone-primary protocol only after the platform spike. Do not implement
watch-start, handoff, event replay, or the three-view watch UI here.

## Residual Uncertainty / Accepted Risks

- Full disconnected watch-primary behavior is not proven here.
  - Accepted because Phase 8 owns watch-primary event replay and disconnect QA.
  - Signal: platform spike shows mirror delivery constraints that invalidate
    the planned protocol.

## Escalation Triggers

- Shell cannot own a single inbox lifecycle cleanly.
- Protocol fields require persistent session identity not yet available.
- Platform spike contradicts assumed delivery, wake, HealthKit, or deployment
  target constraints.
