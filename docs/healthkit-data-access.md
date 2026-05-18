---
title: HealthKit data access
status: planned
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
- sync cursor or batch cursor state per exported request set.
- deleted external IDs or tombstones from anchored queries.

Scheduling is outside the data module. App launch, debug export, post-workout
completion, manual Settings export, and future background scheduling are all
consumers that supply request sets, date windows, and cursors. The module
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
construct `HKObjectType`s, or hand-roll unit conversion. Adding a new HealthKit
type should extend the registry and mapping layer, not the consumer API.

Returned values must carry explicit units or typed payloads at the value
boundary. A consumer must never infer that `123` means bpm, kg, steps, kcal, or
seconds from display context.

## Permissions

Permissions are derived from the union of active consumer requests. The module
maps descriptors into HealthKit read/share sets and owns
`requestAuthorization`. Consumers may ask for data, but they do not own
permission prompts or permission math.

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

Full export and incremental refresh share this primitive. A first run can ask
for a broad window and no cursor. Later runs pass the cursor returned from the
previous batch. Post-workout readback can use a narrower date window and a
smaller request set.

"All HealthKit data" is the direction, not a promise that the first
implementation supports every HealthKit type. The first implementation may ship
a finite registry, but unsupported types must fail explicitly and the registry
must be extension-friendly.

## Live Workout Metrics

Live reads use the same descriptors only for types that can stream credibly.
Tests and simulator flows may use fixture or synthetic streams. Real Apple
Watch-backed live metrics require a physical iPhone paired to a physical Watch,
both visible to Xcode with Developer Mode enabled.

The first physical-device proof should be a tiny diagnostic, not the full app
experience: start a HealthKit workout session, collect a few seconds of live
metric evidence, log the received sample types and values, then stop. No
user-facing live Watch behavior may claim verification before that diagnostic
succeeds.

## Simulator Proof Boundary

A simulator spike on 2026-05-18 proved that the iOS simulator can support the
batch/archive mechanics that matter before device work:

- `HKHealthStore.isHealthDataAvailable()` returned true.
- Health authorization sheet can be driven by an app-hosted UI test.
- Synthetic quantity samples round-tripped for heart rate, body mass, step
  count, and active energy.
- Synthetic sleep category and workout samples round-tripped.
- Anchored queries reported inserted samples and deleted objects.

Therefore, simulator proof is acceptable for descriptor mapping, permission
request construction, synthetic write/read harnesses, anchored batch behavior,
delete handling, and local archive projection. Simulator proof is not accepted
for real Apple Watch sensor delivery.

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
to permission-set mapping. App-hosted simulator proof drives Apple's Health
authorization sheet.

`HKDATA-AC-005`: Batch fetch supports first-run full export and incremental
refresh through the same request/window/cursor primitive. Merge-gate proof:
simulator-backed HealthKit probe or app-hosted test proving inserted records,
deleted IDs, and next cursor behavior for representative sample types.

`HKDATA-AC-006`: Local archive projection stores normalized records and cursor
state without becoming the HealthKit authority. Merge-gate proof: SwiftData
persistence tests with duplicate upsert, cursor update, and tombstone/delete
cases.

`HKDATA-AC-007`: Unsupported types and unimplemented provider paths fail
explicitly instead of returning empty success. Merge-gate proof:
HealthKitBridge package tests for unsupported/not-implemented errors.

`HKDATA-AC-008`: Real Watch-backed live metrics remain blocked until a
physical iPhone + Apple Watch diagnostic run proves live sensor delivery.
Proof: real-device run per `docs/TESTING.md` and `docs/QA.md`; this is not part
of the first implementation phase.

## Current Gaps

- `HKDATA-GAP-001`: General HealthKit descriptor-to-query mapping is not
  implemented beyond the typed contract and fake-backed test surface.
- `HKDATA-GAP-002`: No local app database projection exists for normalized
  HealthKit archive records, external identities, deleted IDs, or cursors.
- `HKDATA-GAP-003`: Real Watch-backed live metric delivery is unproven until a
  physical iPhone + Apple Watch diagnostic run succeeds.
