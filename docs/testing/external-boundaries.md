---
title: External Boundary Testing
status: accepted
last_reviewed: 2026-05-18
purpose: Proof patterns for Apple APIs, WatchConnectivity, real HTTP, Cloudflare Access, and capability gaps.
covers:
  - docs/TESTING.md
  - docs/QA.md
  - docs/healthkit-data-access.md
  - docs/features/watch-workoutkit-handoff.md
---

# External Boundary Testing

Use this when a change crosses an API or runtime boundary the repo does not
fully control: HealthKit, WorkoutKit, WatchConnectivity, Cloudflare Access,
real HTTP sync, simulator entitlements, or physical device behavior.

## Boundary Rule

Do not let external APIs own core behavior. Put app logic behind adapters and
prove the app logic with deterministic fakes. Then add the narrowest simulator,
local-service, or real-device proof needed for the external contract being
claimed.

If the boundary cannot be proven locally, name the capability gap and the
manual or real-device proof required. Do not replace a boundary proof with a
mock and call it realistic-local.

## Apple Health Proof Ladder

HealthKit and WorkoutKit proof is intentionally layered. There is no single
"HealthKit simulator" gate that proves archive export, live Watch metrics,
Workout app handoff, and real sensor behavior at once.

### Tier 1: deterministic fixture/replay streams

Use scripted normalized metric events for app and watch metric consumers. This
is the main development harness for zone display, pace smoothing, stale or
missing heart-rate behavior, pause/resume, interval transitions, summary math,
and UI state.

### Tier 2: iOS simulator HealthKit contract proof

Use synthetic HealthKit samples and app-hosted tests to verify permission
request construction, supported type mapping, write/read round trips, anchored
batch fetches, deleted objects, cursor persistence, and local archive
projection.

`make test-healthkit-ui` is the current focused target. It first fails fast if
Xcode's generated simulator entitlements lack `com.apple.developer.healthkit`,
then runs the app-hosted authorization/archive projection proof.

This target proves the signed debug probe can request HealthKit authorization,
write/fetch synthetic samples, write and read the probe's injected archive
projection store, and handle anchored deletions/cursors in the current
simulator state. The probe runs against the default on-disk store when
`WORKOUTDB_HEALTHKIT_PROBE_DEFAULT_STORE=1` and reopens a fresh store handle to
prove records, tombstones, and cursor state survive outside the original
process object. It is not deterministic fresh authorization-sheet UX proof
unless the run also resets HealthKit permissions and observes the sheet.

### Tier 3: watchOS simulator live-workout contract proof

Use the watchOS simulator for `HKWorkoutSession`/`HKLiveWorkoutBuilder`
lifecycle, simulated live metrics, builder save, Always On/reduced-luminance UI
behavior where applicable, and app metric-stream wiring.

This tier does not prove real optical heart-rate delivery or Watch/iPhone sync
reliability. The current debug entry point is the watch launch argument
`--healthkit-live-workout-probe`, which prints
`HEALTHKIT_LIVE_WORKOUT_PROBE_JSON_BEGIN/END` around the structured probe
result.

`make test-healthkit-watch-sim` asserts the latest XcodeBuildMCP watch app log
for the live-workout probe sentinels and required result fields. XcodeBuildMCP
remains the launch/log-capture owner; Health permissions are not resettable
through `simctl privacy`, so first-run authorization remains a runtime boundary.

Captured probe logs are asserted with
`make assert-healthkit-watch-sim-log PROBE_LOG=/path/to/runtime.log`. This
proves the structured output once XcodeBuildMCP has launched the watch app and
captured the runtime log; it does not by itself build, install, or launch the
watch simulator.

Fresh watch simulators still require the Health permission sheet to be granted
before the live-workout probe can reach metric collection. A healthy run emits
`sessionStarted`, `collectionStarted`, `collectionEnded`, `workoutSaved`, and at
least one heart-rate tick. If a previously used simulator hangs before
collection, rerun on a fresh watch simulator before treating the app code as the
failed boundary.

Use XcodeBuildMCP or Xcode's build/run path for this proof. Raw `simctl
install` is not equivalent: it launched far enough to request HealthKit
authorization, but produced a watch app without the HealthKit authorization
state needed for the proof, and manually re-signing the bundle made the
simulator launcher reject the app.

### Tier 4: physical iPhone + Apple Watch smoke proof

Required for claims about sensors, permissions on real devices, backgrounding,
lock/display sleep, Fitness/Workout presentation, real WorkoutKit
visibility/startability, and Watch/iPhone sync.

### Tier 5: real-world regression traces

After real workouts, export app-level session events and replay them through
Tier 1 fixture streams so future changes can exercise real missing-sample,
pause/resume, and metric-shape behavior without requiring a workout for every
code change.

## WorkoutKit Push Boundary

WorkoutKit handoff is a planning/export boundary. It should stay separate from
HealthKit readback and result reconciliation unless a requirement explicitly
combines them.

Tests should prove:

- vendor-neutral primitive facts map into supported WorkoutKit structures
- unsupported facts degrade with explicit notes instead of guessed semantics
- target limits and scheduling constraints are surfaced before export
- duplicate push/idempotency posture is defined by the adapter contract
- no HealthKit completion readback is required for a push-only claim

Real Apple Workout app visibility, startability, scheduling UX, and sync
behavior require simulator or physical-device proof depending on the claim.

## Real HTTP And Identity Boundaries

For server/app sync, prefer local FastAPI + temporary SQLite + real URLSession
over mocked transports when the claim crosses the HTTP boundary.

For Cloudflare Access or other identity/capability boundaries, keep pure auth
parsing and request-building testable locally, then add a live or recorded proof
only for the external capability. If live proof is not practical, document the
gap and the exact manual smoke test.

## QA Boundary

QA can prove that a device or external app shows the expected user-facing
result. QA cannot prove adapter correctness unless paired with readback,
structured probe output, logs, or persisted state from the boundary owner.
