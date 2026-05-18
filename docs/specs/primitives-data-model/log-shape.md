---
title: Log shape — set_log rows under the primitive model
status: accepted — spec
last_reviewed: 2026-05-17
parent: ../primitives-data-model.md
purpose: Canonical set_log row shape, three log roles (slot / set_result / block_result), deterministic UUID composition for idempotent upsert, per-stimulus typed columns, overlay columns, write semantics at slot / set / block completion. Ten worked examples showing concrete log rows.
---

# Log shape

## Scope

Given the authoring shape above, what does the app write to `set_log` when work happens? This aspect resolves Q-E (stimulus columns) and Q-G (derived stimuli compute-on-read), pins down slot-level and set/block-level outcome semantics, and shows the log rows each of the ten worked examples produces.

**In scope:**
- The `set_log` row shape under the primitive model
- How each authoring primitive maps to one or more log columns
- Set-level and block-level outcome storage (where AMRAP rounds-completed and for-time total-duration live)
- Stimulus value storage: columns per real stimulus type
- Derived-from-telemetry stimulus resolution (compute on read)
- Overlay columns (skipped, notes, warmup, `side` as reserved, weight unit)
- Write semantics at slot completion, set completion, block completion
- Ten worked examples showing concrete log rows

**Out of scope:**
- Runtime resolution — how the driver walks authored JSON to decide when to write what (runtime-resolution.md)
- Migration from today's `set_log` (cutover.md)
- Audit-grade edit provenance (D2). Log shape here stays same-row overwrite.
- App-side publisher for workout preview edits. Deferred.

## The canonical `set_log` row

One `set_log` row is one persisted observation of work, at one of three roles: a slot observation, a set-level observation (AMRAP rounds, for-time duration for a set), or a block-level observation (block-level aggregates).

```
id: UUID                      -- deterministic per (scope_id, set_index, role) — idempotent upsert
role: "slot" | "set_result" | "block_result"
                              -- role discriminator. default "slot".
slot_id: UUID | NULL          -- slot this log came from. NULL for set_result / block_result. Opaque UUID, not FK-enforced.
set_id: UUID | NULL           -- parent set. Required on slot and set_result rows (may be NULL for orphans). Opaque.
block_id: UUID | NULL         -- parent block. Required on set_result (denormalized) and block_result rows (may be NULL for orphans). Opaque.
workout_id: UUID | NULL       -- the workout.id this row belongs to. Denormalized; populated on all post-cutover rows and on V2→V3 denormalized rows; may be NULL on deep pre-V3 orphans. Survives orphaning where already populated.
planned_exercise_id: UUID | NULL  -- exercise authored on the slot at log time. Denormalized; survives slot orphaning.
performed_exercise_id: UUID?  -- mid-workout swap context; populated on slot rows only

set_index: Int                -- commit order within the (block_repeat_index, set_repeat_index) instance.
                              -- Starts at 0, increments on each slot commit within that set-instance.
                              -- Straight sets with one slot: always 0 (one commit per instance).
                              -- Superset with N slots: 0..N-1 per instance.
                              -- AMRAP: unbounded; counts commits across the AMRAP's lifetime.
                              -- Not "flat row order across repeats" — resets at each set_repeat boundary.
set_repeat_index: Int         -- which iteration of set.repeat produced this row (0..set.repeat-1).
                              -- For set_result and block_result rows, the repeat index of the produced scope.
block_repeat_index: Int       -- which iteration of block.repeat produced this row (0..block.repeat-1).

-- outcome metrics (all nullable; what was measured depends on the effective work_target)
reps: Int | NULL
weight: Double | NULL
weight_unit: "kg" | "lb" | NULL
duration_sec: Double | NULL
distance_m: Double | NULL
rounds: Int | NULL            -- only meaningful on set_result rows for round-counting sets, or block_result for round-counting blocks

-- stimulus values (one column per real stimulus type; nullable when not captured)
rir: Int | NULL               -- 0..5, existing
rpe: Int | NULL               -- 1..10, added IF AND ONLY IF the authoring surface introduces an rpe stimulus (Q-A)
-- no hr_zone column — zone is derived from hr_avg_bpm + user_parameters-as-of-completed_at

-- raw telemetry (canonical source of truth for derived stimuli)
hr_avg_bpm: Int | NULL
hr_max_bpm: Int | NULL
cadence_avg_spm: Int | NULL
motion_samples_ref: String | NULL

-- overlays
is_warmup: Bool                -- default false; authored at slot level, flows to log
skipped: Bool                  -- default false
side: "left" | "right" | "bilateral"  -- default bilateral; reserved per D1, not user-authored
notes: String | NULL

-- timestamps
started_at: DateTime | NULL
completed_at: DateTime         -- required
```

### Changes from today's `set_log`

- **Renamed:** `workout_item_id` → `slot_id`.
- **Added:** `set_id`, `block_id` (both nullable; used for aggregate queries and for set_result/block_result rows), `role` discriminator, `rounds` column, `set_repeat_index`, `block_repeat_index`.
- **Potentially added:** `rpe` column (Q-A — only if a real prescription authors an RPE stimulus).
- **Changed:** `slot_id` becomes nullable (NULL on set_result and block_result rows).
- **Not added:** no `stimuli_json` blob. No `hr_zone` column. Typed columns per real stimulus; derived values compute on read.

### Resolving Q-E — stimulus storage is columns-per-type

**Decision: columns per stimulus type, added when the type becomes real.** RIR has `rir` today. If the authoring surface introduces RPE, a migration adds `rpe` (1..10 check). Third stimulus earns its own column migration.

Rationale:
- **Typed constraints.** `rir` has a `0..5` check; a blob loses it.
- **Queryability.** SQL > JSON extraction for history/analytics.
- **Complete-cutover philosophy.** Each stimulus that earns a column earns a cutover — friction enforces "is this stimulus real" before we wire it.

Trade-off: adding a stimulus is a schema migration. Given stimulus types are discrete and rare (2-3 foreseeable), the friction is worth the constraint.

### Resolving Q-G — derived stimuli compute on read against current user_parameters

**Decision: derived stimulus values are computed at DISPLAY time from raw-telemetry columns against the current `user_parameters` latest value.** No `hr_zone` column is added; no historical `user_parameters` lookup is required.

Concretely: when a slot row is committed, the driver already records `hr_avg_bpm`. To surface "which zone was that?" in the UI, the app computes `zone(hr_avg_bpm, max_hr_bpm_now)` where `max_hr_bpm_now` reads from the current `user_parameters` latest value (the existing sync contract returns latest-per-key; [v2-architecture.md:300](../v2-architecture.md)). This is a display-time computation, not a stored value.

**Trade-off accepted:** if the user tests a new `max_hr_bpm` tomorrow, the zone label displayed for yesterday's run will *re-interpret* under the new max_hr. This is a deliberate simplification. A compute-on-read pattern that uses `user_parameters`-as-of-`completed_at` would preserve "yesterday's zones stay correct" but requires an append-only `user_parameters` history mirror on the app — a sync-contract change that has no real use case today (Eric doesn't re-review HR zones for past runs against old max_hr). That work is deferred.

**Canonical parameter key schema (pinned).** Keys used by this model:

| Key | Value type | Used by |
|---|---|---|
| `max_hr_bpm` | int | HR zone derivation (display-time against current value) |
| `bodyweight_kg` | float | Relative load with `unit: "bodyweight"` (seed-time resolution) |
| `one_rep_max_<exercise_id>_kg` | float | Relative load with `unit: "1rm"` (seed-time resolution) |

**Relative-load resolution (Q-F / Q-J) still uses `current-local-value-at-seed-time`.** When the app seeds a pulled workout into an `ExecutionPlan`, `(0.85, "1rm", relative)` looks up `one_rep_max_<exercise_id>_kg` from the latest locally mirrored `user_parameters` row and caches the absolute kg on `ExecutionSlot.load_kg`. The optional `resolved_from_user_param_id` pins the source row's UUID IF it's available from the local mirror — but the field is nullable. If the sync only returned latest without exposing the source id, `resolved_from_user_param_id` stays nil; the cached absolute is still correct for session execution. Audit of "what 1RM did this workout use?" still works via the cached `load_reference.value`.

**If append-only `user_parameters` sync becomes load-bearing later**, it's a separate cutover: add pull-contract change + app-side history mirror + migration. Not part of THIS plan.

## Per-primitive mapping

How each authoring-side primitive appears on a log row.

- **Exercise →** referenced through `slot_id`. `performed_exercise_id` written only on mid-workout swap.
- **Structure →** no log field. Drives how many rows get written at each role:
  - Slot rows: one per slot commit within a `(block_repeat_index, set_repeat_index, set_index)` coordinate.
  - Set_result rows: one per `(set_id, block_repeat_index, set_repeat_index)` when the set carries a set-level work_target. A set that repeats N times within a block iteration produces N set_result rows per block iteration.
  - Block_result rows: one per `(block_id, block_repeat_index)` when the block carries a block-level work_target. A block that repeats K times produces K block_result rows.
- **Timing →** drives row cadence:
  - `set_bounded`: one slot row per slot per commit.
  - `time_bounded`: one slot row per interval (EMOM minute).
  - `cap_bounded`: slot rows per commit until cap; set_result row at cap.
  - `target_bounded` with metric target: slot rows until target; final row records crossing.
  - `target_bounded` with stimulus threshold: slot rows until stimulus crosses; final row records crossing value.
- **Work target →** outcome columns:

| Authoring metric | Log column |
|---|---|
| `reps` | `reps` |
| `duration` | `duration_sec` |
| `distance` | `distance_m` |
| `rounds` | `rounds` (on set_result / block_result rows) |
| `completion` | no column — row existence is the marker |
| `load_carried` | `weight` + `weight_unit` |

  The `role` flag (`completion` vs `observation`) doesn't change what's stored — both get written. It changes driver behavior at log time: `completion` metrics gate slot/set-end; observation metrics are recorded alongside.

- **Load →** `weight` + `weight_unit` on slot rows. At seed time, `relative` unit-types resolve to absolute kg via `user_parameters`; the log writes the resolved absolute. `implicit-bodyweight` stores `weight: NULL, weight_unit: NULL`.

- **Stimulus →** per-type columns + raw telemetry. `rir` → `rir` column. `rpe` (when introduced) → `rpe` column. `hr_zone` → no column; compute from `hr_avg_bpm` at read. Stimulus values are always nullable.

- **Autoreg rules →** nothing on the log. Consumed at log time by the driver; the proposal mutates future `SetPlan` state. The *effect* shows up as adjusted `weight` on subsequent slot rows.

## Set-level and block-level outcomes

AMRAP rounds-completed, for-time total-duration, and multi-round block aggregates are observations at the set or block level, not at a slot.

**Decision: `set_result` row when the set has a set-level work_target; `block_result` row when the block has a block-level work_target. Both live in `set_log` under the `role` discriminator.**

### Shape of a set_result row

For a 5-minute AMRAP set that produced 7 full rounds + 4 pullups into round 8:

```json
{
  "id": "<deterministic-uuid>",
  "role": "set_result",
  "slot_id": null,
  "set_id": "<amrap-set-uuid>",
  "block_id": "<parent-block-uuid>",
  "block_repeat_index": 0,
  "set_repeat_index": 0,
  "set_index": 0,            // always 0 for aggregate rows; reserved
  "rounds": 7,
  "reps": 4,                 // partial-station extras in round 8
  "duration_sec": 300,
  "completed_at": "..."
}
```

**Deterministic id for set_result:** `uuid(set_id, block_repeat_index, set_repeat_index, role="set_result")`. Block and set repeat indices are mandatory in the id so repeated set-instances emit distinct aggregate rows rather than overwriting each other.

Per-slot rows for the completed rounds still exist (21 pushup/pullup slot rows for 7 full rounds + 1 slot row for the partial pullup). The set_result row is the explicit aggregate.

### Shape of a block_result row

For a block with a block-level work_target (e.g. "for-time 5 rounds, cap 15 min", block-level `{(duration, open, observation)}`):

```json
{
  "id": "<deterministic-uuid>",
  "role": "block_result",
  "slot_id": null,
  "set_id": null,
  "block_id": "<ft-block-uuid>",
  "block_repeat_index": 0,
  "set_repeat_index": 0,     // always 0; reserved
  "set_index": 0,            // always 0; reserved
  "duration_sec": 840,        // finished in 14:00 under the 15-min cap
  "completed_at": "..."
}
```

**Deterministic id for block_result:** `uuid(block_id, block_repeat_index, role="block_result")`. `block_repeat_index` is mandatory in the id. If the block repeats, each iteration emits its own block_result row.

### Why one table with a role discriminator

- **Explicitness.** "AMRAP rounds = 7" is a real observed outcome. Storing as an explicit row makes it queryable and editable directly, not reverse-engineered from per-slot rows.
- **Compound outputs.** For-time + AMRAP cap carry both total duration and partial-station extras; one row cleanly carries both.
- **Minimal schema impact.** One role column, nullable `slot_id` / `set_id` / `block_id`, one `rounds` column.
- **Editor composition.** Aggregate-correction UI is a different visual surface than per-slot correction. Keeping both in `set_log` with `role` preserves one cache API; the UI branches on `role`.

### Aggregate authority rule (resolving Q-O)

**Decision: aggregate rows are authoritative observations for the metrics they carry. Queries for aggregate-level metrics MUST read aggregate rows; queries MUST NOT derive competing aggregate totals by summing slot rows.**

Concretely:

- For a block with a block-level `{(duration, open, observation)}` work_target, "block duration" is read from the `block_result.duration_sec`. Not from `max(slot.completed_at) − min(slot.completed_at)`.
- For a set with a set-level `{(rounds, open, observation)}` work_target, "rounds completed" is read from `set_result.rounds`. Not from counting slot rows.
- For slot-level metrics (per-slot reps, per-slot weight), queries sum/read slot rows.
- If an aggregate row is missing for a scope that has an aggregate work_target, the aggregate is unknown — queries MUST NOT fall back to deriving from slot rows. This preserves the invariant that aggregates are user-observed, not computed.

**Correction flow implications.** Editing an aggregate row is a user-observed correction — if the athlete tells the system "I actually got 8 rounds, not 7," the aggregate changes and slot rows do not. If the athlete edits a slot row retroactively (e.g. "I actually did 12 reps in round 3, not 10"), the aggregate row does NOT auto-recompute; the user is responsible for correcting the aggregate separately if they want both to reflect the new truth. This matches the "no retroactive re-propose" convention used for autoreg and is consistent with D2 (audit-grade provenance deferred).

**Why not auto-recompute.** Auto-recomputing the aggregate on slot edits reintroduces a dual-truth problem (which edit wins when both happen?) and erodes the aggregate's "observed by the athlete at end-of-set" semantic. Explicit user responsibility is cleaner.

**Why not "slot rows win if aggregate is missing."** A missing aggregate means the prescription didn't prescribe one, so there's no expected value to fall back to. Computing one ad-hoc would mask whether an aggregate *should* have been captured but wasn't.

## Overlays on the log

- **`skipped`** — boolean, default false. Marking a slot skipped clears outcome + stimulus values (to NULL) but **preserves `weight_unit`** (the earlier bug fix).
- **`notes`** — text, free-form, per-row.
- **`is_warmup`** — boolean. Warmup ramps are authored as multiple slots with `is_warmup: true`; the flag flows from slot authoring to log.
- **`side`** — reserved per D1. The editor does not author it; round-trips from authoring through the log. Per-side work is authored as separate exercise identities.
- **`.manual` flag** — **deferred per D2.** No `set_log.manual` column added. Corrections overwrite in place. Promoted to audit-grade later with `set_log.updated_at` and field-diff telemetry as one structural unit.
- **`weight_unit`** — per-row (not prescription-scoped). Authored Load resolves at seed; unit flows to the log. Preservation on skip enforced per bug fix.

## Write semantics

### On slot completion

1. Driver produces a `SetLogEvent` with observed values + stimulus value(s).
2. Reducer stamps the `SetPlan`, computes deterministic `SetLog.id` from `(slot_id, set_index, set_repeat_index, block_repeat_index, role="slot")`, enqueues for push.
3. Local cache writes the row with same id. Same-UUID upsert preserves history integrity on server round-trip.
4. For autoreg-coupled RIR slots, driver additionally calls `Autoreg.propose` using the RIR stimulus's rule set; proposal mutates remaining `SetPlan` state, not the current log row.

### On set completion (set_result row)

If the set carries a set-level `work_target`:

1. Driver synthesizes the set-level outcome: AMRAP → `(rounds, partial reps, duration_sec)`; for-time at set level → `(duration_sec)`.
2. Produces a `SetLogEvent` with `role="set_result"`, `slot_id=null`, `set_id=<set>`, `block_id=<parent>`, `block_repeat_index` and `set_repeat_index` set, outcome columns per set.work_target.
3. Deterministic id: `uuid(set_id, block_repeat_index, set_repeat_index, role="set_result")`.
4. Push + local cache write same as slot rows.

If the set has no set-level work_target, no set_result row is written. A set that repeats emits one set_result per `set_repeat_index` per `block_repeat_index`.

### On block completion (block_result row)

If the block carries a block-level `work_target`:

1. Driver synthesizes the block-level outcome at the end of each `block_repeat_index`.
2. Produces `SetLogEvent` with `role="block_result"`, `slot_id=null`, `set_id=null`, `block_id=<block>`, `block_repeat_index` set, outcome columns per block.work_target.
3. Deterministic id: `uuid(block_id, block_repeat_index, role="block_result")`.
4. Push + local cache write.

If block has no block-level work_target, no block_result row is written. A block that repeats emits one block_result per `block_repeat_index`.

### On correction (existing log row)

History correction overwrites the same row (deterministic id). Three bug-fix invariants hold: `side` round-trips but is not editable; skip preserves `weight_unit`; skipped→performed requires at least one metric.

Aggregate rows (`set_result`, `block_result`) correct via aggregate-specific sheets (composition TBD in runtime-resolution.md).

### On autoreg proposal accepted

No log write. Autoreg's effect shows up when the next slot row completes at adjusted load — the `weight` on that row carries the adjusted value.

## Worked examples (log rows per prescription)

### 1. Straight sets, loaded strength (4 × 8 bench @ 185 lb, RIR 2)

Four slot rows, same `slot_id`, `set_repeat_index` 0..3 (`set_index` 0..3 mirrored):

```
{role: "slot", slot_id: bench, set_repeat_index: 0, reps: 8, weight: 185, weight_unit: "lb", rir: 2, ...}
{role: "slot", slot_id: bench, set_repeat_index: 1, reps: 8, weight: 185, weight_unit: "lb", rir: 2, ...}
{role: "slot", slot_id: bench, set_repeat_index: 2, reps: 8, weight: 185, weight_unit: "lb", rir: 1, ...}    // undershoot
{role: "slot", slot_id: bench, set_repeat_index: 3, reps: 8, weight: 182.5, weight_unit: "lb", rir: 2, ...}  // autoreg
```

No set_result (no set-level work_target). No block_result.

### 2. Superset (3 rounds of bench 8 + row 8, RIR 2)

Six slot rows (two slot_ids × set_repeat 0..2), interleaved by commit timestamp. No set_result, no block_result.

### 3. Percent of 1RM (5 × 8-12 @ 80% 1RM, RIR 1-2)

Five slot rows. Load resolved at seed to absolute kg from `user_parameters.one_rep_max_<exercise_id>_kg × 0.80`. Log writes resolved value (e.g. `weight: 96, weight_unit: "kg"`). Stimulus captured within authored range.

### 4. Continuous cardio (30 min, zone 2)

One slot row:

```
{role: "slot", slot_id: run, duration_sec: 1830, distance_m: 4500, hr_avg_bpm: 142, hr_max_bpm: 155, ...}
```

HR zone NOT stored. At read: `zone(142, user_params.max_hr_at(completed_at))` → zone 2.

### 5. Intervals (4 × 1km @ 5:00 pace, 2min rest)

Four slot rows (one slot_id, set_repeat 0..3), distance (completion) + duration (observation) each. Pace = `distance_m / duration_sec` at display.

### 6. Weighted carry (3 × 60 lb for 80 m)

Three slot rows. Compound outcome: `distance_m` (completion) + `weight`/`weight_unit` (load held) + `duration_sec` (observed).

### 7. EMOM (10 min of 3 hang cleans @ 135 lb)

Ten slot rows, all at `(block_repeat_index: 0, set_repeat_index: 0, set_index: 0..9)` — the EMOM's interval count lives in `timing.params.rounds`, so `set_index` increments per interval within the single set-instance. No stimulus. No set_result / block_result.

### 8. CrossFit compound (5 rounds of [5-min AMRAP of pushup/pullup + 1 km run])

Per block_repeat (0..4):
- Per-round slot rows for pushups and pullups (one per 10-rep commit) during the 5-minute AMRAP.
- Final partial-round slot row if cap hits mid-round.
- One `set_result` row at AMRAP end:
  ```
  {role: "set_result", set_id: amrap-set, block_id: compound, block_repeat_index: 0,
   rounds: 4, reps: 6, duration_sec: 300, ...}
  ```
- One slot row for the 1km run.

Per-slot history preserved; per-AMRAP aggregate is explicit. Block has no block-level work_target → no block_result (the 5-rounds is structural via `block.repeat`).

### 9. For-time with cap (5 rounds burpee+run, cap 15 min)

Ten slot rows (two slots × set_repeat 0..4). One block_result:

```
{role: "block_result", block_id: ft-block, duration_sec: 840, ...}   // under 15-min cap
```

The block-level timer + block.work_target `{(duration, open, observation)}` produces the aggregate.

### 10. 1RM test (warm-up ramp + test attempt)

Warm-up block: 5 slot rows (one per ramp step), each with `is_warmup: true`, ascending weight.
Test block: 1 slot row:

```
{role: "slot", slot_id: squat-test, reps: 1, weight: 315, weight_unit: "lb", is_warmup: false, ...}
// overshot the 295 estimate
```

No special "test" handling at log level — a strength slot row.

## Current gaps

- `PDM-GAP-003`: Log/result roles must stay query-safe during implementation.
  Slot rows, set-result rows, and block-result rows are distinct facts; history
  and analytics must not derive competing aggregates from slot rows when an
  aggregate result row is the authored source.

- `PDM-GAP-006`: Metric-driven partial-result capture and completion summaries
  are not complete for non-rep slots. Simulator QA on 2026-05-17 showed a
  cap-bounded AMRAP ending on a 1000 m run station, but the aggregate result
  sheet captured the partial as `Run 1 reps` instead of a distance value. A
  follow-up primitive stress pass showed the same class of gap across distance,
  duration, and carried-load work: a for-time row summary preserved elapsed
  time but not the prescribed distance, and a loaded carry completion preserved
  distance but not carried load. The cutover must drive aggregate,
  partial-result, and completion-summary controls from each slot's
  work_target metrics, not from a reps-only or single-primary-metric default.

## log-shape.md open questions

**Q-I. Seed-time expansion of work_target metric roles into driver hooks.** Resolved in runtime-resolution.md: driver reads role flag at seed time; set-end gates on `completion` metrics only.

**Q-J. Relative-load resolution timing.** Resolved in runtime-resolution.md (see Q-F above).

**Q-K. Autoreg proposal provenance.** Audit chain "why is slot 4 at 182.5 not 185?" recoverable via event log only today. Deferred per D2.

**Q-L. AMRAP partial-station accounting on set_result.** Resolved in runtime-resolution.md: option (b). The set_result carries round-level aggregates; per-station partial attribution lives on the final partial slot row at the same `set_repeat_index`, identified by its `slot_id`.

**Q-M. Index semantics on cross-slot traversal.** Pinned in runtime-resolution.md: `set_repeat_index` is per-set-instance (rows within a superset round share it); `set_index` is per-commit within that instance.
