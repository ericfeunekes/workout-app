---
title: Watch authority protocol foundation implementation plan
status: backlog-wip
purpose: Build the first implementation unit for the Apple Watch redesign: a versioned, authority-aware phone/watch protocol and phone-primary mirror path.
covers:
  - docs/features/watch-primary-execution.md
  - docs/watch-metrics.md
  - app/Packages/WatchBridge/
  - app/Packages/Features/WatchFaces/
  - app/Packages/Shell/
  - app/WorkoutDBWatch/
---

# Watch authority protocol foundation implementation plan

## Backlog Note

This plan is parked in the backlog as work in progress. It was challenged and tightened as a possible first implementation unit, but it is not ready to execute until the workout feedback and watch product direction are incorporated.

## Unit Statement

Replace the current unversioned rendered-string WatchBridge vocabulary with a versioned, authority-aware phone-primary mirror protocol that carries session identity, cursor identity, spec revision, and authority epoch on every display and action message.

This unit does not make the Watch primary yet. It makes the current phone-primary behavior explicit, testable, and ready for the later watch-primary cache/event-replay unit.

## Boundaries Touched

- `WatchBridge`: wire vocabulary, Codable shape, fake transport behavior, stale-action validation helpers.
- `FeaturesWatchFaces`: current watch view model consumes the new display snapshot and emits only authority-scoped primary-action requests.
- `Shell`: composes the live bridge, sends display snapshots from the current `ExecutionViewModel`, and receives Watch actions in one app-level inbox.
- `WorkoutDBWatch`: stays a thin watch shell; no duplicate reducer or server sync logic moves to the watch.
- Docs: `docs/watch-metrics.md`, `docs/features/watch-primary-execution.md`, and this plan remain aligned after the code lands.

Out of scope for this unit:

- Starting a workout from the Watch.
- `Drive from Watch` handoff.
- Watch-side executable workout cache and durable event replay.
- HealthKit workout-session ownership, mirrored HealthKit sessions, GPS, pace, route, and directions.
- The three-view visual renderer. Existing faces may be adapted only enough to compile and prove the new protocol.
- Raising the deployment target for programmable double tap. The primary action may be modeled in protocol now, but watchOS 11-specific UI behavior is later.

## Dependencies And Preconditions

- The accepted architecture still applies: the app shows, times, and logs; server sync remains phone-owned.
- `docs/features/watch-primary-execution.md` is the feature spec. This plan implements its first protocol foundation, not the full feature.
- `docs/watch-metrics.md` defines the fixed watch grammar; this unit only creates the identity and authority substrate that grammar needs.
- Existing package boundaries matter: `Execution` currently has no `WatchBridge` dependency, and should not gain one in this unit. `Shell` is the composition point.
- Current `WatchBridge` messages are not sufficient: `pushActiveBlock` carries rendered strings, and Watch actions only carry `workoutItemID` plus set index. The watch view model currently fabricates a placeholder UUID for outbound actions.
- Apple platform constraints shape the proof: `WCSession.transferUserInfo` queues ordered background transfers but Apple says it must be tested on paired devices, not the Simulator; watchOS 11 is required to assign a custom primary double-tap action via `handGestureShortcut(.primaryAction)`.
- The user wants final proof for this implementation unit on the iOS Simulator. Real-device HealthKit/WatchConnectivity behavior remains a named escalation trigger for later watch-primary execution.

## Uncertainty Reduction Summary

Architecture/history:

- Code inspection: `app/Packages/WatchBridge/Sources/WatchBridge/WatchMessage.swift` documents a symmetric v1 vocabulary, but repo search shows no iOS-side sender or inbox currently consuming Watch messages from `Shell` or `Execution`.
- Code inspection: `app/Packages/Features/WatchFaces/Sources/FeaturesWatchFaces/WatchFacesViewModel.swift` explicitly says the Watch is not authoritative and uses a placeholder `UUID()` because the active payload lacks stable IDs.
- Code inspection: `app/Packages/Features/Execution/Package.swift` and `app/Packages/Shell/Package.swift` keep WatchBridge out of execution today; `Shell` is the correct composition layer if phone state needs to be projected to the Watch.

Blast radius:

- This unit should not change `CoreSession` reducer semantics. Authority validation is about accepting or rejecting Watch-originated commands before they become session mutations.
- This unit should not change server or SwiftData schema. Protocol identities can be derived from existing workout/session/cursor data and carried in WatchBridge DTOs.
- Current Watch UI tests already use `FakeWatchBridge`; that is the lowest-risk place to prove the new watch-side action behavior.

Contract and testing:

- Existing `WatchMessageCodingTests` and `FakeWatchBridgeTests` are the first proof seam. They need to move from v1 rendered messages to v2 identity-bearing messages.
- `ShellTests` are the right place to prove app-level inbox behavior because `Shell` owns composition across `Today`, `Execution`, `Sync`, and now `WatchBridge`.
- Final simulator QA should prove the iOS app still starts and runs a workout after adding the WatchBridge composition path. It should not claim WatchConnectivity background delivery works on Simulator.

External platform evidence:

- Apple documents `transferUserInfo(_:)` as queued, ordered, and continuing while the app is suspended, but also warns that the Simulator does not support this method.
- Apple documents `sendMessage` as immediate only when the counterpart is reachable.
- Apple documents `HKHealthStore.startWatchApp(with:)` and mirrored HealthKit workout sessions, but that behavior is deferred out of this unit.
- Apple documents custom double-tap primary action assignment as watchOS 11+ behavior; this unit must not depend on it because the project currently targets watchOS 10.

## Approach

Do a clean v2 protocol cutover inside the app code, not a compatibility layer. This is a single-user app; carrying v1 and v2 Watch messages together would create the exact stale-message ambiguity this unit is meant to remove.

1. Define a small authority identity model in `WatchBridge`:
   - `WatchProtocolVersion`
   - `WatchWireEnvelope`
   - `WatchSessionIdentity`
   - `WatchAuthority` (`phone`, `watch`)
   - `WatchAuthorityEpoch`
   - `WatchCursorIdentity`
   - `WatchSpecRevision`
   - `WatchActionID`
2. Replace rendered v1 messages with v2 messages:
   - `displaySnapshot`: phone to Watch, includes identity, authority snapshot, cursor, HR slot state, current work text, upcoming work text, and minimal display fields needed by the current faces.
   - `primaryAction`: Watch to phone, includes action ID, identity, authority epoch, cursor, spec revision, and created-at.
   - `actionAck`: phone to Watch, acknowledges accepted or rejected Watch actions by action ID with a reason.
   - Completion is represented as `displaySnapshot(route: complete, ...)`, not as a separate skinny completion message.
   - Reserve, but do not fully implement, `workoutPackage`, `authorityHandoff`, and `watchEventBatch` as later unit names in docs; do not ship dormant cases unless tests and callers need them in this unit.
3. Add pure validation in `WatchBridge`:
   - A Watch action is accepted only when session ID, authority epoch, active cursor ID, and spec revision match the live phone snapshot.
   - In this unit, phone-primary sessions reject mutating Watch actions with an explicit secondary-authority reason. The action can be acknowledged, but it must not advance or log.
   - Duplicate action IDs are idempotent at the inbox boundary.
4. Update `FeaturesWatchFaces`:
   - Consume `displaySnapshot`.
   - Preserve the current simple face behavior until the three-view renderer lands.
   - Emit `primaryAction` using the last received identity; never fabricate IDs.
   - If no valid identity has arrived, taps are no-ops.
5. Add a Watch-neutral execution projection seam:
   - `ExecutionViewModel` gets an optional post-mutation projection callback, or equivalent watch-neutral observer, that emits after every `apply(_:)`, `start()`, restore normalization, and completion route change.
   - The projection type must live in `FeaturesExecution` or another non-WatchBridge module and must not import `WatchBridge`.
   - Shell maps the projection to WatchBridge DTOs. No polling, SwiftUI view scraping, or direct WatchBridge import in `Execution`.
6. Add Shell composition:
   - Add `WatchBridge` as a `Shell` dependency.
   - Build a small `WatchMirrorController` or equivalent Shell-owned helper that can:
     - send a `displaySnapshot` whenever the projection's route, cursor identity, rest deadline, authority, spec revision, current text, upcoming text, or HR slot state changes;
     - read `bridge.messages()` in one inbox task;
     - validate `primaryAction` against the current snapshot;
     - send `actionAck` for accepted/rejected actions;
     - reject all mutating Watch actions while authority is phone.
   - `WatchMirrorController` lifetime is explicit: one Shell-owned instance per app root/bootstrap, one long-lived `bridge.messages()` subscription, current execution read through `ExecutionVMHolder`, duplicate-action cache scoped by `sessionID`, and cancellation on Shell/root teardown. A nil `ExecutionVMHolder.vm` means no live snapshot and all mutating actions are rejected as stale/no-session.
   - Keep mutation application out of scope; later watch-primary work will add the path that maps accepted Watch events to `ExecutionViewModel` intents.
7. Keep docs honest:
   - Update `docs/watch-metrics.md` only if field names or semantics change.
   - Update `docs/features/watch-primary-execution.md` with what this unit actually implements and what remains deferred.

## V2 Contract Details

The first implementation should make these fields concrete before writing callers. Field names can be adjusted during implementation only if the tests and docs move with them.

```swift
struct WatchSessionIdentity: Codable, Equatable, Sendable {
    let sessionID: UUID
    let workoutID: UUID
    let startedAt: Date
}

enum WatchAuthority: String, Codable, Sendable {
    case phone
    case watch
}

struct WatchAuthoritySnapshot: Codable, Equatable, Sendable {
    let authority: WatchAuthority
    let epoch: UInt64
    let handoffReason: WatchAuthorityHandoffReason
}

enum WatchAuthorityHandoffReason: String, Codable, Sendable {
    case initialPhoneStart
    case initialWatchStart
    case manualHandoff
    case restore
}

struct WatchSpecRevision: Codable, Equatable, Sendable {
    let value: String
}

struct WatchCursorIdentity: Codable, Equatable, Sendable {
    let blockID: UUID?
    let itemID: UUID?
    let blockIndex: Int
    let itemIndex: Int
    let setIndex: Int
    let route: String
    let phaseStartedAt: Date?
}

enum HeartRateSlotState: Codable, Equatable, Sendable {
    case live(bpm: Int, zone: String?)
    case pending
    case permissionMissing
    case sensorUnavailable
    case notImplemented
}
```

Every wire payload is wrapped in a versioned envelope:

```swift
struct WatchProtocolVersion: Codable, Equatable, Sendable {
    let major: UInt16
    let minor: UInt16
}

struct WatchWireEnvelope: Codable, Equatable, Sendable {
    let protocolVersion: WatchProtocolVersion
    let message: WatchMessage
}
```

This unit ships `WatchProtocolVersion(major: 2, minor: 0)`. Unknown major versions fail closed before message handling. Unknown minor versions are accepted only when the major version matches and the decoded message type is known. Codable tests must cover supported v2, unsupported major, and known-major/unknown-minor behavior.

Minimum shipped messages for this unit:

```swift
enum WatchMessage: Codable, Equatable, Sendable {
    case displaySnapshot(WatchDisplaySnapshot)
    case primaryAction(WatchPrimaryAction)
    case actionAck(WatchActionAck)
}
```

`displaySnapshot` is the atomic source for display state, completion state, and authority identity. Do not ship a separate `authoritySnapshot` or skinny `workoutComplete` in this unit unless there is a tested monotonic ordering and stale-check rule for ignoring older snapshots.

`actionAck` is keyed by `WatchActionID`. `eventAck` is reserved for the later durable `watchEventBatch` replay unit and should not be used for immediate taps.

## Identity And Decision Rules

- `sessionID` is a live execution UUID created when the workout starts. The owner is a small `LiveSessionIdentity` value associated with `ExecutionViewModel` persistence: initialize it when `start()` first creates live execution, persist it alongside the same active-session bytes currently handled through `SessionStateCodable` / `SessionPersistencePipeline`, restore it before Shell emits any watch snapshot, and clear it on `saveAndDone`. It is not the same thing as `workoutID`.
- `authority.epoch` starts at `1` for a phone-started session in this unit. It is persisted with the live session and increments only in later handoff work.
- `specRevision.value` is deterministic for the executable workout package. For this unit, derive it as a stable hash over the `WorkoutContext` fields used to seed and project execution: workout ID plus stable workout metadata, ordered block IDs/timing modes/positions/timing config, ordered item IDs/exercise IDs/positions/prescription JSON, and any authored watch/display timing config consumed by the projection. Do not use render time or mutable session progress. Tests must prove render time does not affect the value and that a package-shape/prescription change does.
- `WatchCursorIdentity` is deterministic for the current phase. It must change when route, block/item/set position, stable item/block identity, or phase start anchor changes.
- Action decision results are explicit:
  - `staleRejected`: identity, epoch, cursor, or spec revision does not match.
  - `duplicateIgnored`: action ID has already been acknowledged in this live session.
  - `secondaryAuthorityRejected`: identity matches, but the Watch is not primary for a mutating action.
  - `acceptedDisplayOnly`: safe display preference or mirror request, if this unit ships one.
  - `acceptedPrimaryMutation`: reserved for later watch-primary/handoff work.
- In this unit, `primaryAction` is classified as `mutatesExecution`, so phone-primary sessions must return `secondaryAuthorityRejected` and must not call any `ExecutionViewModel` mutation.
- `displaySnapshot` includes action availability. In this unit the Watch UI disables or hides the primary action when authority is `phone`. Shell still rejects and acknowledges malicious, stale, or duplicate `primaryAction` messages so the protocol is safe even if a message is injected or delivered late.

## Unit Acceptance Matrix

Implemented in this unit:

- V2 WatchBridge messages are identity-bearing and Codable-tested.
- The Watch view model no longer fabricates workout, session, cursor, or item IDs.
- Shell owns one watch inbox task and rejects phone-primary mutating Watch actions before they reach execution state.
- Display snapshots include an always-present HR slot state, even when HR is not implemented.
- Final proof includes iOS Simulator QA of the iOS execution loop with watch mirror code loaded.

Explicitly deferred:

- Watch-started workouts.
- `Drive from Watch`.
- Watch executable package persistence.
- Durable `watchEventBatch` / `eventAck` replay.
- HealthKit mirrored workout sessions and real WatchConnectivity paired-device proof.
- Three-view watch renderer, target windows, GPS pace, route, and directions.

## Execution Steps

1. Add the v2 identity, envelope, and message DTOs in `WatchBridge`, then update Codable tests so every shipped message round-trips, unsupported protocol majors fail closed, known-major/unknown-minor messages follow the documented rule, and unknown message tags fail.
2. Add `WatchAuthorityValidator` pure tests for matching snapshot, stale epoch, stale cursor, stale spec revision, duplicate action ID, and phone-primary secondary-action rejection.
3. Update `FakeWatchBridgeTests` for the v2 message set and ensure multicast behavior still holds.
4. Update `FeaturesWatchFaces` view model and tests so a `displaySnapshot` drives the face, no identity is fabricated, and phone-primary action availability disables/hides the primary action while injected actions remain rejectable by Shell.
5. Add the Watch-neutral execution projection seam and tests that it fires after start, active-to-rest, rest-to-active, complete, and restore. Add identity persistence tests proving `LiveSessionIdentity` survives restore and clears on `saveAndDone`.
6. Add Shell watch composition with dependency injection. Keep `ExecutionViewModel` free of `WatchBridge`.
7. Add Shell tests using `FakeWatchBridge` proving display snapshots are sent from real projections, exactly one inbox task is owned by Shell across VM swaps/nil VM/teardown, phone-primary Watch actions are acknowledged as rejected, duplicate action IDs are scoped by `sessionID`, and `ExecutionViewModel.state` is unchanged.
8. Update docs and this plan's completion evidence.
9. Run proof gates, then run independent Codex review/challenge on the resulting implementation before closeout.

## Completion Milestones

- [ ] V2 WatchBridge contract implemented.
- [ ] Watch-side view model migrated off placeholder UUIDs.
- [ ] Shell-level phone-primary mirror and inbox implemented.
- [ ] Protocol and validation proof complete.
- [ ] iOS Simulator QA complete.
- [ ] Independent Codex review complete.
- [ ] Review findings addressed.
- [ ] Docs and plan completion evidence updated.
- [ ] Final report ready.

## Proof Map

### Pure computation

- Check: `swift test` in `app/Packages/WatchBridge`.
- Boundary class and why: pure protocol encoding plus deterministic validation helpers.
- Proves: v2 envelopes/messages round-trip, unsupported protocol majors fail closed, unknown message tags fail, stale epoch/cursor/spec revision produce explicit rejection decisions, duplicate action IDs are idempotent, and immediate tap acks are distinct from future durable event acks.
- User/reviewer verification: command exits 0; expected signal is all `WatchBridgeTests` passing.
- Risk remaining: live WatchConnectivity delivery is not proven by SwiftPM tests.

### Cross-module boundary

- Check: `swift test` in `app/Packages/Features/WatchFaces`.
- Boundary class and why: WatchFaces consumes WatchBridge DTOs and emits WatchBridge actions.
- Proves: the Watch no longer fabricates IDs; taps without an identity are no-ops; phone-primary snapshots disable/hide the primary action; later watch-primary snapshots can produce an identity-bearing `primaryAction`.
- User/reviewer verification: command exits 0; expected signal is all `FeaturesWatchFacesTests` passing.
- Risk remaining: visual layout quality is deferred to the three-view renderer unit.

### Shell composition boundary

- Check: focused `ShellTests` using `FakeWatchBridge`.
- Boundary class and why: `Shell` coordinates `ExecutionViewModel`, app lifecycle, and WatchBridge.
- Proves: the phone sends current display snapshots from the watch-neutral execution projection, owns exactly one watch inbox across VM swaps/nil VM/teardown, acknowledges injected phone-primary Watch actions as rejected, scopes duplicate actions by `sessionID`, and does not mutate `ExecutionViewModel.state`.
- User/reviewer verification: `swift test` in `app/Packages/Shell` exits 0 and includes named watch mirror/inbox tests.
- Risk remaining: if existing Shell test fixtures make live state observation awkward, execution may need a small Shell-owned projection seam; adding that seam is allowed if it does not move WatchBridge into `Execution`.

### User-facing simulator QA

- Check: XcodeBuildMCP `build_run_sim`, then launch the iOS app with existing debug arguments for `--start-active --debug-mode=straight_sets`.
- Boundary class and why: user-facing app behavior across the iOS shell after adding WatchBridge composition.
- Proves: the iOS app still boots, starts a workout, advances through active/rest/complete, and does not regress the visible execution loop while the watch mirror code is present.
- User/reviewer verification: simulator app launches; debug workout reaches Active, logs one set into Rest, advances to the next Active state, then can be ended/completed without crash. Capture one screenshot or `snapshot_ui` at Active and Rest, plus note the executed taps.
- Risk remaining: paired-device WatchConnectivity and background `transferUserInfo` are not proven because Apple says Simulator does not support that method. Simulator QA proves the iOS app and Shell composition survive the execution loop, not live watch delivery.

### Static architecture check

- Check: `rg -n "import WatchConnectivity" app`, `rg -n "WatchBridge" app/Packages/Features/Execution app/Packages/Core`, and focused `Package.swift` dependency inspection.
- Boundary class and why: architectural boundary, because only WatchBridge may import WatchConnectivity.
- Proves: WatchConnectivity remains isolated to `WatchBridge`, and `Execution` / `Core` do not depend on WatchBridge or watch-specific DTOs.
- User/reviewer verification: WatchConnectivity matches only `app/Packages/WatchBridge/Sources/WatchBridge/LiveWatchBridge.swift` and comments/docs; WatchBridge has zero matches in `Features/Execution` and `Core` outside explicitly allowed test comments.
- Risk remaining: no Swift package import-linter exists for app-side package dependencies yet; review must check `Package.swift` diffs.

## Independent Review

- Artifact: the code diff plus this plan after implementation.
- Reviewer: Codex via `cxd task --sandbox read-only`, using the repo's non-trivial review loop.
- Review focus:
  - v2 protocol has no stale-action gap.
  - no v1/v2 dual-path ambiguity remains.
  - `Execution` did not gain a WatchBridge dependency.
  - Shell inbox cannot mutate a phone-primary session from Watch action.
  - tests prove intended behavior rather than the old placeholder-ID behavior.
  - simulator QA exercised the Shell/watch composition path, not just generic app launch.
- Reopen condition: any real issue in stale action rejection, duplicate action idempotency, package boundary, or simulator-critical regression forces another implementation pass and review.

## Closeout

- `docs/watch-metrics.md`: still accurately describes authority identity and stale action handling.
- `docs/features/watch-primary-execution.md`: mark this protocol foundation as implemented and keep watch-primary cache/event replay explicitly planned.
- `app/README.md`: update Watch scope if the protocol behavior visible to users changes.
- `docs/ARCHITECTURE.md`: update the WatchBridge/Shell relationship if Shell now owns a watch inbox.
- This plan: add completion evidence with commands run, results, simulator QA notes, review thread ID, and remaining risks.
- Final report to user: name the implemented unit, proof results, simulator QA result, independent review result, and the next implementation unit.

## Recovery Context

Unit statement: Replace unversioned rendered-string WatchBridge messages with a versioned, authority-aware phone-primary mirror protocol carrying session, cursor, spec revision, and authority epoch.

Implementation owner: main agent or implementation worker briefed from this plan.

Review owner: Codex read-only reviewer via the repo's implementer/reviewer cycle.

Next thing to resume if blocked: if code has not started, begin with WatchBridge DTOs and Codable tests. If WatchBridge is complete, move to WatchFaces view-model tests. If WatchFaces is complete, wire Shell composition and simulator QA.

Proof still expected: WatchBridge tests, WatchFaces tests, Shell tests, architecture grep, iOS simulator QA, independent Codex review.

Closeout still expected: update watch docs, architecture docs if Shell wiring changes, completion evidence in this plan, final proof summary.

## Residual Uncertainty / Accepted Risks

- Live paired-device delivery:
  - Why accepted: this unit's final proof target is iOS Simulator QA, and Apple states `transferUserInfo` is not supported by Simulator.
  - Signal that risk has landed: real-device watch actions are delayed, duplicated, or lost despite passing local tests. That becomes the first risk to prove in the watch-primary cache/event-replay unit.
- HealthKit workout ownership:
  - Why accepted: this unit does not start mirrored HealthKit workouts or capture Watch HR into logs.
  - Signal that risk has landed: later watch-primary execution cannot keep HR/workout session state alive while disconnected.
- Visual watch redesign:
  - Why accepted: the three fixed views depend on the protocol identity model but are a separate UI unit.
  - Signal that risk has landed: the v2 display snapshot cannot express persistent HR/current/upcoming slots without another protocol change.
- Current dirty worktree:
  - Why accepted: the repo is already heavily modified by ongoing execution work. This unit must work with that state and avoid reverting unrelated changes.
  - Signal that risk has landed: implementation touches files already changed by another lane and cannot isolate its diff safely.

## Escalation Triggers

- Implementing Shell watch composition requires `Execution` to import `WatchBridge`.
- V2 protocol needs server or SwiftData schema changes to represent identity fields.
- The plan requires supporting old and new Watch message variants at the same time.
- `sessionID`, `specRevision`, or cursor identity cannot be derived deterministically without adding a persistence/schema surface.
- Shell cannot observe route/cursor changes without a Watch-neutral projection seam in or near `ExecutionViewModel`.
- More than one watch inbox task can run for a single app session.
- Simulator QA fails in an existing execution flow after WatchBridge composition is added.
- Codex review finds a stale-action or duplicate-action path that can still mutate phone-primary execution.
- Real-device platform behavior becomes necessary to finish this unit rather than a later watch-primary unit.
