---
title: Observability map — every action → where it lands
status: living
purpose: QA ground truth. For each user action and authored workout shape, enumerate which layers record state (SessionState, local cache, push queue, server DB, event_log). Makes "did it land?" answerable without reading every layer's code.
covers:
  - whole stack (iOS + server)
---

# Observability map

Every user action in WorkoutDB should leave a trail at four layers:

1. **`SessionState`** (in-memory on the main actor; persisted to `default.store` via `SessionStore`)
2. **Local `WorkoutCache`** (SwiftData — the source of truth for the app's reads)
3. **Push queue** (SwiftData `PushItemModel` — durable outbound queue)
4. **Server** — one or more of: `workout`, `block`, `workout_item`, `set_log`, `user_parameters`, `event_log`

This doc is the matrix. A "✓" means that layer records this action; "—" means it doesn't (and shouldn't). If a cell is blank, the behavior is TBD / unclear — that's a QA gap.

**Tick source.** Time-cap enforcement for AMRAP / ForTime / EMOM / Tabata runs off a 1s `Timer.publish(every: 1, on: .main, in: .common).autoconnect()` wired into both `ActiveView` and `RestView` via `.onReceive(tickTimer)`. Each tick calls `ExecutionViewModel.tickBlockTimer()`; the VM's `tickCallCount` increments every call and the `.complete` dispatch fires once `clock.now >= state.blockEndsAt`. The view-side gate `state.blockEndsAt != nil` is an optimization so non-time-capped blocks don't wake the VM each second — correctness doesn't depend on it (`tickBlockTimer` is a cheap no-op when both timers are nil). See bug-042 in `docs/bugs.md` for the wiring history.

## Actions × layers

### Authoring (server side, Claude)

| Action | server workout | server exercise | server `event_log` |
|---|---|---|---|
| POST /api/exercises (new) | — | insert/update | ✓ (via telemetry emit in Claude if wired) |
| POST /api/exercises with `default_prescription_json` | — | stored + merged on future POST /api/workouts | ✓ |
| POST /api/workouts (full) | insert workout/blocks/items/alternatives | — | ✓ |
| POST /api/workouts (sparse — relies on library default) | insert resolved prescription + `prescription_json_raw` snapshot | — | ✓ |
| PUT /api/workouts/{id} | replace blocks/items; re-merge | — | ✓ |

### App launch / sync

| Action | SessionState | Local cache | Push queue | Server | event_log |
|---|---|---|---|---|---|
| First launch, FirstRun succeeds | — | — | — | — | `bootstrap.start` ✓ |
| Pull (/api/sync/pull) | — | writes workouts, blocks, items, exercises, user_params | — | — | `network.pull_latest`, `network.response`, `bootstrap.ready` ✓ |
| Pull fails + cache has data | — | unchanged | — | — | `network.error` ✓ |
| Pull fails + cache empty | — | empty | — | — | `bootstrap.empty` ✓ |
| 401 on any request | — | — | — | — | `bootstrap.token_rejected` or equivalent ✓ |

### Workout execution

| Action | SessionState | Local cache | Push queue | Server | event_log |
|---|---|---|---|---|---|
| Tap "start workout" | route: today → active; cursor (0,0,1); items seeded | — | — | — | `today.start_tap`, `execution.session_mutation (start)` ✓ |
| Log a set (reps + RIR) | SetPlan[idx].done=true, rir populated | — | `.setLogs(SetLog)` enqueued with **deterministic UUID** from (itemID, setIndex) | on flush: upsert `set_log` by id | `execution.session_mutation (logSet)` ✓ |
| Log with RIR that triggers autoreg | proposal on currentProposal; remaining SetPlans' loadKg updated | — | (set_log already pushed) | — | `execution.autoreg_proposed` ✓ |
| Accept autoreg (default) | remaining SetPlans keep adjusted loadKg | — | — | — | — (accept is implicit; no explicit event today) |
| Undo autoreg | `itemLog.autoregHeld = true`, remaining SetPlans revert | — | — | — | `execution.autoreg_undo` ✓ |
| Enter rest | route: active → rest; `restEndsAt = now + driver.restDuration` | — | — | — | — (no event; could add for debugging) |
| Time-cap tick (AMRAP / ForTime / EMOM / Tabata) | `tickCallCount` bumps; once `clock.now >= blockEndsAt`, route flips to `.complete` (Tabata also auto-logs a placeholder 0-rep set when `workEndsAt` elapses) | — | — | — | `execution.session_mutation (complete)` when the cap flips the route ✓ |
| Advance from rest (auto or tap next) | route: rest → active (or complete if last); cursor advances | — | — | — | `execution.session_mutation (advance)` ✓ |
| Tap past-set pill in Rest, edit reps/rir | SetPlan[idx] mutated | — | re-enqueued with **same deterministic UUID** → server upsert | server updates same SetLog row | `execution.past_set_edited` ✓ |
| Long-press exercise → swap alternative | `.swap` mutation: item's `overrides` set; reps/loadKg applied to non-done sets | — | — | (next log_set push carries `performed_exercise_id`) | `execution.exercise_swap` ✓ |
| Long-press + swap with `parameter_overrides_json` | `overrides: { reps, load_kg, target_rir }` stored on ItemLog | — | — | — | `execution.exercise_swap (hadOverrides: true)` ✓ |
| Tap "skip" on RIR sheet | SetPlan[idx].rir = nil, done=true | — | `.setLogs(SetLog)` with rir=nil enqueued | on flush: upsert with rir=NULL | `execution.session_mutation (logSet)` ✓ |
| "End" button (force complete mid-workout) | route → complete; log preserved | — | — | — | `execution.session_mutation (complete)` ✓ (no status_update yet — see `complete()` contract) |

### Completion

| Action | SessionState | Local cache | Push queue | Server | event_log |
|---|---|---|---|---|---|
| Tap "save & done" (no BW/note) | route: complete → today; state cleared | workout status=completed, set_logs written | `.statusUpdate(workout_id, .completed, completed_at)` enqueued | on flush: workout.status='completed', completed_at populated | `execution.session_mutation (save)` ✓ |
| Tap "save & done" with note | (state cleared) | workout.notes populated on local cache write | (status_update; note is local-only for now) | — (server's status_update has no notes field) | same ✓ |
| Tap "save & done" with bodyweight | (state cleared) | user_parameter (key=bodyweight_kg) upserted | `.userParameter(UserParameter)` enqueued | on flush: `user_parameters` insert (append-only) | same ✓ |

### History

| Action | SessionState | Local cache | Push queue | Server | event_log |
|---|---|---|---|---|---|
| Tab to History | — | read completed workouts | — | — | — (no tab-switch event today — gap) |
| Tap a completed-session row | — | read set_logs for that workout | — | — | — (no row-tap event today — gap) |
| Edit a past-set from history detail sheet | — | SetLog upserted (same id) | re-enqueued (same id) | server upserts | `history.past_set_edited` ✓ |

### Persistence boundaries

| Action | Session persists? | Cache persists? | Queue persists? |
|---|---|---|---|
| App backgrounded mid-workout | ✓ (SessionStore codable) | ✓ (SwiftData) | ✓ (SwiftData) |
| App killed mid-workout | ✓ (restored on launch) | ✓ | ✓ |
| App killed mid-rest | ✓ (`restEndsAt` absolute timestamp survives) | ✓ | ✓ |
| Device time change during rest | — (rest arithmetic uses wall clock; may fire early/late) | — | — |

---

## Interaction matrix (what gestures trigger what)

| Gesture target | What happens | Trail |
|---|---|---|
| Tap "start workout" on Today | `sessionStateBinding(.start)` → `ExecutionVM.start()` | session + event |
| Tap "log set N" on Active | Open `LogSetSheet` | (no side effects until commit) |
| Tap digit on LogSetSheet numpad | Append to reps buffer | (sheet state only) |
| Tap "delete" on numpad | Trim rightmost digit | (sheet state only) |
| Tap a RIR button on LogSetSheet | Select that RIR (toggle off if already selected) | (sheet state only) |
| Tap "log" on LogSetSheet | `ExecutionVM.logSet(reps:, rir:)` | full log path (see above) |
| Tap past-set pill on RestView | Open `PastSetSheet` pre-filled | (sheet state only) |
| Commit past-set edit | `ExecutionVM.editPastSet(...)` | full edit path |
| Long-press Active card | Open `SwapSheet` with item's alternatives | (sheet state only) |
| Tap an alternative in SwapSheet | `ExecutionVM.swap(itemID:alternativeID:)` | full swap path |
| Tap "next" on RestView | `ExecutionVM.advance()` | advance path |
| Tap "save & done" on CompleteView | `ExecutionVM.saveAndDone(note:bodyweightKg:)` | full save path |
| Tap a past session row in History list | Push detail view (NavigationLink) | no event emitted today — gap |
| Tap a set row in HistorySessionDetailView | Open `EditSetSheet` | (sheet state only) |
| Commit edit in EditSetSheet | `HistoryVM.editPastSet(workoutID:setLogID:reps:rir:weight:)` | history-edit path |
| Swipe-down on any sheet | Dismiss without commit | — |

---

## QA coverage map

Each feature doc's scenarios should exercise the rows above. Current gaps flagged (looked for ✗ or missing):

- **No telemetry event for "enter rest"** — makes it harder to diff "did the rest timer fire at the right moment" from logs alone. Low-priority gap; filable if we hit a debugging wall.
- **No telemetry event for tab switches or history row taps** — same; only matters if we're diagnosing routing bugs.
- **Skipping RIR by tapping "skip"** — this path should produce a SetLog with rir=nil and a `logSet` event; verify during persona QA.
- **Accept autoreg is not a discrete event** — accept-by-default means it's implicit. If the user never taps undo, the fact that they accepted is derivable from state, not from an event. Acceptable.
- **Mid-workout "End" button** — `complete()` doesn't enqueue status_update (intentional per bug-005/006 fix); only `saveAndDone` does. Persona QA should verify: explicit End → navigate away without saveAndDone → workout stays `active` on server. That's correct.
- **Device clock skew** — no mitigation. Worth a flag in docs/open-questions.md.

## How to use this

1. When you implement a new user-facing feature, add its row to the table above.
2. When you write QA scenarios, cite which layer-cells you're verifying.
3. When a user reports "did X work?", this is the first place to look to know where to check.
