---
title: Watch metrics contract
status: draft
last_reviewed: 2026-05-17
purpose: Slot, metric, target-window, and phone/watch lifecycle contract for the Setmark watchOS workout app.
covers:
  - app/WorkoutDBWatch/
  - app/Packages/Features/WatchFaces/
  - app/Packages/WatchBridge/
  - app/Packages/HealthKitBridge/
---

# Watch Metrics Contract

This doc defines the target contract for the next watchOS app design. It is
not the current implementation. It exists so the watch app can be built against
one reusable metric system instead of one-off workout screens.

This is only for the later custom Setmark Watch app. It does not apply to the
early WorkoutKit handoff lane in `docs/features/watch-workoutkit-handoff.md`,
where Apple's Workout app owns the live Watch UI, metric layout, haptics, and
primary actions.

The watch answers two questions first:

1. What do I do right now?
2. What is my body or the target doing right now?

The phone remains the authoring, customization, and server-sync surface. Live
execution has one primary authority at a time. The primary device owns timers,
advancement, and logging; the other device mirrors state and can show useful
data without independently advancing the workout.

## Live Authority Model

The feature spec for this work lives in
`docs/features/watch-primary-execution.md`. This section records only the
domain contract that the watch metric renderer and phone/watch protocol must
respect.

`primary_authority` is part of live session state:

```text
phone | watch
```

The authority record should include:

```text
session_id
authority
authority_epoch
started_at
handoff_reason: phone_start | watch_start | drive_from_watch | reconnect
```

Rules:

- Starting on the phone creates a phone-primary session.
- Starting on the Watch creates a watch-primary session from the latest cached
  executable workout package.
- `Drive from Watch` creates a new authority epoch and transfers live execution
  to the Watch.
- The primary device may emit `start`, `advance`, `complete`, `log`, and
  sensor-backed transition events.
- The secondary device may emit display-only preferences and safe mirror
  requests, but must not mutate the live cursor.
- Any action whose `authority_epoch` does not match the current epoch is stale.
  It must be rejected or reconciled explicitly.

## View Grammar

The watch has three fixed views. Swiping changes views. Double tap performs the
current primary transition when the platform supports it.

### Main

Purpose: show what to do now and what comes after it.

Fixed slots:

- Top-left: current context, for example `SET 3/5`, `REST`, `INT 3/8`.
- Top-right: heart rate slot, always reserved.
- Center: current task or current auto-tracked target.
- Bottom: upcoming content. Do not label it `next`; position carries meaning.

Manual example:

```text
SET 3/5                     138

BENCH
102.5 x 5

REST 90s
```

Auto-trackable example:

```text
REST                        104

1:14

ROW 77.5 x 8
```

### Data

Purpose: show the athlete's chosen live metrics for the current block.

Fixed slots:

- Top-left: view context, for example `TEMPO`, `LAP DIST`, `DISTANCE`.
- Top-right: heart rate slot, always reserved.
- Upper/middle: one large primary metric.
- Bottom-left: two stacked secondary metrics.
- Bottom-right: one larger tertiary metric.

Example:

```text
TEMPO                    166 Z4

4:28/km

ZONE 4                  3.6 km
TIME 26:12
```

### Quadrant

Purpose: show four data fields at once. Route directions use this later, but
the view must still keep at least one primary effort metric visible.

Fixed slots:

- Top-left: view context.
- Top-right: heart rate slot, always reserved.
- Four equal quadrants below the top band.

Route example:

```text
ROUTE                      158

4:52/km        2.1 km

LEFT           320 m
Robie St
```

## Heart Rate Slot

Heart rate is a layout invariant, not an optional metric slot.

The top-right HR position is always reserved on every view. The value can
change state:

- Live: `138`, `166 Z4`.
- Permission missing: neutral unavailable state.
- Sensor unavailable: neutral unavailable state.
- Not applicable yet: neutral pending state.

`fallback: "hide"` is not valid for the persistent HR slot. Hiding HR would
shift the layout and violate the watch design grammar. Fallback controls the
value state, not the slot's presence.

## Metric Model

Every watch metric resolves through a small contract:

```text
id
role
source
detectability
display_fallback
transition_fallback
target_window
debounce
```

### Role

- `primary_result`: the metric the block is scored or completed by.
- `guidance`: useful live coaching, but does not complete or fail the block.
- `transition_trigger`: the metric can advance or finish the current phase.
- `summary_only`: useful later, not a default live watch metric.

Only one metric should be the primary result for a phase. Other targets may
color their own slots, but they do not redefine the phase result.

### Source

- `prescription`: authored target, for example load, reps, target RIR.
- `session`: current cursor, phase, set index, rest timer, round index.
- `sensor`: live HR, GPS distance, cadence, speed.
- `derived`: rolling pace, distance remaining, target delta, progress percent.
- `route`: turn direction, street name, distance to turn.

### Detectability

- `manual`: the watch cannot know completion, for example bench reps.
- `clock`: elapsed or remaining time.
- `gps`: distance, pace, route progress.
- `healthkit`: heart rate and HR zone.
- `motion`: cadence or later bar/motion signals.
- `route`: route instruction progress.

Detectability is per station/item/phase, not per timing mode. A circuit may
contain a manual bench station and a GPS-trackable run station.

## Target Windows

Target windows are authored as data. The app does not invent percentage
tolerances.

In green:

- Use the normal metric color.
- Show no arrow.

Outside green:

- Tint the metric yellow or red from the authored window.
- Show a small up or down arrow beside the metric.

Missing or unreliable sensor data:

- Do not show red.
- Use the metric's fallback state.

### Direction Semantics

Target windows must specify direction semantics. The renderer cannot infer
whether a higher number is better.

Examples:

- Pace in `sec_per_km`: lower is faster. Too low may mean "too fast".
- Speed in `km_per_h`: higher is faster. Too high may mean "too fast".
- HR bpm: higher means more effort.
- Cadence spm: higher means faster turnover.
- Distance remaining: lower means closer to done.

Arrow meaning is "move back toward the green window", not "numeric value went
up or down". For pace, a runner who is too fast may see a down-effort arrow
even though the numeric `sec_per_km` value is too low.

### Window Shape

Example:

```jsonc
{
  "metric": "derived.rolling_pace",
  "unit": "sec_per_km",
  "direction": "lower_is_faster",
  "green": { "min": 260, "max": 280, "bounds": "inclusive" },
  "yellow": [
    { "min": 250, "max": 259, "bounds": "inclusive" },
    { "min": 281, "max": 295, "bounds": "inclusive" }
  ],
  "red": [
    { "max": 249, "bounds": "inclusive" },
    { "min": 296, "bounds": "inclusive" }
  ],
  "arrow": "outside_green_only",
  "debounce": { "seconds": 5 }
}
```

Rules:

- Ranges are inclusive unless stated otherwise.
- Red wins over yellow if ranges overlap.
- Green wins only inside the green range.
- Gaps resolve to neutral, not red.
- Debounce is required for noisy live sensor metrics.

## Rolling Pace

Rolling pace is the default live coaching pace. Current pace is available but
noisy. Whole-session average pace is summary-first and should not be the
default live watch metric.

The workout author may specify the rolling window. If omitted, the resolver may
use an automatic policy from the target distance or duration.

Suggested automatic policy:

```text
<= 400 m        20-30 s or 100 m
800 m-1 km      45-60 s or 200 m
5K/10K          2-3 min or 500 m
long run        5 min or 1 km
```

The window is not shown on the watch during normal use.

## Fallbacks

Display fallback and transition fallback are separate.

### Display Fallback

Display fallback controls what appears in the slot when a value cannot be
resolved.

- `neutral`: keep the slot, show an unavailable or target-only state.
- `target_only`: show the authored target without live comparison.
- `pending`: show that the value is not available yet.
- `hide`: allowed only for non-fixed optional slots.

### Transition Fallback

Transition fallback controls what happens when a metric was supposed to advance
or complete a phase.

- `manual_transition`: require double tap or phone action.
- `elapsed_only`: continue with time but stop using distance/pace detection.
- `manual_log`: require manual result capture.
- `block_start`: refuse to start the phase until the required sensor is ready.

Any metric with `role: "transition_trigger"` must author a transition fallback.
If it does not, the workout is invalid for watch-driven execution.

## Active Cursor And Slot Resolution

Slot resolution must use an explicit active cursor. This prevents block-level
settings from leaking into the wrong station and prevents stale watch actions.

The active cursor should include:

```text
workout_id
session_id
block_id
round_index
item_id or station_id
set_index when applicable
phase: ready | active | rest | complete
phase_started_at
spec_revision
```

The slot resolver merges configuration in this order:

1. Global personal defaults.
2. Timing-mode or archetype template.
3. Block-level `watch` defaults from `timing_config_json`.
4. Item/station-level `watch` overrides from `prescription_json`.
5. Phase-level override, for example rest or interval recovery.

Override rules:

- A more specific slot replaces a less specific slot with the same slot key.
- `null` removes an inherited optional slot.
- The persistent HR slot cannot be removed.
- Target windows attach to the metric and phase where they are authored.
- If a slot metric is incompatible with the active item/phase, the resolver
  must use that slot's display fallback rather than rendering stale data.

`next.work_target` resolves from the active cursor:

- Next set when the current item has pending sets.
- Next station inside a round-robin block.
- Next round when the block repeats.
- Next block when the current block is done.
- Empty only at workout completion.

## Phone/Watch Protocol

The watch display must be versioned. WatchConnectivity delivery can be delayed,
and a double tap can otherwise apply to the wrong phase.

Every watch display payload should include:

```text
workout_id
session_id
active_cursor_id
spec_revision
primary_authority
authority_epoch
views
rendered_slots
```

Every watch action should include:

```text
workout_id
session_id
active_cursor_id
spec_revision_seen
authority_epoch_seen
action
created_at
```

Action rule:

- If the receiver's active cursor, spec revision, and authority epoch still
  match, apply the action.
- If the cursor changed but the action is still obviously equivalent, the phone
  may reconcile it.
- Otherwise reject or ignore the action and push the current display state back
  to the watch.

This is especially important for EMOM, tabata, intervals, and any phase where a
timer can advance while the watch app is backgrounded.

Watch-primary execution also needs package, handoff, and event-log messages:

- `workout_package`: phone sends the Watch the executable workout package.
- `authority_handoff`: phone and Watch agree that a new authority epoch starts.
- `watch_event_batch`: Watch sends primary-authority events back to the phone.
- `event_ack`: phone acknowledges which Watch events have been reconciled.

These messages still travel through WatchConnectivity. The Watch does not talk
to the server.

## Workout-Type Mapping

### Strength / Set-Based

- Manual-first.
- Main view shows current set prescription and upcoming rest/work.
- HR fixed.
- No fake progress for reps or load.
- RIR is not live; it can color post-log or rest/next-set displays only after
  the user logs RIR.
- Duration holds can become clock-detectable if authored that way.

### Superset / Circuit

- Current station fills the main "now" slot.
- Upcoming station/rest fills the stable upcoming slot.
- Detectability is per station.
- A strength station remains manual.
- A run/carry station can be sensor-aware if the target and fallback are
  authored.

### EMOM / Tabata

- Timer/phase is real.
- Manual work is not auto-completed.
- HR, pace, cadence, or finish-by-time windows can be guidance.
- If the interval boundary passes, the watch may move on, but it must not imply
  the manual set was completed.

### AMRAP

- Cap and rounds/reps remain the result.
- Main view shows current station and upcoming station.
- HR zone, pace, or cadence target is guidance unless explicitly authored as a
  stop or transition rule.
- A red HR zone should not interrupt or fail the AMRAP by default.

### For Time

- Elapsed time is the score.
- Pace/zone on a run segment can color that metric but does not redefine the
  score.
- GPS can eventually auto-complete distance stations.
- Manual reps still need double tap or phone action.

### Intervals

- Best fit for authored windows.
- Each interval may have its own pace, cadence, or zone range.
- Time boundaries auto-transition.
- Distance boundaries auto-transition only when GPS support is real and a
  transition fallback is authored.

### Continuous

- Primary metric should be the authored driver: rolling pace, HR zone, distance
  remaining, or time remaining.
- Reaching the target can notify, complete, or continue depending on authored
  behavior.

### Accumulate

- Main view shows accumulated/target and current bout target.
- Duration and distance can be auto-trackable.
- Reps, quality, and manually judged chunks remain manual.

### Rest

- Countdown plus upcoming work plus HR.
- HR recovery target can color HR later, but should not hide upcoming work.

### Route / Directions

Deferred. Use the quadrant view later.

Reserved route metrics:

- `route.turn_direction`
- `route.street_name`
- `route.distance_to_turn`
- `route.distance_remaining`
- `route.off_route_state`

Route directions must not replace the primary workout metric. Orientation and
effort need to coexist.

## Authoring Shape

Use optional `watch` objects inside existing JSON blobs at first. This avoids a
database migration while the display contract is still evolving.

Block-level defaults live in `block.timing_config_json`:

```jsonc
{
  "target_duration_sec": 2700,
  "target_pace_sec_per_km": 270,
  "watch": {
    "default_views": ["main", "data", "quadrants"],
    "slots": {
      "persistent_hr": {
        "metric": "sensor.hr_bpm",
        "display_fallback": "neutral"
      },
      "primary": {
        "metric": "derived.rolling_pace",
        "window": { "kind": "auto" },
        "display_fallback": "target_only"
      },
      "secondary_1": { "metric": "progress.elapsed_time" },
      "secondary_2": { "metric": "progress.distance_done" },
      "tertiary": { "metric": "progress.distance_left" }
    },
    "windows": {
      "derived.rolling_pace": {
        "unit": "sec_per_km",
        "direction": "lower_is_faster",
        "green": { "min": 260, "max": 280, "bounds": "inclusive" },
        "yellow": [
          { "min": 250, "max": 259 },
          { "min": 281, "max": 295 }
        ],
        "red": [
          { "max": 249 },
          { "min": 296 }
        ],
        "arrow": "outside_green_only",
        "debounce": { "seconds": 5 }
      }
    }
  }
}
```

Item-level overrides live in `workout_item.prescription_json`:

```jsonc
{
  "sets": 4,
  "reps": 5,
  "load_kg": 225,
  "target_rir": 2,
  "watch": {
    "slots": {
      "primary": { "metric": "prescription.work_target" },
      "secondary_1": { "metric": "prescription.load" },
      "secondary_2": { "metric": "prescription.target_rir" },
      "tertiary": { "metric": "next.work_target" }
    }
  }
}
```

Do not promote this to a first-class table until one of these becomes true:

- Route plans need durable queryable data.
- Watch telemetry needs durable queryable data.
- Multiple clients need to update slot preferences independently.
- The JSON contract stabilizes and validation needs to move earlier.

## Customization

Slot editing belongs on the phone before workout start. The watch may preview
the three views read-only, but should not offer slot editing.

Default resolver order:

1. Workout-authored slot spec, including target windows.
2. Goal/target template, such as pace target, HR-zone target, cadence target,
   or distance target.
3. Timing archetype default.
4. Global personal default.

Mid-workout slot changes, if needed, happen on the phone. They are display-only
changes and do not pause the workout. The phone pushes a new versioned display
payload to the watch.

## Current Gaps

- `WATCHCUSTOM-GAP-003`: The three-view custom Watch renderer, metric resolver,
  persistent HR slot states, target-window display, and route/directions
  quadrant are target behavior, not implemented behavior. Route/directions work
  must prove route package fidelity, GPS ownership, and honest unavailable
  states before it can claim guidance.

## Open Platform Decisions

These must be spiked on real devices before implementation relies on them:

- Whether `HKHealthStore.startWatchApp(with:)` reliably wakes the companion
  watch app when the phone starts a workout.
- Whether the HealthKit workout session should be watch-primary mirrored to
  phone, or phone-primary waking the watch.
- Whether the project should move from watchOS 10 to watchOS 11 for
  programmable double-tap primary actions.
- Whether double tap can be trusted on the user's actual Watch model and
  settings.
- How reliably WatchConnectivity delivers slot-spec updates when the watch app
  is inactive.
- Whether WatchConnectivity transfers the executable workout package early
  enough for a Watch-started workout to be available offline.
- Whether the Watch can keep the needed event log durable across app
  termination during an active workout.

## Proof Cases

Before implementation is considered ready, prove these cases:

- Strength set: HR slot remains present when HR is unavailable.
- Strength set: reps/load show no fake progress.
- Tempo run: rolling pace uses authored green/yellow/red windows and arrow
  direction is correct for inverse pace values.
- AMRAP with HR guidance: HR colors from authored windows but does not
  complete, fail, or interrupt the AMRAP.
- Mixed circuit: strength station uses manual behavior, run station uses
  sensor-aware behavior, and slot overrides do not leak between stations.
- Distance interval without GPS: transition fallback becomes manual rather than
  red/off-target.
- EMOM boundary: timer advances without marking unresolved manual work as done.
- Mid-workout display update: stale double-tap action is rejected or reconciled
  by session/cursor/spec revision.
- Phone-started workout: phone is primary, Watch mirrors HR, current work, and
  upcoming work without advancing the session.
- Watch-started workout: Watch is primary from cached workout data and can
  continue without phone reachability.
- `Drive from Watch`: authority handoff creates a new epoch, and stale phone
  or Watch actions from the prior epoch do not mutate the session.
- Reconnect: Watch event replay is idempotent and produces no duplicate logs.
- Route quadrant placeholder: route directions coexist with one primary effort
  metric.
