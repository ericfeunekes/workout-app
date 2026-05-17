---
title: Watch-primary execution
status: planned
last_reviewed: 2026-05-17
purpose: Feature spec for starting, mirroring, handing off, and reconciling Apple Watch workout execution.
covers:
  - app/WorkoutDBWatch/
  - app/Packages/Features/WatchFaces/
  - app/Packages/WatchBridge/
  - app/Packages/HealthKitBridge/
  - app/Packages/Features/Execution/
  - app/Packages/Shell/
---

# Watch-Primary Execution

> **Planning note (2026-05-17):** The shorter Apple Watch delivery path is now
> `watch-workoutkit-handoff.md`: map eligible Setmark workouts into Apple's
> Workout app through WorkoutKit, then reconcile coarse completion back into
> Setmark. This custom watch-primary spec remains the later path for Setmark
> watch-native execution: offline event replay, custom metric slots, watch-side
> set logging, route ownership, and phone/watch authority handoff.

Eric needs the Watch to be able to run the workout when the phone is nearby,
in a bag, or left behind. The current companion model is too weak for that:
the Watch can display a face and emit start/end messages, but the phone has no
watch inbox, the watch payload lacks stable cursor identity, and delayed
WatchConnectivity delivery can make an old action look current. The feature is
not "make the Watch independent of the system." It is: make one device the live
workout authority, let the other mirror, and reconcile back through the phone.

The intended model is start-origin plus explicit handoff. Starting on the
phone creates a phone-primary session. Starting on the Watch creates a
watch-primary session from cached executable workout data. A phone-started
session may offer `Drive from Watch`; accepting it creates a new authority
epoch and transfers timers, advancement, and logging to the Watch. The phone
remains the authoring, customization, and server-sync surface. The Watch never
talks to the server directly.

The feature should make these outcomes possible:

- The user can start on the phone and use the Watch as a mirror for HR, current
  work, upcoming work, and the fixed watch views.
- The user can start on the Watch from cached workout data and leave the phone
  behind.
- The user can hand a phone-started workout to the Watch before leaving the
  phone.
- The Watch can continue timers, transition fallbacks, HR capture, and logging
  while disconnected.
- When the Watch reconnects, the phone catches up without duplicate logs and
  pushes results through the existing sync queue.

The first custom watch-primary scope excludes direct Watch-to-server sync,
editing watch slot layout on the Watch, multi-primary execution, durable route
tables, and WorkoutKit handoff behavior. GPS pace, route progress, and
directions use the same authority model later, but they should not block the
first authority and display cutover.

The live authority record is session-scoped:

```text
session_id
primary_authority: phone | watch
authority_epoch
started_at
handoff_reason: phone_start | watch_start | drive_from_watch | reconnect
```

The primary device may emit start, advance, complete, log, and sensor-backed
transition events. The secondary device may mirror display state and request
safe display-only changes, but must not mutate the live cursor. Any action
whose authority epoch, active cursor, or spec revision is stale must be
rejected or explicitly reconciled.

The Watch needs a cached executable package before it can be primary:

```text
workout
blocks
items
prescriptions
timing configs
watch slot config
target windows
route package when available
spec_revision
```

While watch-primary, the Watch records an append-only event log:

```text
session_id
authority_epoch
active_cursor_id
spec_revision_seen
event_id
event_type
created_at
payload
```

On reconnect, the Watch sends unsynced events to the phone. The phone applies
events idempotently inside the matching session and authority epoch, ignores
duplicate event IDs, rejects stale epochs unless they are explicitly
equivalent, and then pushes the resulting logs/status through the existing
server sync path.

## Acceptance Criteria

- Starting a workout from the phone creates a phone-primary session; the Watch
  mirrors the same active cursor, HR slot, current work, and upcoming work
  without independently advancing the session.
- Starting a workout from the Watch creates a watch-primary session from the
  latest cached executable workout package and does not require phone
  reachability at start time.
- `Drive from Watch` on a phone-started workout creates a new authority epoch;
  after handoff, Watch events advance and log the session, while stale phone
  or Watch actions from the prior epoch do not mutate it.
- During a watch-primary disconnected period, the Watch keeps timer state,
  records HR when available, supports manual transitions through the primary
  action, and appends durable local events.
- Reconnect replay is idempotent: replaying the same Watch event batch twice
  produces one set of logs/status updates on the phone.
- A stale action from an old cursor, old spec revision, or old authority epoch
  is rejected or reconciled without moving the current session to the wrong
  phase.
- The three watch views follow `docs/watch-metrics.md`: persistent HR slot,
  stable current/upcoming positions, and no fake progress for manual reps/load.
- Route and directions work later under the same rule: when the Watch is
  primary, it can own route progress; the phone still owns server sync.

## Current gaps

- `WATCHCUSTOM-GAP-001`: Real-device behavior is still unproven for `HKHealthStore.startWatchApp`,
  HealthKit session ownership, inactive WatchConnectivity delivery, and
  programmable double tap.
- `WATCHCUSTOM-GAP-001`: The current WatchBridge schema is rendered-string oriented and unversioned.
  Implementation must replace it before enabling watch-primary actions.
- `WATCHCUSTOM-GAP-001`: The phone-side watch inbox does not exist today, so current Watch taps do not
  mutate phone session state.
- `WATCHCUSTOM-GAP-002`: Watch durability during app termination must be proven before relying on
  disconnected execution for real workouts.

## Risks And Open Questions

- The installed project currently targets watchOS 10. Programmable
  `handGestureShortcut(.primaryAction)` support may require raising the watch
  target to watchOS 11, but primary authority must not depend on that decision.

No rollout flag is planned. This is a single-user app, and the correct rollout
posture is a complete cutover with strong local proof and a real-device spike
before relying on Watch-only workouts.

## Planning Notes

If this later capability becomes active, re-enter phase planning from this
feature doc, `docs/watch-metrics.md`, `docs/sync.md`, and the exact
`WATCHCUSTOM-*` gap IDs in `docs/backlog.md`. Do not preserve a durable phase
split here; the correct implementation sequence depends on the app, WatchKit
handoff evidence, watchOS target, and HealthKit behavior at that time.

Proof must include Codable protocol tests, pure authority/event replay tests,
watch bridge boundary tests, watch UI proof for the fixed slots, and real-device
spikes for platform behavior.
