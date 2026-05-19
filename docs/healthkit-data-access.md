---
title: HealthKit data access
status: active
last_reviewed: 2026-05-18
purpose: Requirements contract for making HealthKit data available to Setmark consumers through one typed batch/live module.
covers:
  - app/Packages/HealthKitBridge/
  - app/Packages/Persistence/
  - app/WorkoutDB/
  - app/WorkoutDBWatch/
  - docs/watch-metrics.md
  - docs/TESTING.md
---

# HealthKit Data Access

Setmark needs one HealthKit data module that can serve full personal archive
export, post-workout readback, and live workout metrics without each consumer
knowing HealthKit's type identifiers, units, permission sets, or query APIs.
Consumers declare the data they want. `HealthKitBridge` owns the translation
into HealthKit and returns normalized records with explicit units and external
identity.

The full personal archive lane is intentional. It is not only a workout-screen
helper. The module must be able to grow toward broad HealthKit export while
still giving workout screens narrow request sets for post-workout and live
execution use.

HealthKit and WorkoutKit have separate jobs:

- HealthKit owns health data access: authorization, completed workouts,
  metrics, samples, anchored batch export, post-workout readback, and live
  workout metric collection.
- WorkoutKit owns planned workout handoff into Apple's Workout app: preview,
  open, export, and scheduling of workout plans. Scheduled WorkoutKit records
  are not health metrics; any completed-workout metrics still come back through
  HealthKit.

This module reads and normalizes external health data; it does not perform
workout programming, progression, readiness analysis, or exercise selection.
Claude and the server remain the workout authoring and analysis authorities.

## Ownership And State

HealthKit is the source of truth for Apple health samples. Setmark may store a
local projection for export, deduplication, post-workout readback, and personal
system sync, but the projection is not the authority for the underlying sample.

Projected records must preserve:

- Setmark projection ID.
- HealthKit external sample identity when available.
- Health data type descriptor.
- source bundle or source name when available.
- start and end dates.
- typed value with unit or payload.
- metadata that can be represented safely.
- sync cursor or batch cursor state per stable exported request-set key.
- deleted external IDs or tombstones from anchored queries.

Scheduling is outside the data module. App launch, debug export, post-workout
completion, manual Settings export, and future background scheduling are all
consumers that supply request-set keys, request sets, date windows, and cursors. The module
returns records and delete information; it does not decide when archive jobs
run.

## Consumer Contract

Consumers request data through typed descriptors:

```text
type id
sample kind: quantity | category | workout | characteristic | correlation | clinical
default unit when applicable
access: read | write | readWrite
delivery: batch | live
```

Descriptors are the stable boundary. Consumers must not import HealthKit,
construct `HKObjectType`s, or hand-roll unit conversion. `WorkoutKitAdapter` is
the one narrow exception for `HKWorkoutActivityType` and
`HKWorkoutSessionLocationType` values required while constructing WorkoutKit
plans; that exception does not include HealthKit queries, stores, samples,
authorization, or readback. Adding a new HealthKit type should extend the
registry and mapping layer, not the consumer API.

Returned values must carry explicit units or typed payloads at the value
boundary. A consumer must never infer that `123` means bpm, kg, steps, kcal, or
seconds from display context.

## Permissions

Permissions are derived from the union of active consumer requests. The module
maps descriptors into HealthKit read/share sets and owns
`requestAuthorization`. Consumers may ask for data, but they do not own
permission prompts or permission math.

Request legality is shared across live, batch, fake, and HealthKit-backed
providers:

| Access | Batch fetch | Live stream | Authorization request |
|---|---|---|---|
| `read` | allowed | allowed | read permission |
| `readWrite` | allowed | allowed | read + share permission |
| `write` | rejected for fetch | rejected for stream | share permission for batch/write consumers |

This matrix is an app contract, not test-double behavior. Fakes must enforce
the same request validation as live providers unless a test explicitly installs
a lower-level spy for mapper-only assertions.

HealthKit deliberately does not expose reliable read authorization status for
privacy. A successful authorization call means the request flow completed, not
that every future query will return data. The module must keep failures typed:

- HealthKit unavailable.
- Not authorized or not yet authorized.
- Type unsupported by the provider/platform.
- Query failed with redacted diagnostic context.
- Provider path not implemented yet.

## Batch And Archive

Batch reads use a request set, an optional date window, and an optional opaque
cursor. Batch results include inserted/updated normalized records, deleted
external IDs, and the next cursor.

Consumers own stable request-set keys for named export/readback scopes, such as
`archive-all` or a post-workout readback scope. A consumer must change the key
when the meaning of the request set changes incompatibly. The stored cursor is
one opaque value per request-set key; the cursor itself may contain per-type
HealthKit anchors.

Full export and incremental refresh share this primitive. A first run can ask
for a broad window and no cursor. Later runs pass the cursor returned from the
previous batch. Post-workout readback can use a narrower date window and a
smaller request set.

Date windows are type-aware. Point samples use strict start-date semantics.
Interval-shaped samples such as sleep and workouts use overlap semantics, so a
sample that starts before the window but ends inside it is still returned.

"All HealthKit data" is the direction, not a promise that the first
implementation supports every HealthKit type. The first implementation may ship
a finite registry, but unsupported types must fail explicitly and the registry
must be extension-friendly.

## Live Workout Metrics

Live reads use the same descriptors only for types that can stream credibly.
The consumer-facing contract is an app-level metric stream, not direct
`HKWorkoutSession`, `HKLiveWorkoutBuilder`, or `HKLiveWorkoutBuilderDelegate`
usage in screens. Feature code should be testable against deterministic fixture
or replay streams before Apple runtime proof exists.

The live proof ladder is:

1. Deterministic fixture/replay streams for app behavior: zone display, pace
   smoothing, stale or missing heart-rate handling, pause/resume, summaries,
   interval transitions, and UI state.
2. watchOS simulator contract proof for `HKWorkoutSession` and
   `HKLiveWorkoutBuilder` lifecycle, simulated live metrics, builder save, and
   live-metric UI update wiring.
3. Real iPhone + Apple Watch proof for sensor delivery, permission behavior,
   backgrounding, lock/display sleep, Activity/Fitness presentation, and
   Watch/iPhone sync behavior.

The module may expose HealthKit live data through `HealthLiveDataProvider`, but
custom Watch or phone screens consume typed normalized records and replayable
metric events. They do not own HealthKit session setup or permission prompts.
Real Apple Watch-backed live metrics require a physical iPhone paired to a
physical Watch, both visible to Xcode with Developer Mode enabled.

The first physical-device proof should be a tiny diagnostic, not the full app
experience: start a HealthKit workout session, collect a few seconds of live
metric evidence, log the received sample types and values, then stop. No
user-facing live Watch behavior may claim verification before that diagnostic
succeeds.

## Simulator Proof Boundary

A simulator spike on 2026-05-18 proved that the iOS simulator has enough
HealthKit surface area for the batch/archive mechanics that matter before
device work:

- `HKHealthStore.isHealthDataAvailable()` returned true.
- The Health authorization sheet can be presented and driven by an app-hosted
  UI test. The accepted proof path checks Xcode's generated simulator
  entitlements, then proves `HKHealthStore.requestAuthorization` completes
  before fetching records.
- Synthetic quantity samples round-tripped for heart rate, body mass, step
  count, and active energy.
- Synthetic sleep category and workout samples round-tripped.
- Anchored queries reported inserted samples and deleted objects.
- The app-hosted archive proof uses one stable request-set key, writes
  representative synthetic records for the supported registry, fetches a first
  batch, deletes one fetched sample, fetches again with the first cursor, and
  emits structured JSON proving request fingerprints, this-run correlation,
  cursor use, typed deleted IDs, local projection persistence, and persisted
  tombstone readback.

Therefore, simulator proof remains the intended proof layer for descriptor
mapping, permission request construction, synthetic write/read harnesses,
anchored batch behavior, delete handling, and the app route that wires a fetched
batch into the local archive store. `make test-healthkit-ui` first verifies
`WorkoutDB.app-Simulated.xcent` carries `com.apple.developer.healthkit`, then
runs the archive proof. Persistence tests prove the archive projection contract
against in-memory stores and migration fixture stores; they do not claim to
open the real `Application Support/default.store` path used by `makeDefault()`.

Simulator proof is split by platform. iOS simulator HealthKit proof covers
synthetic samples, app-hosted authorization flow, descriptor mapping, anchored
batch export, and local projection. watchOS simulator proof may cover live
workout session/builder lifecycle and simulated metric delivery. Neither
simulator layer is accepted for real Apple Watch optical sensor behavior,
wrist/lock/display conditions, battery pressure, Activity/Fitness presentation,
or Watch/iPhone sync reliability.

## Non-Goals For The First Implementation Phase

- No real Watch live metric claim.
- No custom Watch-primary execution behavior.
- No cloud or remote personal-system sync target.
- No app-side analysis of HealthKit samples beyond normalized export/readback.
- No promise that every HealthKit type is supported on day one.
- No scheduling engine; consumers trigger batch reads.

## Acceptance Criteria

`HKDATA-AC-001`: A consumer can declare a batch request for supported HealthKit
data without importing HealthKit or naming an `HKObjectType`. Merge-gate proof:
`HealthKitBridge` package tests for descriptor/request construction and
mapping behavior per `docs/TESTING.md` Swift package tests.

`HKDATA-AC-002`: A consumer can declare a live request with the same descriptor
shape as a batch request. Merge-gate proof: `HealthKitBridge` fake live
provider tests show scripted records preserve request type and unit.

`HKDATA-AC-003`: Returned records include explicit unit or typed payload,
external identity, source, start/end dates, and metadata. Merge-gate proof:
package tests for normalized records plus persistence tests when the local
projection lands.

`HKDATA-AC-004`: Permission prompts are derived from consumer request sets and
owned inside `HealthKitBridge`. Merge-gate proof: package tests for request-set
to permission-set mapping. App-hosted simulator proof must first pass the
simulator entitlement preflight in `make test-healthkit-ui`, then show that
`requestAuthorization` completed and that fetch succeeds afterward. A
deterministic fresh-sheet claim requires a separate permission-reset capability
test.

`HKDATA-AC-005`: Batch fetch supports first-run full export and incremental
refresh through the same request/window/cursor primitive. Merge-gate proof:
simulator-backed HealthKit probe or app-hosted test proving inserted records,
this-run sample correlation, deleted IDs, and next cursor behavior for
representative sample types.

`HKDATA-AC-006`: Local archive projection stores normalized records, deletion
tombstones, and cursor state without becoming the HealthKit authority.
Merge-gate proof: SwiftData persistence tests with duplicate upsert, cursor
update by request-set key, tombstone persistence, tombstone-applied
`loadRecords`, and archive clear cases.

`HKDATA-AC-007`: Unsupported types and unimplemented provider paths fail
explicitly instead of returning empty success. Merge-gate proof:
HealthKitBridge package tests for unsupported/not-implemented errors.

`HKDATA-AC-008`: Real Watch-backed live metrics remain blocked until a
physical iPhone + Apple Watch diagnostic run proves live sensor delivery.
Proof: real-device run per `docs/TESTING.md` and `docs/QA.md`; this is not part
of the first implementation phase.

`HKDATA-AC-009`: Live metric consumers can be driven by deterministic fixture
or replay streams without importing HealthKit or requiring a simulator/device.
Merge-gate proof: package tests for the consuming feature or watch metric
surface cover missing samples, stale values, pause/resume, and summary math
through scripted normalized metric events.

`HKDATA-AC-010`: Planned workout handoff and completed-workout readback remain
separate extension points. WorkoutKit scheduling/opening must not claim HealthKit
metric ingestion, and HealthKit result import must not be required to push a
planned workout. Merge-gate proof: architecture tests keep WorkoutKit side
effects in `WorkoutKitAdapter` and HealthKit data access in `HealthKitBridge`.

## Current Capability

- `HealthKitBridge` maps the first supported batch registry into HealthKit
  object/sample types, units, read/share permissions, and anchored queries.
- Batch results carry normalized records, typed deleted records, and opaque
  next-cursor state.
- `Persistence` stores a SwiftData-backed local HealthKit archive projection
  for normalized records, deleted external IDs, and one cursor per stable
  request-set key. It persists deletion tombstones and applies them to
  `loadRecords`; `loadDeletions` remains the evidence surface for
  reconciliation/export.
- The DEBUG simulator probe route requests HealthKit authorization, runs the
  archive fetch, persists the projection, and exposes structured proof fields
  for authorization request completion, request-set fingerprints, fetch
  success, this-run sample correlation, first/second cursor presence, second
  fetch cursor input, deleted-sample correlation, projection persistence, and
  tombstone readback. The proof route is gated by the signed-app entitlement
  preflight in `make test-healthkit-ui`; on the current Xcode simulator path,
  the HealthKit entitlement is embedded in `WorkoutDB.app-Simulated.xcent`.
  On 2026-05-18, the target passed the entitlement preflight and archive UI
  proof on an iPhone 16 Pro simulator.
- Fake live providers and scripted heart-rate observers exist for package-level
  live-consumer proof. They are deterministic app harnesses, not evidence of
  Apple Watch sensor delivery.
- `HealthKitBridge` now exposes a stable `WorkoutMetricReplay` /
  `WorkoutMetricSource` contract for deterministic app-level metric event
  replay, including a readable JSON trace format and summary projection.
- `HealthKitBridge` includes a watchOS `HealthKitWorkoutMetricSource`
  implementation of `WorkoutMetricSource`. The watch face starts that source
  when an active block arrives, renders the latest heart rate, and includes the
  latest heart rate in the outbound `.setEnded` message. Package tests prove
  the consumer behavior with deterministic fixture streams; physical sensor
  delivery remains a real-device gap.
- A DEBUG watch launch path, `--healthkit-live-workout-probe`, runs a
  `HealthKitBridge` diagnostic that requests HealthKit permission, starts
  `HKWorkoutSession`/`HKLiveWorkoutBuilder`, collects simulated live metric
  ticks where available, ends collection, saves the workout, and prints
  structured JSON. The bridge compiles against the watchOS simulator SDK and
  the watch target carries the required HealthKit purpose strings. On
  2026-05-18, the XcodeBuildMCP watch simulator run path presented the
  HealthKit authorization UI, accepted read/write permission, collected five
  simulated live ticks including heart rate and active energy, and saved an
  8.55 second workout. Raw `simctl install` is not accepted as the proof path:
  it produced a watch app without HealthKit authorization and manual ad-hoc
  re-signing was rejected by the watch simulator launcher.
- `make assert-healthkit-watch-sim-log PROBE_LOG=...` parses a captured
  XcodeBuildMCP watch runtime log and asserts the live-workout probe JSON.
  The parser is repeatable, but the current post-wiring watch launch path still
  needs a reliable trigger that emits the sentinels on demand.

## Current Gaps

- `HKDATA-GAP-005`: The watchOS simulator diagnostic now proves HealthKit
  authorization, `HKWorkoutSession`/`HKLiveWorkoutBuilder` lifecycle, simulated
  metric delivery, and builder save through XcodeBuildMCP. The watch face now
  consumes the typed metric-source contract for HR display and outbound set-end
  payloads. Remaining live-work scope is reliable merge-gated watch probe
  triggering plus phone-side execution handling of watch HR payloads.
- `HKDATA-GAP-003`: Real Watch-backed live metric delivery is unproven until a
  physical iPhone + Apple Watch diagnostic run succeeds.
