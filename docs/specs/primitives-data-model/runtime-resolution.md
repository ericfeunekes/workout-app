---
title: Runtime resolution — seed, log, and correction time
status: accepted — spec
parent: ../primitives-data-model.md
purpose: What the app does at three moments. Seed time (pull -> ExecutionPlan, stimulus resolution via hierarchy walk, relative-load resolution to absolute kg). Log time (driver iteration over primitive cells, index assignment, completion vs observation role dispatch). Correction time (same-UUID upsert, autoreg proposal flow).
---

# Runtime resolution


## Scope

Given the authoring shape (authoring-shape.md) and log shape (log-shape.md), this section pins down what the app does at three moments: **seed time** (workout is pulled and turned into executable state), **log time** (driver produces and commits log events as work happens), and **correction time** (history edits overwrite existing rows).

This aspect resolves Q-F / Q-J (relative-load resolution timing), Q-H (cluster authoring), Q-I (metric role dispatch in drivers), Q-L (AMRAP partial-station accounting), Q-M (`set_repeat_index` semantics on multi-slot traversals).

**In scope:**
- Seed-time walk of the authored JSON into executable `ExecutionPlan`
- Stimulus resolution (hierarchy walk + library defaults + alternatives) into per-slot effective stimuli
- Relative-load resolution to absolute kg at seed time
- Slot / set / block iteration model and how the driver produces log events
- Index assignment rules (`set_index`, `set_repeat_index`, `block_repeat_index`)
- Completion vs observation role dispatch
- Correction semantics and same-UUID upsert
- Autoreg proposal flow

**Out of scope:**
- Migration from today's runtime state (cutover.md)
- UI component composition (separate downstream unit, named in the concept doc)
- New driver implementations per primitive (downstream; this section specifies the contract drivers read against, not the driver code)

## The seed-time transform

When a workout is pulled from the server (or authored locally), the app transforms the authored JSON into an **`ExecutionPlan`**: a flat, indexed structure the driver iterates. The authored JSON is the source of truth; the `ExecutionPlan` is a derived cache.

### Shape of `ExecutionPlan`

```
ExecutionPlan
├── workout_id
├── blocks: [ExecutionBlock]
    ├── block_id                    -- from block.id (authoring-stable)
    ├── block_repeat: Int           -- from block.repeat
    ├── block_timer: BlockTimer?    -- from block.timer
    ├── block_work_target: [WorkTargetEntry]  -- from block.work_target, may be empty
    ├── effective_stimuli: [Stimulus]  -- resolved for each scope at seed; cached here for block-scope
    ├── sets: [ExecutionSet]
        ├── set_id                   -- from set.id (authoring-stable)
        ├── set_repeat: Int          -- from set.repeat
        ├── timing: Timing
        ├── traversal: Traversal
        ├── set_work_target: [WorkTargetEntry]
        ├── effective_stimuli: [Stimulus]  -- resolved at set scope
        ├── slots: [ExecutionSlot]
            ├── slot_id              -- from slot.id (authoring-stable)
            ├── exercise_id
            ├── work_target: [WorkTargetEntry]  -- from slot
            ├── load_kg: Double?     -- RESOLVED to absolute kg (or nil for bodyweight)
            ├── load_unit: "kg" | "lb" | nil  -- authored unit preserved for display
            ├── load_display_value: Double?   -- authored value in authored unit (for UI round-trip)
            ├── load_reference: {kind: "1rm" | "bodyweight", key: String, value: Double}?
                                     -- if relative, the resolved reference: key is the user_parameters key, value is the absolute kg
            ├── resolved_from_user_param_id: UUID?  -- pinned user_parameters row used to resolve load; nil for bodyweight or absolute loads
            ├── effective_stimuli: [Stimulus]  -- resolved at slot scope
            ├── post_rest_sec: Int
            ├── is_warmup: Bool
            ├── alternatives: [ExecutionAlternative]  -- swap candidates, fully materialized
                ├── id
                ├── exercise_id
                ├── work_target? load? stimuli?  -- nil means inherit from base at swap time
```

Each `WorkTargetEntry` keeps its `(metric, value_form, value, role)` tuple. Each `Stimulus` in `effective_stimuli` keeps its type, target, and (if present) the resolved autoreg rule set.

### Stimulus resolution at seed time

For each slot, compute `effective_stimuli` by walking `workout.stimuli` → `block.stimuli` → `set.stimuli` → `slot.stimuli`, applying nearest-wins per stimulus type. **Library-default merge does NOT happen at seed time** — it already happened at server-side ingest (authoring-shape.md), and the stored workout's slot-level `stimuli` arrays already carry any library defaults that applied.

The result is cached on the slot. Block-scope and set-scope `effective_stimuli` are also computed and cached so aggregate-row write paths (set_result / block_result) can emit stimulus context without re-walking.

**Why cache at seed.** Stimuli drive two things: what the editor renders for a slot (read often during the session) and what stimulus columns the log event populates. Walking the hierarchy on every read is cheap but repeats across surfaces — preview, active, logger, history. Cache once per pull.

**Re-resolution on swap.** When the user swaps a slot to one of its `alternatives`, the alternative's overrides (from the `ExecutionAlternative` object cached at seed) replace the base slot's effective fields per the authoring-shape.md swap rules. The slot's `effective_stimuli` is recomputed against the alternative's `stimuli` (or inherited from base). The slot's `id` does not change; log rows after the swap carry the same `slot_id` with `performed_exercise_id` set to the alternative's `exercise_id`.

### Resolving Q-F / Q-J — relative load resolves once at seed

**Decision: relative loads resolve at seed time and cache the absolute kg on `ExecutionSlot.load_kg`. No re-resolution on each read.**

Rationale:
- **Stability.** A `(0.85, "1rm", relative)` slot seeded at workout pull uses the `user_parameters` row (key: `one_rep_max_<exercise_id>_kg`) with `updated_at` latest-before-pull. If the user tests a new 1RM mid-session, pre-seeded slots keep the pull-time target; newly-seeded workouts use the new 1RM.
- **Single-read.** Resolve once at pull from the local `user_parameters` mirror and record the pinned `resolved_from_user_param_id` on `ExecutionSlot` for auditing. No repeated DB hits during the session.
- **Audit trail.** If a future session asks "what 1RM did this workout use to set my load?", the cached `load_reference.value` and the pinned `resolved_from_user_param_id` answer directly.

**Resolver contract.**

- `unit: "1rm"` → look up `user_parameters` where `key = "one_rep_max_<slot.exercise_id>_kg"` AND `updated_at <= pull_time`, taking the most recent. Multiply `load.value` by the parameter value to get `load_kg`. Pin that parameter row's `id` on `ExecutionSlot.resolved_from_user_param_id`.
- `unit: "bodyweight"` → look up `key = "bodyweight_kg"` the same way. Multiply `load.value` by the parameter value to get `load_kg`.
- `unit: "kg"` or `"lb"` with `unit_type: "absolute"` → no resolution. `load_kg` is the raw value converted to kg if authored in lb; `resolved_from_user_param_id` stays nil.

If a required `user_parameter` is missing at pull time, the slot's `load_kg` is left nil and a warning is raised to the sync layer. Execution falls back to the authored absolute if one was given alongside the relative (not currently authored — flagged for future authoring-surface extension).

Corrections change this behavior predictably: if history correction on a relative-load slot changes the load, it changes the absolute stored on the log row — the prescription's relative authoring is unchanged, but the logged outcome reflects what actually happened.

The authored `load` keeps `unit: "1rm"` and `value: 0.85` in the prescription JSON (never rewritten). `load_kg` on the execution plan is derived cache only.

### Resolving Q-H — cluster authoring is explicit multi-slot

**Decision: clusters author as a set with multiple slots (same exercise, per-slot reps, `post_rest_sec: intra_set_rest`). No implicit expansion from one slot + sub-reps metadata.**

Rationale:
- **Composition over specialness.** The Block > Set > Slot hierarchy already expresses every cluster: "15 total reps as 5/4/3/3 with 20s between" is a set with four slots (same exercise_id, work_target `[(reps, 5|4|3|3, completion)]` respectively, `post_rest_sec: 20`, last slot `post_rest_sec: 0`).
- **No hidden expansion.** The driver does not ad-hoc split. If the author wants an even split, they author even slots; if they want a descending cluster, they author a descending cluster. Authoring carries the rep distribution explicitly.
- **Rest-pause is the same primitive.** "15 reps, rest 10s, 15 reps" is two slots; "AMRAP, rest 10s, AMRAP" is two open-rep slots. No cluster-vs-rest-pause branching.

Authoring ergonomic shorthand (e.g. "cluster into 4 sub-sets of 5 with 20s intra") can be added later as an authoring-surface sugar that desugars to multi-slot before hitting the prescription JSON — but the wire format and runtime both see explicit slots.

## The driver's iteration model

A driver consumes the `ExecutionPlan` as a state machine. The iteration is hierarchical:

```
for block_repeat_index in 0 ..< block.block_repeat:
  (run block.block_timer if present)
  for set_in_block in block.sets:
    for set_repeat_index in 0 ..< set_in_block.set_repeat:
      execute_set(set_in_block, block_repeat_index, set_repeat_index)
      (if set.work_target is non-empty, emit set_result row)
  (if block.work_target is non-empty, emit block_result row)
```

`execute_set` varies by `timing × traversal`. The driver doesn't do anything specific to the legacy 12 timing modes — it dispatches on `(timing.mode, traversal)`. The section does not define every dispatch cell; it defines the contract.

### Legal `(timing × traversal)` cell matrix

Authored sets must land in a legal cell. Ingest rejects workouts whose sets specify illegal combinations.

| timing ↓ / traversal → | `sequential` | `round_robin` | `amrap` |
|---|---|---|---|
| `set_bounded` | **legal (default)** — the base straight-sets/superset case; athlete commits each slot; set ends after last slot in each repeat. | **legal** — N-round inferred from slot completion targets (one reps target on each slot); set ends when all slots are fully traversed. | **REJECT** — AMRAP with no cap is ambiguous; author must use `cap_bounded` or `target_bounded`. |
| `time_bounded` | **legal** — EMOM stations in order; one slot row per slot per interval; `timing.params.rounds` drives set-end. | **legal** — alternating stations within interval; each slot commits once per interval. | **legal** — EMOM-structured AMRAP; rounds counted across intervals; set ends at interval-limit. |
| `cap_bounded` | **legal** — for-time with cap at set level; set ends on completion of all slot-repeats or cap, whichever first. Requires set-level `{(duration, open, observation)}` work_target. | **legal** — circuit with outer cap; behaves like `cap_bounded × sequential` with round-robin traversal within the cap window. | **legal** — AMRAP; rounds cycle through slots under cap. **Requires** set-level `{(rounds, open, observation)}` work_target. |
| `target_bounded` | **legal** — "work until 100 total reps across slots" or "work until RPE ≥ 9"; driver polls target after each slot commit. | **legal** — target-bounded with alternating-slot traversal; same polling. | **REJECT** — AMRAP semantics conflict with target_bounded (AMRAP is its own termination). Authors should use `cap_bounded × amrap` instead. |

Cell semantics:

- **`set_bounded × sequential`** (the default): Driver walks slots in order; each slot commits a slot row when the athlete taps done; `post_rest_sec` is honored between slots; at end of slots, the set instance ends.
- **`set_bounded × round_robin`**: Walks slots N times in alternating order; N is derived from slot completion targets. If slots have differing reps-per-round, authoring is rejected — round_robin assumes congruent slot targets.
- **`time_bounded × sequential`**: EMOM; `timing.params.interval_sec` drives set-end cadence. One slot row per slot per interval; if multiple slots per set, the set plays through sequentially within the interval. `timing.params.rounds` defines the set's total intervals.
- **`time_bounded × round_robin`**: Alternating EMOM; each interval cycles to the next slot, one commit per interval.
- **`time_bounded × amrap`**: EMOM-AMRAP; within each interval, slots cycle amrap-style; rounds carry across intervals (observer metric on set_result).
- **`cap_bounded × sequential`**: For-time at the set level; set ends on either completion of all slot-repeats or cap.
- **`cap_bounded × round_robin`**: Circuit under cap; same as `cap_bounded × sequential` but with round-robin traversal within the cap window.
- **`cap_bounded × amrap`**: The canonical AMRAP; set continues until cap, slots cycle, rounds are counted on the set_result.
- **`target_bounded × sequential`**: Work until the target hits (metric target like "100 total reps" or stimulus threshold like "RPE ≥ 9"); driver polls after each slot commit. Slot rows accumulate; final row records the crossing value for stimulus-threshold targets.
- **`target_bounded × round_robin`**: Same polling, alternating slots.

Illegal cells reject at ingest, not at runtime. An ingest-time validator enumerates the (timing, traversal) cells above and rejects `set_bounded × amrap` and `target_bounded × amrap` with a precise error pointing to the offending set.

### Resolving Q-I — completion vs observation dispatch

**At seed time, each slot's `work_target` is partitioned into `completion_metrics` and `observation_metrics`. The driver's done-signal evaluates only `completion_metrics`.**

Concrete rule:
- If at least one `completion_metric` has a prescribed value (single or range) — the slot's "done" condition is that value-form being satisfied:
  - `single`: exact match or achieve-or-exceed (depends on metric — distance/duration/reps = achieve; rounds = count).
  - `range`: athlete commits somewhere in the range; driver accepts any in-range value.
  - `open`: athlete commits; the value is recorded without prescribed comparison.
- If a completion metric is `open`, the driver waits for athlete commit (the "done" button on the slot).
- Observation metrics are recorded at commit time without influencing the done-signal.
- If no completion metric is prescribed (all are observation), the slot is entirely athlete-commit-driven; the driver still records everything at commit.

Example: 1km run with `{(distance, single 1000, completion), (duration, open, observation)}` — driver ends slot when 1000m is logged (distance is completion-metric). Duration is recorded alongside.

Example: Tabata 20s round with `{(reps, open, observation)}` — no completion-metric; the set's time-bounded timing ends the slot (the clock is authoritative). Reps are recorded on interval-end.

### Resolving Q-M — the three index fields (unified definition)

The three index fields compose to uniquely identify a slot commit. Each has one meaning, stated once:

- **`block_repeat_index`** — which iteration of `block.repeat` produced this row. Range: `0..block.repeat-1`. Always set on slot, set_result, and block_result rows.
- **`set_repeat_index`** — which iteration of `set.repeat` produced this row, within the current `block_repeat_index`. Range: `0..set.repeat-1`. Always set on slot and set_result rows. On block_result rows, it is `0` (reserved).
- **`set_index`** — commit sequence number within the (`block_repeat_index`, `set_repeat_index`) instance of this set. Range: `0..∞`. Starts at 0 for each new set-instance; increments on each slot commit within that instance; **resets** when `set_repeat_index` advances.

**Worked index behavior by pattern:**

| Pattern | Set composition | Indices on slot rows |
|---|---|---|
| Straight sets, 4 × 8 bench | 1 set, 1 slot, `set.repeat: 4` | Four rows: `(0, 0, 0)`, `(0, 1, 0)`, `(0, 2, 0)`, `(0, 3, 0)` — `set_index` is always 0 because each set-instance has one commit. |
| Superset, 3 rounds of bench+row | 1 set, 2 slots, `set.repeat: 3` | Six rows: bench `(0,0,0)`, row `(0,0,1)`, bench `(0,1,0)`, row `(0,1,1)`, bench `(0,2,0)`, row `(0,2,1)`. `set_index` orders slot commits within each set-instance; resets at each `set_repeat_index` boundary. |
| AMRAP, cap_bounded × amrap | 1 set, N slots, `set.repeat: 1`, driver cycles | Many rows all at `set_repeat_index: 0`; `set_index` is the monotonic commit counter from 0 upward; at cap, the set emits a set_result and `set_index` is not reused. |
| EMOM, time_bounded 10×60s | 1 set, 1 slot, `set.repeat: 1`, `timing.rounds: 10` | Ten rows all at `(0, 0, 0)..(0, 0, 9)` — the EMOM interval is `set_index`-driven, not `set_repeat_index`, because `set.repeat` is 1. Canonical form for EMOM is the `timing.rounds`-driven form. The alternative encoding (`set.repeat: 10`) is rejected at ingest — EMOM intervals belong in `timing.params.rounds`, not in `set.repeat`. |
| CrossFit compound, block.repeat 5 with AMRAP+run | 1 block, 2 sets, `block.repeat: 5` | Per block iteration k ∈ 0..4: AMRAP set emits slot rows `(k, 0, 0..N)` and a set_result `(k, 0)`; run set emits one slot row `(k, 0, 0)`. |

(Reading the table: each row cell is `(block_repeat_index, set_repeat_index, set_index)`.)

**Deterministic ids.**

- Slot row: `uuid(slot_id, block_repeat_index, set_repeat_index, set_index, role="slot")`.
- Set_result row: `uuid(set_id, block_repeat_index, set_repeat_index, role="set_result")`. (No `set_index` — aggregate is one-per-instance.)
- Block_result row: `uuid(block_id, block_repeat_index, role="block_result")`. (No `set_repeat_index` or `set_index`.)

The id formulas guarantee distinct ids across all repeat instances.

### Resolving Q-L — AMRAP partial-station accounting

**Decision: option (b). The `set_result` row carries round-level aggregates; per-station partial attribution lives on the final partial slot row.**

When an AMRAP cap hits mid-pullup in round 8:

- Slot rows for rounds 1..7 (fully completed cycles): one pushup row + one pullup row each (14 rows total for a two-slot AMRAP).
- Round 8 partial: pushup row with `set_index: 14, reps: 10` (athlete finished the pushup station); pullup row with `set_index: 15, reps: 4` (athlete had 4 when cap hit). The partial-station reps live on the pullup slot row itself.
- `set_result` row: `rounds: 7, reps: 4, duration_sec: 300`.

The `reps: 4` on the set_result is the partial-round aggregate; the station attribution comes from the slot row's `slot_id` (which slot the partial happened on). No new column, no reference field.

If the user edits the set_result to "actually I got 8 rounds exactly," they set `rounds: 8, reps: 0` on the aggregate; the final slot row (the partial pullup) becomes a correction target — they either edit it to `reps: 10` (full round) or delete it (skip the row). Aggregate-correction UI makes this flow explicit.

## Log event emission

The driver emits `SetLogEvent` records; the reducer converts them into `SetLog` rows and the push queue persists. One event type per role.

### `SetLogEvent.slot`

Emitted on slot commit (or on time_bounded interval-end for EMOM-style).

```
SlotLogEvent {
  slot_id: UUID
  set_id: UUID
  block_id: UUID
  block_repeat_index: Int
  set_repeat_index: Int
  set_index: Int
  performed_exercise_id: UUID?   -- swap context, omitted for no-swap
  reps: Int?
  weight: Double?
  weight_unit: "kg"|"lb"|nil
  duration_sec: Double?
  distance_m: Double?
  stimulus_values: { rir: Int?, rpe: Int? }   -- only for real stimulus-type columns
  telemetry: { hr_avg_bpm: Int?, hr_max_bpm: Int?, cadence_avg_spm: Int?, motion_samples_ref: String? }
  is_warmup: Bool
  skipped: Bool
  notes: String?
  started_at: DateTime?
  completed_at: DateTime
}
```

Deterministic id: `uuid(slot_id, block_repeat_index, set_repeat_index, set_index, role="slot")`. Same-UUID upsert on push + local cache.

### `SetLogEvent.set_result`

Emitted when a set with non-empty `set.work_target` finishes. Required fields:

```
SetResultLogEvent {
  set_id: UUID
  block_id: UUID
  block_repeat_index: Int
  set_repeat_index: Int
  rounds: Int?
  reps: Int?              -- partial-round extras for AMRAP
  duration_sec: Double?   -- for for-time sets
  completed_at: DateTime
}
```

Deterministic id: `uuid(set_id, block_repeat_index, set_repeat_index, role="set_result")`.

### `SetLogEvent.block_result`

Emitted when a block with non-empty `block.work_target` finishes.

```
BlockResultLogEvent {
  block_id: UUID
  block_repeat_index: Int
  rounds: Int?
  duration_sec: Double?
  completed_at: DateTime
}
```

Deterministic id: `uuid(block_id, block_repeat_index, role="block_result")`.

### Stimulus capture on slot rows

`effective_stimuli` on the slot tells the driver which stimulus inputs to surface:
- **Interactive stimuli** (RIR, RPE): one interactive input per slot commit. The current execution contract carries one `loggedRir` slot; extending to multiple interactive-stimuli simultaneously is a named downstream extension.
- **Derived stimuli** (HR zone): no input; telemetry columns are captured automatically from the sensor fusion layer; zone is computed on read.

When the slot has no interactive stimulus attached, the commit surface skips the stimulus input entirely. When the slot has an `rir` stimulus, the commit surface shows the RIR input with the authored target as a cue. The stimulus target itself is not stored on the log; it lives in the prescription and re-reads at display time.

### Autoreg proposal flow

After a slot row is committed, for each stimulus on the slot's `effective_stimuli` that has an `autoreg` rule set:

1. Driver invokes `Autoreg.propose(stimulus, observed_value, target_value, rule_set)`.
2. If the proposal adjusts load, the driver writes the adjustment to remaining `SetPlan` entries within the same set instance (per `autoreg.apply_to: "remaining_sets_in_set"`).
3. Subsequent slot rows in the same set commit at the adjusted load.
4. The proposal is not a log row; the *effect* surfaces as the adjusted `weight` on later slot rows.
5. If the proposal is `.manual`-overridden by the athlete (user types a load that differs from the autoreg suggestion), the override records on the SetPlan; the committed slot row's weight reflects the override.

Autoreg proposal audit (Q-K) stays deferred per D2.

## Correction semantics

History correction overwrites existing log rows using deterministic id.

### Slot-row correction

The three bug-fix invariants from the EditSetSheet fix hold:
- `side` is not editable from the sheet; authored identity owns it.
- Marking a slot skipped preserves `weight_unit`.
- Toggling from skipped → performed requires at least one metric (reps / weight / duration / distance) before save.

Correction extends the primitive mapping: a slot authored with `{(distance, completion), (duration, observation)}` shows both fields in the correction sheet, whether the row is a cardio or a carry. No union-subset shell; composition drives the sheet.

### Aggregate-row correction (`set_result`, `block_result`)

Aggregate rows correct via a separate sheet layout. Fields shown:
- `rounds` (if the aggregate's `work_target` includes a rounds metric).
- `reps` (partial-round aggregate).
- `duration_sec` (for for-time / timed aggregates).
- `notes`.

When a user edits an aggregate, the underlying slot rows are not automatically mutated, and conversely editing a slot row does not auto-recompute the aggregate. Aggregates are authoritative for their metric per the section-2 rule. Aggregate-correction UI can offer links to the partial-round slot rows when they exist, but the athlete is responsible for deciding which truth (aggregate or slot-sum) to correct.

### Mid-session correction (during live execution)

A user editing a committed slot row during the same session writes through the correction flow — same deterministic id, same overwrite semantics. The driver does not special-case in-session edits vs post-session edits.

### Swap-then-correct ordering

If a slot is swapped after some slot rows have already committed, the earlier rows retain `performed_exercise_id` pointing to the pre-swap exercise. Later rows use the alternative's `exercise_id`. Correcting a pre-swap row preserves the pre-swap performed identity.

### Correction vs autoreg

If a user corrects a slot row's weight retroactively, autoreg does not re-propose for subsequent rows — the proposal at the time is what it was. This matches today's "no retroactive re-compute" convention and keeps the history stable.

## runtime-resolution.md open questions

**Q-N. Cross-set autoreg scope.** Today's `apply_to: "remaining_sets_in_set"` adjusts within one set-instance. Should autoreg also have `"remaining_sets_in_block"` (adjust across future sets in the same block for repeating supersets)? Not a blocker; nameable as an authoring-surface addition if a real prescription asks for it.

**Q-P. `ExecutionPlan` invalidation on prescription edits.** If the workout prescription is edited server-side mid-session (rare but possible via direct sync push), does the `ExecutionPlan` rebuild? Decision: no — the executing workout is the snapshot pulled at session start; server-side edits arrive on next pull and re-seed the plan then. cutover.md pinpoints the one-shot rebuild on app upgrade.
