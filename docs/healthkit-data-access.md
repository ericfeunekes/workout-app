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

Scheduling and upload are outside the data module. App launch, debug export,
post-workout completion, manual Settings export, daily background export, and
foreground catch-up are all consumers that supply request-set keys, request
sets, date windows, and cursors. The module returns records and delete
information; it does not decide when archive jobs run or where exported
records are uploaded.

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

## Personal Archive Export

The full personal archive export is a first-class product lane. Its target is
Eric's home server, not an arbitrary third-party destination. The app should
let Eric choose either all currently supported HealthKit descriptors or an
explicit subset, request the required permissions for that selection through
`HealthKitBridge`, fetch the selected data through the batch/archive primitive,
persist the local projection, and upload normalized records plus tombstones to
the home server.

"All" means all descriptors supported by the app registry at that build. It
does not mean every Apple HealthKit type exists in the registry, is available
on the current device, or has a generic serializer. Unsupported or unavailable
types must be visible as unsupported/unavailable, not silently treated as a
successful empty export.

The export configuration is app-local state:

- selected descriptor set: all supported, or explicit descriptor IDs.
- current-server delivery namespace, derived from the saved server identity.
- request-set key and fingerprint for cursor ownership, scoped to the selected
  descriptor set and current-server delivery namespace.
- permission request status and last observed failure class.
- last successful local fetch time and upload time.
- last server-acknowledged HealthKit cursor per request-set key.
- last export summary: inserted/updated count, tombstone count, upload outcome,
  and redacted error class if any.

The server is the durable landing zone for exported health records.
`POST /api/health/archive` stores normalized records, tombstones, and
request-set summaries in SQLite. Its API/schema preserves the same identity,
descriptor, unit, source, start/end, value, metadata, cursor, and tombstone
semantics as the local projection. Server storage must not become a writer back
into HealthKit; HealthKit remains the source of truth.

Local HealthKit projection data is connection-agnostic and survives server
changes. Delivery state is not connection-agnostic. A new server identity must
use a fresh delivery namespace and therefore a fresh cursor/backfill for that
server. Returning to a previously used server may reuse that server's namespace
if still present locally, but Settings must show status for the current server
only.

Cursor advancement is tied to server acknowledgement. The app may persist
fetched records and tombstones locally before upload, but the cursor used for
the next export run must advance only after the corresponding upload succeeds.
If upload fails after fetch succeeds, the next run re-fetches from the last
server-acknowledged cursor and relies on local/server idempotency to tolerate
duplicate records. No implementation may advance the export cursor merely
because local fetch/projection succeeded.

## Archive Scheduling And Delivery

Daily export is app-initiated. The intended behavior is opportunistic rather
than exact-wall-clock: the app schedules a background-capable daily archive job
where iOS allows it, runs the same export primitive when woken, and always
runs a foreground catch-up on app open if the daily export is due or a prior
run failed. A manual Settings export uses the same request set and cursor path.

The schedule must be transparent to the user. Settings should show whether
automatic export is enabled, what descriptor scope is selected, when the app
expects to try next, when the last successful local fetch/upload completed, and
the last failure class. The UI must not promise exact daily timing because iOS
background execution is not exact or guaranteed.

Silent push/APNs is not required for this archive lane. APNs server-nudged
workout delivery is tracked separately in `docs/sync.md` as `SYNC-GAP-004`.
HealthKit background delivery may later be used as an optimization for specific
sample descriptors, but the daily archive contract must still work through
scheduled/background opportunities and foreground catch-up.

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
- No arbitrary third-party health export target. The home server is the
  accepted target for the personal archive lane once its endpoint/schema are
  selected.
- No app-side analysis of HealthKit samples beyond normalized export/readback.
- No promise that every HealthKit type is supported on day one.
- No exact-wall-clock background guarantee; scheduled exports are
  opportunistic and foreground catch-up remains required.

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

`HKDATA-AC-011`: Settings can configure a personal archive export for all
supported HealthKit descriptors or an explicit supported subset, and permission
requests are derived from that selected descriptor set. Merge-gate proof:
Settings feature tests for selection state and HealthKitBridge permission-set
tests for the same request set.

`HKDATA-AC-012`: A manual archive export fetches selected descriptors, persists
the local projection, and uploads normalized records and tombstones to the home
server without screens importing HealthKit. Merge-gate proof: package tests for
the orchestration path against fake HealthKit providers and fake server
transport, server tests for idempotent health-record/tombstone ingestion and
request-set validation, and `make test-sync-real-http` proof that Swift
`SyncAPI` can upload archive records through FastAPI into SQLite.

`HKDATA-AC-013`: A daily archive schedule is opportunistic and catch-up based,
not exact-wall-clock. If the scheduled background run is skipped, throttled, or
offline, the next app-open foreground pass uses the same cursor and upload path.
Merge-gate proof: scheduler/orchestrator tests with controlled clocks and fake
background triggers, plus app-hosted lifecycle proof when the app wiring lands.

`HKDATA-AC-014`: Export status is user-visible and diagnostic enough to answer
what happened without inspecting the database: selected scope, last fetch,
last upload, next intended attempt, counts, and redacted failure class.
Merge-gate proof: Settings feature tests and telemetry/export-summary tests.

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
- The personal archive export now supports all-supported and explicit-subset
  request sets. The server exposes `POST /api/health/archive`, stores uploaded
  normalized records, tombstones, and request-set summaries in SQLite, and
  updates `schema/openapi.json` plus `WorkoutDBSchema` DTOs. `Sync` owns the
  upload client and maps its public archive-upload types to wire DTOs internally;
  `Persistence` owns the canonical current-server namespace normalization used
  by archive export state and Settings; `HealthArchiveExport` owns the shared
  manual/foreground coordinator, requests permissions through `HealthKitBridge`,
  fetches from the last server-acknowledged cursor for the selected request set,
  persists the local projection, uploads through `Sync`, and advances the local
  delivery cursor only after server acknowledgement. Settings now has descriptor
  scope, manual export, automatic-export toggle, next-attempt status, and
  current-server status controls. The real HTTP probe uploads quantity,
  category, and workout archive records plus a tombstone through `SyncAPI` and
  verifies SQLite persistence. BGTask registration and richer status
  presentation are still later loops.
- The DEBUG simulator probe route requests HealthKit authorization, runs the
  archive fetch, persists the projection, and exposes structured proof fields
  for authorization request completion, request-set fingerprints, fetch
  success, this-run sample correlation, first/second cursor presence, second
  fetch cursor input, deleted-sample correlation, projection persistence,
  tombstone readback, default-store selection, and reopen-from-disk readback.
  The proof route is gated by the signed-app entitlement preflight in
  `make test-healthkit-ui`; on the current Xcode simulator path, the HealthKit
  entitlement is embedded in `WorkoutDB.app-Simulated.xcent`. On 2026-05-18,
  the target passed the entitlement preflight and archive UI proof on an
  iPhone 16 Pro simulator; the proof now fails unless the probe uses the
  default on-disk store and a newly opened store can read back the records,
  tombstones, and cursor.
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
- The phone app wires `WatchBridge` into the active execution view model during
  shell bootstrap. Watch `.setStarted`, `.setEnded`, and `.quickLog` messages
  now apply to the current execution session, preserve the real
  `workoutItemID`, update primitive set logs with watch heart-rate fields, and
  enqueue the resulting push payloads. This is local app-consumption proof, not
  proof of inactive/background WatchConnectivity delivery.
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
  `make test-healthkit-watch-sim` finds the latest XcodeBuildMCP watch app log
  and applies the same assertions. XcodeBuildMCP still owns the watch
  build/install/launch path; `simctl privacy` does not expose Health as a
  grantable service, so first-run permission UI remains an Apple-runtime
  boundary rather than a pure CLI reset.

## Current Gaps

- `HKDATA-GAP-005`: The watchOS simulator diagnostic now proves HealthKit
  authorization, `HKWorkoutSession`/`HKLiveWorkoutBuilder` lifecycle, simulated
  metric delivery, and builder save through XcodeBuildMCP. The watch face now
  consumes the typed metric-source contract for HR display and outbound set-end
  payloads, and the phone-side execution session consumes those watch messages
  into local logs/push payloads. Remaining live-work scope is real-device
  sensor/sync behavior and richer metric coverage beyond HR fields.
- `HKDATA-GAP-003`: Real Watch-backed live metric delivery is unproven until a
  physical iPhone + Apple Watch diagnostic run succeeds.
- `HKDATA-GAP-006`: Personal archive export to the home server has
  all-supported and explicit-subset source-to-server paths, including server
  ingestion/schema, upload transport, local export state, Settings
  trigger/status controls, foreground catch-up through the shared runtime, and
  split proof for local projection and server-side SQLite ingestion. Remaining
  work is BGTask registration, richer user-visible schedule/status copy, a real
  HTTP app-client to server readback harness, and proof that BGTask-triggered
  exports share the same typed descriptor, cursor, tombstone, and upload path.
