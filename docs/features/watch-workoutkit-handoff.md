---
title: Watch WorkoutKit handoff
status: planned
last_reviewed: 2026-05-18
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
to the closest Apple WorkoutKit representation, schedules it or hands it to the
appropriate platform-side Workout app flow.

This is an early-delivery bridge, not the final watch execution model. It uses
Apple's Workout app for the actual watch-side workout experience and keeps
Setmark as the authoring, planning, history, and analysis surface.

Completion/result reconciliation is a separate future module. This handoff
feature must not depend on HealthKit readback, WorkoutKit completion matching,
or imported-result semantics.

## Platform grounding

Apple's WorkoutKit supports creating, previewing, opening, exporting, and
scheduling workout plans for the Workout app on Apple Watch. This repo's
current adapter only models scheduling from iPhone and opening from watchOS;
preview/save UI is a future path and is not emitted by the production
coordinator. WorkoutKit supports common
WorkoutKit workout shapes such as single-goal, pacer, custom interval, and
multi-sport workouts. Local Xcode 16.4 SDK inspection shows scheduling APIs are
available to iOS, while `WorkoutPlan.openInWorkoutApp()` is watchOS-only in the
SDK interface. Treat phone-side scheduling and watch-side opening as separate
platform paths until real-device proof says otherwise. Custom workout steps
carry a limited goal/alert shape, so this bridge must separate
**exportability** from **Setmark fidelity**. A workout may still be useful to
send to Apple's Workout app when WorkoutKit cannot carry every Setmark
primitive fact, as long as the app records what was simplified or omitted and
never treats the Apple result as a full Setmark execution log.

Scheduling is bounded. Apple's WWDC23 guidance says scheduled workouts are
locally synced into a dedicated app section in the Workout app, visible for the
next seven days and previous seven days, with up to 15 workouts synced at a
time. The local SDK exposes `WorkoutScheduler.maxAllowedScheduledWorkoutCount`;
the adapter must use the live SDK value rather than hard-coding capacity.

HealthKit can launch or wake the companion watch app with an
`HKWorkoutConfiguration`, but that path starts a HealthKit workout session for
our app. That belongs to the later custom watch-primary track, not the
WorkoutKit handoff bridge.

## Mapping contract

The bridge must be explicit about what survives the mapping:

- WorkoutKit mapping consumes Setmark primitives through a vendor-neutral export
  profile first, then a WorkoutKit adapter profile. It must not add
  WorkoutKit-specific fields to primitive workout, block, set, slot, or log
  records. The same primitive inspection shape should be reusable by future
  export targets such as Strava or other health/training systems.
- **Outbound mapping and result ingestion are separate extension points.**
  The export profile answers "what can this Setmark workout become for target
  X?" Target adapters then translate that profile into WorkoutKit, Strava, or
  another application. Result ingestion is a separate later lane; do not make a
  target adapter both the source of export truth and the owner of
  imported-result semantics.
- **Eligible workouts** map to a known WorkoutKit workout type and activity
  type. Each mapped workout has a stable push identity so repeated pushes,
  schedule updates, and user-visible degradation disclosure can be handled
  deterministically.
- **Unsupported workouts** stay in Setmark only and show a clear reason.
  Unsupported means WorkoutKit cannot represent the workout safely enough to be
  useful, not merely that Setmark facts such as load, reps, RIR, alternatives,
  notes, or per-slot results would be omitted.
- **Support status is profile-specific.** A primitive composition can be
  native, degraded, Setmark-only, or unsupported depending on the export
  target. Degraded mappings are valid only when the user-facing loss is named
  before export and available to the future export tracking record. For example, a
  strength circuit may map as a functional-strength or custom interval workout
  while Setmark-specific load/reps/RIR and per-set logging remain phone-only.
- **Representational fit is separate from proof state.** A composition can have
  a plausible native or degraded WorkoutKit representation while still being
  blocked from user-facing export until SDK availability, simulator behavior,
  real-device visibility/startability, and duplicate/update scheduling behavior
  are proven.
- **Setmark-only is not failure.** A valid Setmark workout can intentionally
  remain Setmark-only for a specific export target. `unsupported` is reserved
  for a target/profile that cannot produce a safe or useful representation.
- **Degradation includes push semantics, not only fields.** Every degraded
  mapping names the Apple-visible goal/result and which authored Setmark
  planning semantics are omitted or collapsed in the pushed plan.
- **Completion reconciliation is not part of this feature.** A future
  target-specific ingestion engine may decide whether any target completion data
  comes back into Setmark, but this WorkoutKit handoff does not own that.
- **Bridge ownership stays split.** WorkoutKit plan construction, opening, and
  scheduling belong to a WorkoutKit adapter boundary. Results/readback belongs
  to a separate module if later promoted.

### Neutral source facts

Some export choices cannot be inferred from primitive structure. A distance
target might be a run, row, ride, loaded carry, or station inside a mixed
workout. The durable workout contract therefore carries a small
vendor-neutral `activity_intent` object at the primitive workout root. This is
source truth about what the workout is trying to preserve, not an instruction
to any one export adapter.

V1 source facts:

| Field | Values | Required for Setmark execution? | Export meaning |
| --- | --- | --- | --- |
| `activity_domain` | `running`, `cycling`, `rowing`, `swimming`, `walking`, `hiking`, `functional_strength`, `traditional_strength`, `hiit`, `mobility`, `mixed_modal`, `carry`, `other` | No | Broad authored activity family. Missing means source-dependent export rows return `needsSourceChoice`; the classifier must not guess from distance, duration, load, or reps alone. |
| `environment` | `indoor`, `outdoor`, `unspecified` | No | Where the workout is intended to happen when that changes the target mapping. Missing defaults to `unspecified`; resolved descriptors preserve `indoor` and `outdoor` and translate `unspecified` to unknown location. Target adapters may block when a concrete location is required. |
| `preservation_policy` | `preserve_primary_activity`, `preserve_structure`, `preserve_elapsed_time`, `preserve_distance`, `preserve_mixed_modality` | No | What truth should survive when a mixed workout cannot preserve everything in the target. Missing is allowed for single-domain workouts but produces `needsSourceChoice` for Hyrox/run-station and other mixed-domain rows where the choice changes meaning. |

The object itself may be omitted. Omission never makes a workout invalid in
Setmark. It only prevents the export profile from pretending to know which
external representation is honest. Future targets may reuse these same facts;
new target-specific fields still belong outside primitive workout, block, set,
slot, and log records.

Ownership and wire semantics:

- Claude-authored workout pushes are the normal author of `activity_intent`.
  Server create/update APIs validate and persist it. Sync, Persistence, Today,
  Shell, WorkoutKitAdapter, and HealthKitBridge are not allowed to invent,
  normalize by heuristic, or mutate the facts.
- Manual/app-created workouts may omit `activity_intent`; that omission means
  source-dependent export rows must ask for source choice instead of guessing.
- On the API and sync wire, `activity_intent` is a sibling of
  `primitive_blocks` on the primitive workout root. It is not nested in a block,
  set, slot, log, or adapter-specific object.
- Omitted `activity_intent` and explicit `null` both mean “no source facts.”
  Read and sync responses materialize that as `activity_intent: null`;
  classifiers treat it as absent.
- If `activity_intent` is present, `activity_domain` is required,
  `environment` defaults to `unspecified` and is materialized on readback, and
  `preservation_policy` may be omitted only when the source activity choice does
  not change the export meaning. Mixed-domain rows that need the policy return
  `needsSourceChoice`.
- Target adapters may read the neutral facts only after `ExportProfile` has
  classified them. Candidate-family choice, degradation meaning,
  Apple-visible result, source-choice state, and misleading-block decisions
  belong to `ExportProfile`.

Hyrox-style workouts use the same neutral facts. If the workout is "running
with hard stations," `activity_domain=running` plus
`preservation_policy=preserve_primary_activity` can admit a lossy running-first
export that discloses station loss. If the workout is a mixed event where
station structure matters most, `activity_domain=mixed_modal` plus
`preservation_policy=preserve_structure` should prefer a broad custom/mixed
representation. Without that explicit policy, the WorkoutKit classifier must
return `needsSourceChoice`; if the requested preservation policy would make the
Apple-visible result misleading, it must block as `misleading` rather than
silently push.

Minimum Hyrox/run-station V1 matrix:

| Activity intent | Expected classification |
| --- | --- |
| No `activity_intent`, or `activity_domain=mixed_modal` with missing `preservation_policy` | `needsSourceChoice`; no target guess. |
| `activity_domain=running`, `preservation_policy=preserve_primary_activity` | Lossy running-first candidate; station work is disclosed as Setmark-only. |
| `activity_domain=mixed_modal`, `preservation_policy=preserve_structure` | Lossy mixed/custom candidate; run distance may be collapsed or disclosed depending on target fit. |
| `activity_domain=running`, `preservation_policy=preserve_structure` for a station-heavy mixed workout | `misleading`; the requested policy conflicts with the visible running-first result. |

The mapping table is a durable artifact of this feature. It names each Setmark
shape, primitive axes, Apple workout candidate, preserved facts,
omitted/collapsed facts, Apple-visible result, push identity requirements, and
path-specific proof state. It is not an export authorization table; future app
coordinators decide whether to expose a row after this pure plan reports its
unmet prerequisites.

Implemented pure planner row IDs in `app/Packages/ExportProfile`:

| Row ID | Source shape | WorkoutKit candidate family | Support state | Base proof requirements | Extra path proof |
| --- | --- | --- | --- | --- | --- |
| `paceTargetRun` | Exactly one block, one set, one slot; slot has distance completion target plus duration observation target; `activity_intent.activity_domain=running` | `pacer` | native | SDK compile, simulator construction | Schedule visibility + duplicate/update for scheduled pushes |
| `continuousCardio` | Distance/time target with no load | `singleGoal` | native | SDK compile, simulator construction | Schedule visibility + duplicate/update for scheduled pushes; startability for open-on-Watch |
| `simpleIntervals` | Time-bounded work/rest intervals | `customWorkout` | native | SDK compile, simulator construction | Schedule visibility + duplicate/update for scheduled pushes; startability for open-on-Watch |
| `straightStrength` | Reps/load/RIR set-based strength | `singleGoal` | degraded | SDK compile, simulator construction, degradation acknowledgement | Schedule visibility + duplicate/update for scheduled pushes; startability for open-on-Watch |
| `roundRobinStrength` | Multi-slot round-robin strength | `customWorkout` | degraded | SDK compile, simulator construction, degradation acknowledgement | Schedule visibility + duplicate/update for scheduled pushes; startability for open-on-Watch |
| `cappedForTime` | Time cap plus Setmark-owned result | `customWorkout` | degraded | SDK compile, simulator construction, degradation acknowledgement | Schedule visibility + duplicate/update for scheduled pushes; startability for open-on-Watch |
| `loadedCarry` | Distance/duration with load | `singleGoal` | degraded | SDK compile, simulator construction, degradation acknowledgement | Schedule visibility + duplicate/update for scheduled pushes; startability for open-on-Watch |
| `mobilityRecovery` | Time-bounded recovery sequence | `singleGoal` | degraded | SDK compile, simulator construction, activity support, degradation acknowledgement | Schedule visibility + duplicate/update for scheduled pushes; startability for open-on-Watch |
| `setmarkOnlyRest` | Standalone timer-only rest | none | Setmark-only | none | none |
| `ambiguousAmrap` | AMRAP result overlay not represented safely enough by current primitives | unresolved | unsupported | SDK compile only | blocked by source ambiguity |
| `unsupported` | No safe WorkoutKit representation | none | unsupported | SDK compile only | blocked by target capability |

Phase 1 mapping matrix:

| Setmark archetype | Primitive axes / dominant metric | WorkoutKit candidate | Support state | Preserved for Apple | Omitted or collapsed | Apple-visible result | Setmark result claim | Planner state |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Continuous cardio | One concrete time or distance target; sequential traversal; source activity fact required | `SingleGoalWorkout` | Native when `activity_intent` is present and the resolved descriptor preserves the single target; otherwise `needsSourceChoice` or descriptor-incomplete | Authored activity family, concrete time/distance goal, and authored indoor/outdoor location when present | Setmark block/set hierarchy; unspecified location remains unknown | Workout completed with elapsed time, distance/energy when available | No Setmark result claim from push | Block until source activity fact, exact descriptor mapping, and real-device schedule/start proof |
| Pace-target run | One scheduled running slot with distance completion and duration observation | `PacerWorkout` | Native for `paceTargetRun` | Running activity, authored scheduled date, distance, target time, derived Apple pacing model | Setmark hierarchy, multi-slot or multi-pace structure | Workout completed against Apple pacing model | No Setmark result claim from push | Hidden unless delivery proof source permits exposure; public/TestFlight enablement still waits on real-device proof |
| Pace-target ride | Distance plus target time/pace; cycling domain | `PacerWorkout` where supported | Future candidate; not emitted by current classifier/adapter | None yet | Pacer payload construction and source activity | Workout completed against Apple pacing model | No Setmark result claim from push | Block until target mapper and real-device proof |
| Simple cardio intervals | Time-bounded work/rest steps; sequential traversal; source activity fact required | `CustomWorkout` with interval blocks/steps | Native or degraded when `activity_intent` is present and the resolved descriptor preserves the authored work/rest metric; otherwise `needsSourceChoice` or descriptor-incomplete | Authored activity family, step order, concrete work/rest cadence, and repeat count | Step names on lower OS floors; detailed Setmark hierarchy | Interval workout completion | No Setmark result claim from push | Block until source activity fact, exact descriptor mapping, and real-device proof |
| Segmented continuous workout | Sequential blocks in one modality; time/distance segments | `CustomWorkout` | Degraded | Segment order and broad goals | Rich segment intent, result roles below Apple step level | Custom workout completion | No Setmark result claim from push | Block until adapter proof |
| Straight strength / set based | Repeated sets/slots; strength domain; reps/load are Setmark-owned | `SingleGoalWorkout` or `CustomWorkout` with functional-strength activity and open/time goals | Degraded | Activity category, broad duration or open workout | Load, reps, RIR, alternatives, per-slot/set results | Strength workout duration/energy/HR only | No Setmark result claim from push | Requires degradation acknowledgement plus real-device path proof |
| Density strength | Time-bounded strength block; work density is Setmark-owned | `CustomWorkout` time block or open functional-strength workout | Degraded | Time cap/duration and activity category | Round count, reps/load density semantics | Timed strength workout completion | No Setmark result claim from push; density score remains Setmark-only | Requires degradation acknowledgement plus proof |
| Superset | Round-robin or sequential multi-slot strength set | `CustomWorkout` when time-cued; otherwise functional-strength open workout | Degraded | Broad activity and optional time/rest structure | Pairing semantics, per-exercise load/reps/RIR | Workout/interval completion | No Setmark result claim from push | Requires degradation acknowledgement plus proof |
| Circuit | Repeated multi-slot circuit, often mixed domain | `CustomWorkout` when time-cued; otherwise mixed-cardio/functional-strength approximation | Degraded | Step order and timing when authored | Exercise identity, station detail, reps/load and manual results | Custom or mixed workout completion | No Setmark result claim from push | Requires target adapter proof |
| Cluster | Intra-set repeats/rest for strength | Functional-strength open workout or `CustomWorkout` if rest-timed | Degraded | Broad strength activity, optional rest/work timing | Cluster identity, intra-set reps/load/RIR | Workout duration/energy/HR | Workout completed only | Requires degradation acknowledgement plus proof |
| EMOM strength | Time-bounded repeated minutes; strength/mixed domain | `CustomWorkout` with repeated time steps | Degraded | Minute cadence and duration | Rep/load targets, station results, success/fail per minute | Interval-style workout completion | No Setmark result claim from push | Requires adapter proof |
| AMRAP metcon | Time cap plus aggregate result; mixed domain | `CustomWorkout` time goal/open mixed workout | Degraded | Time cap, broad mixed/functional activity | Rounds/reps result semantics unless entered in Setmark | Workout duration/energy/HR | No Setmark result claim from push; AMRAP score remains Setmark-owned | Requires explicit degradation disclosure or remains source-ambiguous |
| Compound AMRAP plus run/carry | Time cap plus mixed strength/cardio/carry slots | `CustomWorkout` mixed approximation | Degraded | Time cap and broad activity order where possible | Compound scoring, load, distance-per-round semantics | Workout completion | No Setmark result claim from push; Setmark score remains Setmark-only | Requires adapter proof |
| For-time / chipper | Target completion by elapsed time; usually mixed slots | `SingleGoalWorkout` time/open or `CustomWorkout` approximation | Degraded | Broad elapsed-time target or open workout | Chipper station identity, reps/load and partial completion semantics | Workout elapsed time | No Setmark result claim from push; Setmark result must be entered in Setmark | Requires degradation acknowledgement plus proof |
| Capped for-time | Time cap plus completion/partial result | `CustomWorkout` time cap/open workout | Degraded | Cap duration | Finish-vs-cap partial result semantics | Workout duration | No Setmark result claim from push; cap result remains Setmark-owned | Requires explicit result-loss disclosure |
| Tabata | Fixed work/rest intervals; usually one activity | `CustomWorkout` interval blocks/steps | Native or degraded candidate | Work/rest cadence, total duration, activity | Exercise-level scoring and custom step names on lower OS floors | Interval workout completion | No Setmark result claim from push | Block until simulator and real-device proof |
| Loaded carry | Distance or duration with load; carry domain | `SingleGoalWorkout` distance/time using functional-strength or walking/hiking activity | Degraded | Distance or time goal, broad activity | Load, grip/implement details, carry-specific score | Distance/time workout completion | No Setmark result claim from push; load remains Setmark-only | Requires degradation acknowledgement plus proof |
| Skill / isometric hold | Duration or open hold; skill/static domain | `SingleGoalWorkout` time/open or `CustomWorkout` step | Degraded | Duration/open activity | Skill quality, hold standard, side/position detail | Timed/open workout completion | No Setmark result claim from push | Requires degradation acknowledgement plus proof |
| Mobility / recovery flow | Time-bounded low-intensity sequence | `SingleGoalWorkout` time or `CustomWorkout` with mind-body/flexibility-like activity where available | Native or degraded candidate | Duration, broad recovery activity | Pose/sequence detail and notes | Workout duration | No Setmark result claim from push | Block until activity support probe |
| Standalone rest / recovery | Timer-only rest or recovery block | No export by itself | Setmark-only | Nothing | Timer-only semantics are not a useful Apple workout | None | None | Do not export standalone; can be collapsed inside adjacent custom workout if safe |
| Swim / bike / run | Multi-sport sequence | `SwimBikeRunWorkout` | Future candidate; not emitted by current classifier/adapter | None yet | Multi-sport payload construction and source sport order | Multi-sport workout completion | No Setmark result claim from push | Block until target mapper and real-device proof |
| Max-effort / open-result overlay | Any domain with Setmark-owned result overlay | Underlying archetype candidate only | Degraded or Setmark-only | Underlying workout activity/goal | Max result, score, PR, success criteria | Underlying workout completion | No Setmark result claim from push; max/open score remains Setmark-owned | Candidate only if underlying row is supportable and result loss is explicit |

This matrix deliberately avoids load, reps, RIR, and per-slot strength result
fields as WorkoutKit export requirements. Those remain Setmark-owned. The
adapter may still export a degraded strength or mixed workout when that gives
Eric useful Apple Watch execution, but the export record must say that Apple
cannot produce the missing Setmark result semantics.

Push proof must answer these cases before user-facing implementation:

| Export path | Required evidence | Setmark result claim |
| --- | --- | --- |
| Open now in Workout app | Prove the platform path first. In the local Xcode 16.4 SDK, `WorkoutPlan.openInWorkoutApp()` is watchOS-only, so a phone-only implementation cannot assume direct open. | No Setmark result claim; this only starts or presents the Apple Workout flow. |
| Scheduled WorkoutKit plan | Prove iPhone scheduling support, scheduled date behavior, duplicate/update behavior, and visibility/startability on the paired Watch. | No Setmark result claim; this only creates or updates the app-owned scheduled plan. |
| Duplicate/update push | Prove whether repeated stable `WorkoutPlan.id` pushes replace, duplicate, reject, or require explicit remove-then-schedule. | No Setmark result claim; this determines idempotent push behavior only. |

## Product route v1

The current product route is deliberately narrower than the full matrix:

- `WorkoutKitHandoff` coordinates the phone-side `.scheduleOnPhone` path for
  `paceTargetRun` only.
- `Features/Today` receives SDK-free presentation strings and one action
  closure. It does not import `ExportProfile`, `WorkoutKitAdapter`, or
  `WorkoutKit`.
- The action is exposed in normal app composition for `paceTargetRun` so
  TestFlight can collect real device delivery evidence from the same button
  path users will exercise.
- The coordinator writes a latest-attempt snapshot plus a structured receipt for
  every attempted schedule and emits telemetry for presentation, exposure,
  block, tap, scheduler check, success, failure, and repeat-block states.
- Same-occurrence scheduling is one-shot after local success. Changed-payload
  replacement remains blocked until real-device duplicate/update behavior is
  proven.

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
2. **A supported workout reaches Apple Watch.** The app can schedule or hand off
   a supported workout through the proven platform path, and real-device proof
   shows it is visible/startable in Apple's Workout app on the paired Watch.
3. **Push is idempotent or clearly constrained.** Repeated pushes and schedule
   updates either have a proven safe algorithm or remain blocked from
   user-facing export.
4. **Setmark remains the source of truth for plans.** Claude-authored Setmark
   workouts still originate in the server/app model. WorkoutKit receives a
   mapped copy; it does not become the planning authority.
5. **Degradation is tracked.** Every non-native export records the WorkoutKit
   representation used, the primitive facts preserved, the primitive facts
   omitted or collapsed, and the user-visible push disclosure.
6. **Fallback is clear.** A workout that cannot map safely remains executable in
   the Setmark phone app.

## Current gaps

- `WATCHKIT-GAP-002`: The vendor-neutral export profile and fake-backed
  WorkoutKit classifier exist in `app/Packages/ExportProfile`, and
  `app/Packages/WorkoutKitAdapter` now owns the production WorkoutKit push
  entrypoint, platform gates, real schedule/open clients, and DEBUG/test
  diagnostics. `ExportProfile` owns the SDK-free resolved descriptor contract;
  the adapter translates only resolved descriptors to WorkoutKit SDK objects.
  No user-facing export button or export tracking persistence exists yet, and
  descriptor-incomplete rows remain blocked until the pure export profile can
  provide exact target and step mapping. Cardio-like rows also remain blocked
  until primitives carry source activity/location semantics; the adapter no
  longer guesses cycling for generic cardio. DEBUG diagnostics use a separate
  synthetic descriptor for evidence collection and do not imply product export
  readiness. Product export must wait for exact target/step mapping plus the
  real-device proof in `WATCHKIT-GAP-004`.
- `WATCHKIT-GAP-003`: Completion/reconciliation is a separate future lane, not
  a prerequisite for push-only WorkoutKit handoff.
- `WATCHKIT-GAP-004`: Local watchOS simulator infrastructure exists and proves
  Watch app build/install/launch plus iOS-to-Watch custom content push through
  `WatchBridge`. Scratch probe sources for real-device WorkoutKit
  schedule/open behavior exist and typecheck, but no physical iPhone/Watch is
  currently visible to Xcode, so real-device WorkoutKit visibility,
  startability, and duplicate/update behavior remain unproven.

## Relationship to custom watch-primary

This feature comes before `watch-primary-execution.md`. If it satisfies the
early delivery need, the full custom Watch app can stay deferred until Setmark
needs watch-side set logging, custom metric slots, offline event replay, route
ownership, or interaction patterns Apple's Workout app cannot express.
