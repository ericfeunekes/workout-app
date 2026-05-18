---
title: Watch WorkoutKit handoff
status: planned
last_reviewed: 2026-05-17
purpose: Early Apple Watch delivery path that maps Setmark workouts into Apple's Workout app through WorkoutKit before building a full custom watch-primary execution surface.
covers:
  - docs/features/watch-primary-execution.md
  - docs/watch-metrics.md
  - docs/sync.md
  - app/Packages/Features/Today/
  - app/Packages/Features/Execution/
  - app/WorkoutDBWatch/
---

# Watch WorkoutKit Handoff

## Target behavior

Eric can send selected Setmark workouts to Apple Watch without first building
the full custom watch-primary app. The phone maps each eligible Setmark workout
to the closest Apple WorkoutKit representation, opens it now or schedules it in
Apple's Workout app, and later reconciles only the completion/result signal
that can be proven back into Setmark history.

This is an early-delivery bridge, not the final watch execution model. It uses
Apple's Workout app for the actual watch-side workout experience and keeps
Setmark as the authoring, planning, history, and analysis surface.

## Platform grounding

Apple's WorkoutKit supports creating, previewing, opening, exporting, and
scheduling workout plans for the Workout app on Apple Watch. It supports common
WorkoutKit workout shapes such as single-goal, pacer, custom interval, and
multi-sport workouts. Custom workout steps carry a limited goal/alert shape, so
this bridge starts narrow: enough for selected cardio or simple interval cases,
not enough to represent every Setmark timing mode or every strength-log field
losslessly.

HealthKit can launch or wake the companion watch app with an
`HKWorkoutConfiguration`, but that path starts a HealthKit workout session for
our app. That belongs to the later custom watch-primary track, not the
WorkoutKit handoff bridge.

## Mapping contract

The bridge must be explicit about what survives the mapping:

- WorkoutKit mapping consumes Setmark primitives through an adapter profile; it
  must not add WorkoutKit-specific fields to primitive workout, block, set,
  slot, or log records. The same primitive inspection shape should be reusable
  by future export targets such as Strava or other health/training systems.
- **Eligible workouts** map to a known WorkoutKit workout type and activity
  type. Each mapped workout carries a stable Setmark workout identifier in the
  phone-side tracking record so completion can reconcile back.
- **Unsupported workouts** stay in Setmark only and show a clear reason, not a
  fake or lossy export. Examples likely include complex strength blocks,
  clusters, supersets, and anything whose value depends on per-set load/reps/RIR
  logging.
- **Support status is profile-specific.** A primitive composition can be
  native, degraded, Setmark-only, or unsupported depending on the export
  target. Degraded mappings are allowed only when the user-facing loss is named
  before export. For example, a run with target pace may map cleanly while
  Setmark-specific notes remain phone-only.
- **Completion reconciliation** is app-owned imported-result behavior. It may
  mark the Setmark workout completed or attach coarse HealthKit/WorkoutKit
  facts only when identity matching is unambiguous. It must not invent set-level
  logs that Apple did not produce.

The mapping table is a durable artifact of this feature. It should name each
Setmark timing/workout archetype, the Apple workout type it maps to, what data
is preserved, what data is lost, and whether the bridge is allowed to export it.

Initial allowlist:

| Setmark shape | Initial export stance | Reason |
| --- | --- | --- |
| Continuous cardio with time or distance goal | Allow after real-device proof | Maps closest to a single-goal workout. |
| Pace-target run or ride | Allow after real-device proof | Maps closest to pacer or alert-backed workout shapes. |
| Simple time/distance interval cardio | Allow after real-device proof | Maps closest to custom interval steps when the per-step goal/alert limits are acceptable. |
| Multi-sport swim/bike/run | Spike before allow | WorkoutKit has a multi-sport shape, but Setmark identity and completion mapping still need proof. |
| Strength, supersets, clusters, circuits with load/reps/RIR, mixed manual stations | Block by default | Apple's Workout app does not produce Setmark per-set load/reps/RIR logs, and lossy completion would misrepresent the workout. |

Completion proof must answer these cases before implementation planning:

| Export path | Required evidence | Allowed Setmark result |
| --- | --- | --- |
| Open now in Workout app | Prove whether Setmark can recover a stable identity, start/end time, and matching HealthKit workout sample. | Unknown until spike; no automatic completion without proof. |
| Scheduled WorkoutKit plan | Prove scheduled date, composition identity, completion flag, and HealthKit sample matching behavior. | Completed status and coarse imported facts only when unambiguous. |
| HealthKit query after completion | Prove which sample metadata, activity type, dates, and statistics are available to this app. | Attach observed facts; never invent missing Setmark fields. |

## Non-goals

- No custom Setmark watch UI.
- No watch-primary Setmark event log.
- No direct Watch-to-server sync.
- No Setmark-owned live Watch haptics, double-tap actions, HR slot, metric
  layout, route UI, or event replay. Apple's Workout app owns the live Watch
  experience in this lane.
- No fake per-set strength history from Apple Workout completions.
- No attempt to force every Setmark workout through WorkoutKit.
- No replacement of the existing phone execution loop.

## Acceptance criteria

1. **Mapping table exists and blocks unsafe exports.** A future reader can tell
   which Setmark workout shapes can be handed to WorkoutKit and why. Unsupported
   shapes fail visibly before export.
2. **A supported workout reaches Apple Watch.** The phone can open or schedule a
   supported workout in Apple's Workout app, and real-device proof shows it is
   visible/startable on the paired Watch.
3. **Completion reconciles without fabricated detail.** After the Apple workout
   completes, Setmark can mark the corresponding workout complete or attach a
   coarse imported result only when the identity match is unambiguous. It never
   creates per-set logs from unavailable data.
4. **Setmark remains the source of truth for plans.** Claude-authored Setmark
   workouts still originate in the server/app model. WorkoutKit receives a
   mapped copy; it does not become the planning authority.
5. **Fallback is clear.** A workout that cannot map safely remains executable in
   the Setmark phone app.

## Current gaps

- `WATCHKIT-GAP-001`: Initial allowlist exists; the final per-archetype mapping
  table still needs to be built and proven through a WorkoutKit adapter profile.
- `WATCHKIT-GAP-002`: No app package currently wraps WorkoutKit, and real-device
  WorkoutKit scheduling/opening has not been proven.
- `WATCHKIT-GAP-003`: Completion reconciliation path is unsettled. HealthKit
  query, WorkoutKit scheduled-plan completion state, or explicit user
  confirmation may each be viable depending on platform behavior.

## Relationship to custom watch-primary

This feature comes before `watch-primary-execution.md`. If it satisfies the
early delivery need, the full custom Watch app can stay deferred until Setmark
needs watch-side set logging, custom metric slots, offline event replay, route
ownership, or interaction patterns Apple's Workout app cannot express.
