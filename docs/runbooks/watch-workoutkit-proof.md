---
title: Watch WorkoutKit proof runbook
status: accepted
purpose: Proof matrix and setup notes for the WorkoutKit handoff spike.
covers:
  - docs/features/watch-workoutkit-handoff.md
  - docs/TESTING.md
  - docs/QA.md
  - app/project.yml
---

# Watch WorkoutKit proof runbook

This runbook defines what can and cannot be proven before WorkoutKit handoff
work becomes user-facing.

## Proof tiers

| Tier | Proves | Does not prove |
| --- | --- | --- |
| Package tests | Export-profile classification, degradation records, support-state rollups, fake support-probe behavior. | Apple Workout app visibility, scheduling, Watch startability, permissions. |
| iPhone simulator | iOS-side UI affordance and failure states once a fake/probe is injectable. | Paired Watch behavior or Apple Workout app execution. |
| Paired Watch simulator | Watch target build/install/screenshot smoke and iOS-to-Watch `WatchConnectivity` content push through the app's custom watch bridge. | Real Workout app startability, WorkoutKit schedule behavior, permissions, on-device sensor behavior. |
| Real iPhone + real Watch | Open/schedule visibility, startability, permissions, and duplicate/update scheduling behavior. | Broad regression coverage without repeatable fixtures. |

## Current local state

On 2026-05-18, the first probe found XcodeBuildMCP configured for the iOS
`WorkoutDB` scheme and only iOS 18.6 simulator runtimes. `xcrun simctl list
devicetypes` listed Apple Watch device types and `xcodebuild -showsdks` listed
`watchos11.5` and `watchsimulator11.5`, but no watchOS simulator runtime was
registered.

The watchOS runtime was then installed with:

```bash
xcodebuild -downloadPlatform watchOS
```

After installation, `xcrun simctl runtime list` reported:

- iOS 18.6 (`22G86`)
- watchOS 11.5 (`22T572`)

The installed toolchain is Xcode 16.4 (`16F6`). Available SDKs include iOS
18.5, iOS Simulator 18.5, watchOS 11.5, and watchOS Simulator 11.5.

At proof time, a local paired iPhone/Apple Watch simulator existed and
`xcrun simctl list pairs` reported it as active/connected when both devices
were booted. Do not copy simulator UUIDs into durable docs; discover the active
pair on the machine running the proof:

```bash
xcrun simctl list pairs
xcrun simctl list devices
```

Build the Watch target against the active Watch destination:

```bash
xcodebuild -project app/WorkoutDB.xcodeproj -scheme WorkoutDBWatch \
  -destination "platform=watchOS Simulator,name=<active watch name>" build
```

`xcrun simctl install` and `xcrun simctl launch` now work for
`com.ericfeunekes.WorkoutDB.watchkitapp` on the Watch simulator. The install
initially failed because `app/WorkoutDBWatch/Info.plist` did not declare
`WKCompanionAppBundleIdentifier`; the fix is part of the repo setup and must be
kept in sync with `app/project.yml`.

`xcodegen` was installed through the existing `/usr/local/bin/brew`, and
`make xcodegen` now succeeds. Regeneration produced no checked-in Xcode project
diff for the Watch plist change because the target uses the static
`app/WorkoutDBWatch/Info.plist` file.

Record fresh screenshots under the active `scratch/qa-runs/<run-id>/` when
rerunning this proof. Scratch paths are not durable evidence and should not be
referenced from shipped requirements.

The iOS simulator can push custom WatchBridge content to the paired Watch
simulator. Launch the active phone simulator with:

```bash
xcrun simctl launch <active-phone-device-id> \
  com.ericfeunekes.WorkoutDB --debug-watch-push
```

With `WorkoutDBWatch` foregrounded, the Watch simulator rendered the pushed
synthetic active-block payload:

- set: `2 / 5`
- exercise: `Bench Press`
- prescription: `5 reps @ 102 lb`
- target RIR: `2`

Record fresh screenshot evidence for each proof run instead of relying on a
previous scratch path.

Two repo setup fixes were required for this proof:

- `WorkoutDBWatch` declares `WKCompanionAppBundleIdentifier` in
  `app/WorkoutDBWatch/Info.plist` and `app/project.yml`.
- The iOS `WorkoutDB` target depends on `WorkoutDBWatch`, so the generated
  build embeds `WorkoutDBWatch.app` under `WorkoutDB.app/Watch/`.

The DEBUG proof sender must keep its temporary `LiveWatchBridge` alive briefly
after `send(_:)`; otherwise WatchConnectivity can report
`WCSession is missing its delegate` before delivery completes. Production watch
UI already keeps its bridge alive for the app/view-model lifetime.

The initial compile probe used a scratch file importing `WorkoutKit` and
referencing `WorkoutScheduler.shared`. With an explicit module cache outside
the default sandboxed cache, that probe typechecked for:

- `arm64-apple-ios17.0`
- `arm64-apple-ios18.0`
- `arm64_32-apple-watchos10.0`
- `arm64_32-apple-watchos11.0`

This proves only basic compile availability for the installed SDK and those
deployment floors. It does not prove Workout app visibility, scheduling
behavior, permissions, or Watch startability.

Local SDK interface inspection and Apple documentation agree on the core
WorkoutKit shape:

- `WorkoutPlan.Workout` supports `.goal(SingleGoalWorkout)`,
  `.custom(CustomWorkout)`, `.pacer(PacerWorkout)`, and
  `.swimBikeRun(SwimBikeRunWorkout)`.
- `WorkoutScheduler.shared`, `isSupported`, `scheduledWorkouts`,
  `schedule(_:at:)`, `remove(_:at:)`, `markComplete(_:at:)`, and
  `removeAllWorkouts()` are available from iOS 17 / watchOS 10 in the local
  SDK interface.
- `WorkoutScheduler.maxAllowedScheduledWorkoutCount` is available in the local
  SDK interface. WWDC23 described scheduled workouts as locally synced, visible
  for the next seven days and previous seven days, and capped at 15 workouts at
  a time. Use the SDK value at runtime for capacity decisions.
- `WorkoutPlan.openInWorkoutApp()` is watchOS-only in the local SDK interface
  and unavailable to iOS. Treat direct open as a watch-side proof question, not
  a phone-side implementation assumption.
- Core `WorkoutGoal` cases (`open`, `distance`, `time`, `energy`) are
  available from iOS 17 / watchOS 10. `poolSwimDistanceWithTime` requires iOS
  18 / watchOS 11.
- `WorkoutStep` custom `displayName` support requires iOS 18 / watchOS 11 in
  the local SDK interface; the basic goal/alert step initializer is available
  from iOS 17 / watchOS 10.

Paired-Watch simulator proof is now available for direct Watch app
build/install/launch smoke testing on this machine. It is not proof of Apple's
Workout app behavior.

On 2026-05-18, a push-semantics spike added two compile probes:

- `scratch/workoutkit-push-semantics-probe.swift` typechecked against
  iOS 18.5 / target `arm64-apple-ios18.0` and proves the local SDK accepts
  constructing a stable-ID cycling `WorkoutPlan` plus calls to
  `authorizationState`, `requestAuthorization`, `scheduledWorkouts`,
  `schedule(_:at:)`, `remove(_:at:)`, `markComplete(_:at:)`, and
  `removeAllWorkouts()`.
- `scratch/workoutkit-watch-open-probe.swift` typechecked against watchOS 11.5
  / target `arm64_32-apple-watchos11.0` and proves
  `WorkoutPlan.openInWorkoutApp()` is available to the Watch target.

The booted Watch simulator did not list Apple's Workout app among installed
apps when inspected with `xcrun simctl listapps`, so simulator evidence cannot
prove actual Workout app visibility, startability, duplicate handling, or
schedule update behavior. Those remain real paired-watch questions.

On 2026-05-18, the real-device WorkoutKit open/schedule spike was implemented
up to the physical-device boundary:

- Probe sources live under
  `scratch/watch-workoutkit-handoff/spikes/real-device-workoutkit-open-schedule/probe/`.
- The iOS schedule probe typechecks against iPhoneOS 18.5 for
  `arm64-apple-ios18.0`.
- The watchOS open probe typechecks against watchOS 11.5 for
  `arm64_32-apple-watchos11.0`.
- `xcrun devicectl list devices` reported `No devices found`.
- `xcrun xctrace list devices` reported only the Mac as a real device; all
  iPhone/Watch entries were simulators.

The real-device portion of `WATCHKIT-GAP-004` therefore remains blocked on a
connected and trusted iPhone paired to a real Apple Watch. Once hardware is
visible to Xcode, run the retained probe to answer schedule visibility,
startability, same-ID duplicate behavior, changed-payload update behavior, and
same-ID multi-date behavior.

## Spike probes

Phase 1 must record:

- installed Xcode version and SDKs: **recorded above for Xcode 16.4**
- whether `import WorkoutKit` compiles under current project deployment targets:
  **basic compile probe recorded above**
- whether WorkoutKit APIs needed by the handoff require iOS 18 or watchOS 11:
  **partially recorded above; display names and pool swim time goals need
  higher OS floors**
- whether capabilities/entitlements are needed for open and schedule
- whether XcodeBuildMCP can drive any watchOS simulator workflow in this repo:
  **partially proven; XcodeBuildMCP lists the installed watchOS 11.5
  simulators, while shell `xcodebuild` and `simctl` currently provide the
  proven build/install/launch path**
- whether iOS simulator can push app-owned watch content to the paired Watch:
  **proven for custom WatchBridge active-block content; screenshot recorded
  above**
- which push claims remain blocked on real-device proof

## Evidence rules

- A mapping can be `native` or `degraded` while proof state is still
  `unproven`.
- User-facing export cannot be exposed until the selected row and delivery path
  have the required evidence.
- Push proof makes no Setmark result claim. Completion/readback/reconciliation
  belongs to a separate future results lane.
- Duplicate/update behavior must be proven against real WorkoutKit scheduler
  state. Until then, the adapter should be planned around an explicit
  remove-then-schedule algorithm, not silent replace semantics.

## Planning disposition

Phase 1 spike disposition:

- Proceed to implementation planning for a pure vendor-neutral export profile
  and fake-backed WorkoutKit adapter classifier.
- Do not create a production user-facing `WorkoutKitBridge` export flow until
  real-device scheduling/startability and duplicate/update behavior proof
  exists.
- Local watch simulation infrastructure is now ready for Watch app
  build/install/launch smoke proof and iOS-to-Watch custom-content push proof.
- Simulator proof can cover adapter UI affordances and fake support-probe
  behavior; it cannot prove Apple's Workout app visibility/startability or
  WorkoutKit scheduler duplicate/update behavior.

## References

- Apple Developer Documentation:
  [WorkoutKit](https://developer.apple.com/documentation/WorkoutKit)
- Apple Developer Documentation:
  [WorkoutPlan](https://developer.apple.com/documentation/workoutkit/workoutplan)
- Apple Developer Documentation:
  [CustomWorkout](https://developer.apple.com/documentation/workoutkit/customworkout)
