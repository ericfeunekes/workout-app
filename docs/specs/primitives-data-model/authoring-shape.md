---
title: Authoring shape — prescription JSON wire format
status: accepted — spec
last_reviewed: 2026-05-17
parent: ../primitives-data-model.md
purpose: Wire format for workout / block / set / slot under the 7-primitive model. How each primitive serializes in JSON. Merge and override rules. Ten worked examples covering the common prescription patterns.
---

# Authoring shape


## Scope

This section defines the wire format for prescriptions under the primitive model. *Given an author who wants to express a workout using the 7 primitives, what JSON do they write?*

**In scope:**
- The shape of workout / block / set / slot at the wire level
- How each primitive appears in JSON
- Merge rules (library defaults, alternative overrides, hierarchy walk)
- Worked examples covering ten real prescription patterns

**Out of scope:**
- Set log schema (log-shape.md below) — what gets stored when work is logged
- Runtime resolution (runtime-resolution.md) — seed/log/correction-time walking of the hierarchy
- Migration (cutover.md) — cutover plan from today's per-timing-mode prescription shapes
- Components-as-primitives UI mapping — this is pure authoring shape, not display
- Execution-route behavior — drivers stay driver-owned; this proposal only changes what they *read*

## Node identity

Every block, set, and slot in the authored JSON carries a required `id: UUID`. Identity is load-bearing: it's the join key between authoring, execution plan state, log rows, and corrections. Without stable ids, the repo's idempotent-upsert invariant ([CLAUDE.md:101](../../../CLAUDE.md)) cannot hold across repulls.

**Generation rule.** Server generates ids at authoring time. The client never synthesizes node ids for the server's view; it only consumes them. When a client-side correction mutates fields *within* an existing node, the id persists; when a correction or re-authoring structurally replaces a node (e.g. splitting a block, inserting a new set, removing a slot), the new node gets a new id.

**Uniqueness scope.** All ids are UUIDs and globally unique by construction. Within a workout, no two blocks, sets, or slots share an id even across hierarchy levels.

**Persistence across repulls.** "Semantically in place" means the node occupies the same position and serves the same purpose in the authored tree even if its fields change. The table below spells out the rule per edit class so two implementations don't diverge on "preserve or rekey":

| Edit class | Example | Preserve id? |
|---|---|---|
| Load / stimulus / target change on a slot | "change bench target from 185 → 195 lb" | **Preserve slot id** |
| Exercise replacement on a slot (not via swap) | "replace bench with incline bench in the stored prescription" | **New slot id** — different movement is a different node semantically |
| Slot reorder within the same set | move slot 1 to position 2 | **Preserve slot ids** — ordering is set-property, not slot-identity |
| Slot added or removed from a set | insert a new slot mid-sequence | **New id for added slot**; surviving slots preserve ids |
| Slot's work_target metric changed (e.g. reps → distance) | author changes a rep-counted slot to a distance-counted slot | **New slot id** — the metric change redefines what the slot measures; old history no longer applies |
| Set reorder within a block | swap set 0 and set 1 | **Preserve set ids** — ordering is block-property |
| Set added / removed / split | split one set into two | **New ids for new sets**; surviving sets preserve ids |
| Set's timing mode changed (e.g. set_bounded → cap_bounded) | convert a straight-sets set to an AMRAP | **New set id** — the set's semantic behavior changed |
| Set's traversal changed (sequential ↔ round_robin) | restructure a superset into a circuit | **New set id** — traversal is structural |
| `set.repeat` count changed (3 → 4 or 4 → 3) | add or subtract a set-instance | **Preserve set id** — the set is the same, cardinality changed |
| `block.repeat` count changed | same at block level | **Preserve block id** |
| Block reorder within a workout | swap block 0 and block 1 | **Preserve block ids** |
| Block added / removed / split | | **New ids for new blocks**; surviving blocks preserve ids |
| Alternative added / changed / removed under a slot | add an alternative exercise | **Preserve slot id; alternative id is its own** (preserve for alternative-only field changes, new id when a new alternative is introduced) |

The server is responsible for generating ids per this table on every authoring round-trip; the client trusts the ids it receives. If the server's edit logic cannot tell which case applies (e.g. the client is editing a local draft before push), the conservative default is NEW id — it's always safer to orphan history than to bind unrelated history to a changed node.

**What the log rows depend on.** `slot_id`, `set_id`, `block_id` on `set_log` rows (log-shape.md) are the authored ids. A pulled-and-edited workout that preserves a slot's id preserves the slot's history; a reshape orphans history on the old id and starts fresh on the new id. This is deliberate: the alternative (matching on shape/position) is brittle and would retroactively rewrite history.

## Workout shape

```json
{
  "id": "uuid",
  "title": "Upper strength + conditioning",
  "scheduled_date": "2026-04-28",
  "stimuli": [],
  "blocks": [ /* block[] */ ]
}
```

`stimuli` at the workout level is the outermost default. Most workouts leave it empty; real use is things like "this whole day is a Z2 cardio day" attaching `hr_zone: 2` at the workout root.

## Block shape

```json
{
  "id": "uuid",
  "title": "Heavy bench + accessory push",
  "repeat": 1,
  "timer": { /* optional block-level timer */ },
  "stimuli": [],
  "work_target": [],
  "sets": [ /* set[] */ ]
}
```

- **`repeat`** — how many times the entire set sequence plays. Default 1. A 5-round CrossFit block with `sets: [A, B]` and `repeat: 5` plays `[A, B, A, B, A, B, A, B, A, B]`.
- **`timer`** — optional. If present, scopes the whole block's duration. Two forms:
  - `{ "direction": "count_up" }` — records total elapsed across the block (e.g. "how long did this warmup take"). No cap.
  - `{ "direction": "count_down", "duration_sec": 1200 }` — caps the block at 20 min. Acts as an outer AMRAP cap around whatever the sets inside do.
- **`stimuli`** — block-level stimuli. Applies to every set/slot inside unless overridden at a lower level.
- **`work_target`** — block-level work-target observations (rare). Mostly `{(rounds, open, observation)}` for counting AMRAP rounds across repeated sets, or `{(duration, open, observation)}` for for-time.
- **`sets`** — the set sequence that plays `repeat` times.

## Set shape

```json
{
  "id": "uuid",
  "title": "EMOM pair",
  "timing": { /* Timing primitive */ },
  "traversal": "sequential" | "round_robin" | "amrap",
  "repeat": 1,
  "stimuli": [],
  "work_target": [],
  "slots": [ /* slot[] */ ]
}
```

- **`timing`** — how time is structured within this set. See Timing primitive below. Options: `set_bounded`, `time_bounded`, `cap_bounded`, `target_bounded`.
- **`traversal`** — how the slots are executed:
  - `sequential` (default): slot 1, then slot 2, then slot 3, ... Used for supersets, straight-sets (single slot), EMOM stations performed in order within the minute.
  - `round_robin`: cycle through all slots, one rep or one dose at a time, then loop. Used for alternating-side work or tight circuits where the slot-to-slot rhythm is fine-grained.
  - `amrap`: cycle through slots repeatedly for the duration the timing specifies, counting rounds. Used for AMRAPs where the slots together define "one round."
- **`repeat`** — how many times this set plays back-to-back within its parent block's pass. Default 1. **Canonical rule:** if multiple sets logically differ (work set + rest set), author them as sibling sets inside one block; if the same set-instance repeats, use `set.repeat`. Do NOT encode the same workout as either "block-repeat of one set" or "set-repeat within one block" depending on authoring mood — pick by this rule. Canonical form for "4 × (1 min on, 1 min off)" is one block containing two sets (work set + rest set) with `block.repeat: 4` (four cycles of the work-then-rest pattern). The alternative encoding (one set, two slots, `set.repeat: 4`) is rejected at ingest because the work and rest are semantically distinct sets, not distinct slots.
- **`stimuli`** — set-level stimulus attachments. Common for "stay in zone 3 for this whole 20-minute AMRAP."
- **`work_target`** — set-level work-target. Common for AMRAP: `{(rounds, open, observation)}` on a time-bounded set.
- **`slots`** — the atomic prescription units. **May be empty (`[]`)** when the set is a pure-timer rest interval (tabata rest phase, between-round rest blocks). A zero-slot set is a valid authored form: its semantic is "elapse the timing, no work." Required: a zero-slot set must have `timing.mode = "time_bounded"` or `timing.mode = "cap_bounded"` (authoring-time rejection of zero-slot `set_bounded` sets — nothing would commit to end them). Driver behavior: a zero-slot time_bounded set advances the clock per `timing.params` and emits zero slot rows; a zero-slot cap_bounded set does the same under cap. No set_result row is emitted unless the set carries an explicit work_target.

## Slot shape

```json
{
  "id": "uuid",
  "exercise_id": "uuid-of-bench-press",
  "work_target": [ /* Work target primitive */ ],
  "load": { /* Load primitive, optional */ },
  "stimuli": [ /* Stimulus primitive[], optional */ ],
  "post_rest_sec": 0,
  "is_warmup": false,
  "notes": null,
  "alternatives": [ /* AlternativeSlot[], optional; see below */ ]
}
```

- **`id`** — stable UUID per the identity rule above.
- **`exercise_id`** — identity only, references the exercise catalog. Per D1, unilateral variants are distinct exercises.
- **`work_target`** — the metric-value-role triples this slot produces.
- **`load`** — optional; the Load primitive. Omitted or null means implicit bodyweight.
- **`stimuli`** — slot-level stimulus attachments. Most RIR targets live here.
- **`post_rest_sec`** — rest after this slot before the next slot (within sequential traversal) or before the set repeats. Default 0. Used for "[pushups × 10, 15s rest, bench × 5 @ 185]".
- **`is_warmup`** — authoring overlay; default false. Slot-level only. See "Authoring overlays" below.
- **`notes`** — authoring overlay; optional per-slot free text.
- **`alternatives`** — swap candidates as concrete objects (not just ids). Empty/omitted means no alternatives.

### AlternativeSlot shape

```json
{
  "id": "uuid",
  "exercise_id": "uuid-of-alternative-exercise",
  "work_target": [ /* optional override; omitted = inherit base slot */ ],
  "load": { /* optional override */ },
  "stimuli": [ /* optional override; absent-vs-empty rule applies */ ]
}
```

An alternative is a full slot-override proposal attached to a base slot. The alternative's `id` is a stable UUID (server-generated, persists across repulls) distinct from the base slot's `id`. When a swap is applied mid-workout, the logged `performed_exercise_id` on subsequent rows reflects the alternative's `exercise_id`, and the runtime's in-memory slot swaps its effective fields by the override rules. The base slot's `id` remains the log row's `slot_id` — swap does NOT rekey the slot; it retargets what that slot looks like. This preserves history linkage for the slot across swaps.

Override fields are optional. Omitted fields inherit the base slot. `stimuli` follows the absent-vs-empty convention: omitted → inherit, `[]` → clear all.

## Authoring overlays

Overlays are row-level fields orthogonal to the primitive model. They are declared authorable here so the authoring schema is closed (no undeclared keys in examples).

| Overlay | Authorable at | Default | Notes |
|---|---|---|---|
| `is_warmup` | slot | `false` | Log rows inherit. Warm-up ramps author as multiple slots with `is_warmup: true` ascending. |
| `notes` | slot, set, block | `null` | Free text. **Policy:** set-level and block-level notes stay in authoring and in preview/history UI; they are NOT copied or denormalized onto slot log rows. Slot log rows carry only the slot's own authored notes plus any runtime-added notes on the log row itself. If an aggregate row (`set_result`, `block_result`) exists, it may carry the authored set/block notes at display time (read from the stored workout, not from the log row). |
| `manual` | **NOT AUTHORABLE** | — | Log-only autoreg-bypass marker, set by the runtime reducer when user overrides an autoreg proposal. Not a field in the authored JSON. |
| `side` | **NOT AUTHORABLE** | `bilateral` | Log-only field per D1. Round-trips through correction but is not set from the sheet. Unilateral work is authored as distinct exercise identities. |
| `skipped` | **NOT AUTHORABLE** | `false` | Log-only; set when a user skips at the slot level. Preserves `weight_unit` per bug fix. |

Any authored key not listed under a primitive field or an overlay above is rejected at ingest.

## Validation constraints

Rejected-at-ingest constraints that keep authoring within what the runtime can execute today:

1. **At most one stimulus per type per attachment level.** A slot with two `rir` entries is invalid. The hierarchy walk is nearest-wins per type; ambiguity at the same level is a specification error, not a runtime decision.
2. **At most one interactive stimulus effective on a slot** (after the hierarchy walk). Interactive = `rir` or `rpe`. Derived stimuli (`hr_zone`) are unconstrained and may co-exist with an interactive stimulus. This mirrors the current execution contract's single `loggedRir` field; a future execution-contract extension (named downstream) will relax this.
3. **Exactly one completion metric per slot work_target** OR zero if the set's timing alone gates set-end. Two completion metrics on one slot creates dispatch ambiguity at `execute_slot` and is rejected.
4. **Block/set/slot ids are unique within the workout** and follow the identity rule above.
5. **Alternatives belong to exactly one base slot.** An alternative id appears under exactly one slot's `alternatives`.
6. **Timing × traversal must be a legal cell.** See the matrix in runtime-resolution.md.

## Primitive serialization

### Canonical form

Every workout has exactly one canonical wire form. Authoring-surface convenience (ergonomic shorthand) is allowed only if it desugars deterministically to the canonical form before persistence — an ingest normalizer enforces this. Two prescriptions that mean the same thing must serialize to byte-identical stored JSON (modulo ids), so fixtures, migrations, diffs, and sync all behave deterministically.

Canonical choices (referenced throughout this section):

1. **Repeat belongs where the semantic variation lives.** Siblings that differ (work + rest, pushup + pullup as separate sets) go in sibling sets under a block; identical repetitions go in `set.repeat` or `block.repeat`. See the set-shape rule for intervals/"1 min on, 1 min off" authoring.
2. **EMOM intervals live in `timing.params.rounds`, not `set.repeat`.** Time_bounded timing is the one right place for interval counts.
3. **Clusters are multi-slot with explicit per-slot reps and `post_rest_sec`.** No sub-rep metadata form.
4. **Warm-up ramps are multi-slot with `is_warmup: true` and explicit per-slot load.** Not a cluster and not a `repeat`.
5. **AMRAP's rounds work_target attaches at set level** (set-scoped round counting). A block-level rounds work_target would mean "rounds across the block" — only use that when the block has multiple sets and rounds span all of them.
6. **For-time duration work_target attaches at block level** when the cap is a block-level cap; at set level when the cap is set-level. The `block_result` vs `set_result` emission follows from which scope carries the work_target.

Any alternate authoring that parses but is non-canonical is REJECTED at ingest with an error pointing to the offending node and the canonical form the author should use instead.

### Structure primitive

Structure is not a single JSON field — it's the shape of the tree (block/set/slot nesting + `block.repeat` + `set.repeat` + `set.traversal`). There is no separate `"pattern": "straight_sets"` key anymore; the shape *is* the pattern. Named patterns become recognizable compositions:

| Legacy pattern | Composition |
|---|---|
| straight_sets | block with one set, one slot, `set.repeat = N` |
| superset | block with one set, multiple slots, `set.traversal = sequential`, `set.repeat = N` |
| circuit | block with one set, multiple slots, `set.traversal = sequential`, `set.repeat = N` |
| cluster | block with one set containing multiple slots (same `exercise_id`, per-slot reps, `post_rest_sec` between slots). Canonical — no sub-rep metadata form. |
| AMRAP | block with one set, multiple slots, `set.timing = cap_bounded`, `set.traversal = amrap`, set.work_target `{(rounds, open, observation)}` |
| EMOM | block with one set, one or many slots, `set.timing = time_bounded` with `interval_sec` + `rounds`, `set.traversal = sequential` |
| for-time (block-capped) | block with `block.timer = {direction: "count_down", duration_sec: cap}`, block.work_target `{(duration, open, observation)}`, one set with `set.traversal = sequential`, `set.repeat = N`. Canonical when the cap is the whole for-time event. |
| for-time (set-capped) | block with one set, `set.timing = cap_bounded`, set.work_target `{(duration, open, observation)}`. Use when the cap scopes a single set, not the block. |
| intervals | block with one set, one slot, `set.repeat = N`, `set.timing = set_bounded` (work is distance/duration-completion on the slot) |

### Timing primitive

Attaches to a set. (Block-level timing is via `block.timer` — a simpler shape with just direction and optional cap.)

```json
"timing": {
  "mode": "set_bounded" | "time_bounded" | "cap_bounded" | "target_bounded",
  "params": { /* mode-specific */ }
}
```

Per mode:

- **`set_bounded`**: `{ "params": {} }` — the set ends when the athlete commits the slot(s); rest after is `slot.post_rest_sec` or external.
- **`time_bounded`**: `{ "params": { "interval_sec": 60, "rounds": 10 } }` — EMOM-style; clock drives set-end at each interval, set plays `rounds` times.
- **`cap_bounded`**: `{ "params": { "cap_sec": 1200 } }` — AMRAP / for-time cap; timer forces end of the set.
- **`target_bounded`**: `{ "params": { "target": ... } }` — work until target hits. Target:
  - Metric: `{ "kind": "metric", "metric": "reps", "value": 100 }` — "100 total reps across the set."
  - Stimulus threshold: `{ "kind": "stimulus_threshold", "stimulus_type": "rpe", "op": ">=", "value": 9 }` — "work until RPE ≥ 9."

### Work target primitive

Same shape at any level (slot / set / block):

```json
"work_target": [
  {
    "metric": "reps" | "duration" | "distance" | "rounds" | "completion" | "load_carried",
    "value_form": "single" | "range" | "open",
    "value": <metric-dependent>,
    "role": "completion" | "observation"
  }
]
```

Value by value-form:
- `single`: scalar (e.g. `10` reps, `60` seconds, `1000` meters).
- `range`: `{ "min": 8, "max": 12 }`.
- `open`: `null` — counted/timed but no prescribed target.

**Role** (`completion` vs `observation`) gates what ends the slot/set:
- `completion` metrics gate the driver's done-signal.
- `observation` metrics are recorded but don't end anything.

### Load primitive

Attaches to a slot.

```json
"load": {
  "value": 185,
  "unit": "lb",
  "unit_type": "absolute"
}
```

Unit-type variants:

- **`absolute`**: `{ "value": 185, "unit": "lb", "unit_type": "absolute" }` or `{ "value": 60, "unit": "kg", "unit_type": "absolute" }`. Raw value; unit kg or lb.
- **`relative`**: `{ "value": 0.85, "unit": "1rm", "unit_type": "relative" }` or `{ "value": 0.5, "unit": "bodyweight", "unit_type": "relative" }`. Fraction of a named reference, resolves at seed time via `user_parameters`.
- **`implicit-bodyweight`**: `load` key omitted or explicitly `null`. Bodyweight-only slot; a `+vest` annotation can sit beside as an overlay later.

### Stimulus primitive

Attaches at any level (workout / block / set / slot). Same shape regardless of level:

```json
"stimuli": [
  {
    "type": "rir",
    "target": { "value_form": "single", "value": 2 },
    "autoreg": { /* optional rule set, stimulus-specific */ }
  },
  {
    "type": "hr_zone",
    "target": { "value_form": "single", "value": 3 }
  },
  {
    "type": "rpe",
    "target": { "value_form": "range", "value": { "min": 7, "max": 8 } }
  }
]
```

Per-stimulus fields:

- **`type`** — `"rir"`, `"rpe"`, `"hr_zone"`, or future types.
- **`target`** — prescribed value. Value-form grammar matches work-target metrics: `single`, `range`, `open`. Omitted for purely observational stimuli.
- **`autoreg`** — rule set, optional, stimulus-specific.

Value shapes per known stimulus type:

- `rir`: integer 0..5. Value-forms: single, range, open.
- `rpe`: integer/half 1..10. Value-forms: single, range.
- `hr_zone`: integer 1..5. Value-forms: single, range. **Derived from telemetry** at log-time; no stored column (see log-shape.md Q-G).

### Autoreg rules inside a stimulus

```json
"stimuli": [
  {
    "type": "rir",
    "target": { "value_form": "single", "value": 2 },
    "autoreg": {
      "overshoot_at": 2,
      "undershoot_at": 0,
      "load_step_kg": 2.5,
      "apply_to": "remaining_sets_in_set"
    }
  }
]
```

Fields are stimulus-specific. Today's RIR autoreg rule (overshoot/undershoot thresholds + load-step) encodes as above. `apply_to` now targets **within the set** — "adjust remaining repeats of this set at the adjusted load." Previously this was implicit because sets were the terminal authoring unit; with `set.repeat > 1`, autoreg needs to name its scope.

## Merge and override rules

### Hierarchy walk for effective stimuli

For each slot, the effective stimuli list is computed by walking up from slot → set → block → workout:

1. Start empty.
2. Collect `workout.stimuli`.
3. Override by type at `block.stimuli`.
4. Override by type at `set.stimuli`.
5. Override by type at `slot.stimuli`.
6. Apply library-default merge at the slot level for any stimulus type not otherwise attached.

"Override by type" means: if both `set` and `slot` name an `rir` stimulus, the slot's wins completely; the set's `rir` is hidden for that slot. Different stimulus types are independent — the set's `hr_zone` is still inherited.

### Library default merge at ingest (snapshot-materialized)

Library defaults live on the exercise catalog. The current system exposes `default_prescription_json` per exercise; under this model, library-default *stimuli* attach to the exercise as a sibling field `default_stimuli_json` (added in the schema cutover). Structure of `default_stimuli_json` matches the `stimuli` array shape in primitive serialization.

**Snapshot-materialized merge.** At workout ingest (server-side, when Claude pushes a workout to `/api/workouts`), the server:

1. Resolves each slot's stimulus list by walking `workout.stimuli` → `block.stimuli` → `set.stimuli` → `slot.stimuli` with nearest-wins per type (this is authoring-only, no library defaults yet).
2. For each slot, looks up `exercise.default_stimuli_json` for the slot's `exercise_id`.
3. For each stimulus type from the library that the slot's resolved authoring does NOT carry, appends the library default to the slot's `stimuli` array.
4. For each stimulus type present in BOTH, the authored wins — but within that stimulus, `autoreg` rule fields merge field-by-field (matches today's `autoreg` merge at `prescription.md:39`).
5. Persists the fully-materialized workout with library defaults written into slot-level `stimuli` arrays in the stored JSON.

**After ingest, the stored workout is self-contained.** No seed-time resolution reads from the exercise catalog. A workout pulled to the app at time T executes against the catalog state at time T₀ (when it was ingested), not T. This preserves the frozen-session / snapshot-at-ingest invariant from [v2-architecture.md:123](../v2-architecture.md) and the offline-first invariant from [CLAUDE.md:101](../../../CLAUDE.md).

**Consequence for the section-3 seed walk.** The seed-time `effective_stimuli` computation walks workout → block → set → slot stimuli on the stored workout only. It does NOT read `default_stimuli_json` at seed time. runtime-resolution.md's reference to "library-default merge at the slot level" is a historical echo of this ingest-time step; the seed walk itself is pure hierarchy resolution.

### Alternative override (swap)

The alternative payload is the `AlternativeSlot` object defined in the slot shape above. When a swap is applied at runtime (user picks alternative A over base slot B):

1. **exercise_id:** always overrides. The slot's executed exercise becomes the alternative's `exercise_id`.
2. **stimuli:** if alternative supplies a `stimuli` array, it replaces the base slot's effective stimuli wholesale (the library-default merge from ingest already lives on the base slot; the alternative starts fresh with its own override). If the alternative omits `stimuli`, inherit from the base slot. If the alternative supplies `"stimuli": []`, clear all stimuli.
3. **work_target:** if alternative supplies, replaces; else inherits.
4. **load:** if alternative supplies, replaces; else inherits.
5. **Log linkage:** the base slot's `id` remains the log row's `slot_id`. `performed_exercise_id` on log rows after the swap reflects the alternative's `exercise_id`. Rows logged before the swap retain the base's `exercise_id` on their `performed_exercise_id`. Swap does NOT rekey the slot.

## Worked examples

Ten prescription patterns, each worked end-to-end. Node ids are elided with `"id": "..."` placeholders — every block, set, slot, and alternative carries a UUID per the identity rule, omitted here for readability.

### 1. Straight sets, loaded strength

"4 × 8 bench press @ 185 lb, target RIR 2."

```json
{
  "title": "Bench day",
  "blocks": [{
    "title": "Bench press",
    "sets": [{
      "timing": { "mode": "set_bounded", "params": {} },
      "traversal": "sequential",
      "repeat": 4,
      "slots": [{
        "exercise_id": "bench-press-uuid",
        "work_target": [
          { "metric": "reps", "value_form": "single", "value": 8, "role": "completion" }
        ],
        "load": { "value": 185, "unit": "lb", "unit_type": "absolute" },
        "stimuli": [{
          "type": "rir",
          "target": { "value_form": "single", "value": 2 },
          "autoreg": {
            "overshoot_at": 2, "undershoot_at": 0,
            "load_step_kg": 2.5, "apply_to": "remaining_sets_in_set"
          }
        }],
        "post_rest_sec": 180
      }]
    }]
  }]
}
```

### 2. Superset

"3 rounds of bench 8 @ 135 + barbell row 8 @ 95, RIR 2, 90s rest between rounds."

```json
{
  "blocks": [{
    "title": "Push/pull superset",
    "sets": [{
      "timing": { "mode": "set_bounded", "params": {} },
      "traversal": "sequential",
      "repeat": 3,
      "slots": [
        {
          "exercise_id": "bench-press-uuid",
          "work_target": [{ "metric": "reps", "value_form": "single", "value": 8, "role": "completion" }],
          "load": { "value": 135, "unit": "lb", "unit_type": "absolute" },
          "stimuli": [{ "type": "rir", "target": { "value_form": "single", "value": 2 } }],
          "post_rest_sec": 0
        },
        {
          "exercise_id": "barbell-row-uuid",
          "work_target": [{ "metric": "reps", "value_form": "single", "value": 8, "role": "completion" }],
          "load": { "value": 95, "unit": "lb", "unit_type": "absolute" },
          "stimuli": [{ "type": "rir", "target": { "value_form": "single", "value": 2 } }],
          "post_rest_sec": 90
        }
      ]
    }]
  }]
}
```

### 3. Percent of 1RM with rep range

"5 × 8-12 back squat @ 80% 1RM, RIR 1-2."

```json
{
  "blocks": [{
    "sets": [{
      "timing": { "mode": "set_bounded", "params": {} },
      "traversal": "sequential",
      "repeat": 5,
      "slots": [{
        "exercise_id": "back-squat-uuid",
        "work_target": [
          { "metric": "reps", "value_form": "range", "value": { "min": 8, "max": 12 }, "role": "completion" }
        ],
        "load": { "value": 0.80, "unit": "1rm", "unit_type": "relative" },
        "stimuli": [{
          "type": "rir",
          "target": { "value_form": "range", "value": { "min": 1, "max": 2 } },
          "autoreg": { "overshoot_at": 3, "undershoot_at": 0, "load_step_kg": 2.5, "apply_to": "remaining_sets_in_set" }
        }],
        "post_rest_sec": 120
      }]
    }]
  }]
}
```

### 4. Continuous cardio with HR zone

"30 min easy run, zone 2 HR."

```json
{
  "blocks": [{
    "sets": [{
      "timing": { "mode": "time_bounded", "params": { "interval_sec": 1800, "rounds": 1 } },
      "traversal": "sequential",
      "repeat": 1,
      "stimuli": [{ "type": "hr_zone", "target": { "value_form": "single", "value": 2 } }],
      "slots": [{
        "exercise_id": "run-uuid",
        "work_target": [
          { "metric": "duration", "value_form": "single", "value": 1800, "role": "completion" },
          { "metric": "distance", "value_form": "open", "role": "observation" }
        ]
      }]
    }]
  }]
}
```

HR zone attaches at set level (one row "covers" the whole 30 minutes). Duration is completion; distance is observed. HR zone derives at log time.

### 5. Intervals with pace observation

"4 × (1 km run @ target 5:00/km, 2 min rest)."

```json
{
  "blocks": [{
    "sets": [{
      "timing": { "mode": "set_bounded", "params": {} },
      "traversal": "sequential",
      "repeat": 4,
      "slots": [{
        "exercise_id": "run-uuid",
        "work_target": [
          { "metric": "distance", "value_form": "single", "value": 1000, "role": "completion" },
          { "metric": "duration", "value_form": "single", "value": 300, "role": "observation" }
        ],
        "post_rest_sec": 120
      }]
    }]
  }]
}
```

Pace = `distance / duration` at display time. Duration is the target pace translated, role=observation so distance-completion gates set-end.

### 6. Weighted carry

"3 × farmer carry, 60 lb for 80 m, 90s rest."

```json
{
  "blocks": [{
    "sets": [{
      "timing": { "mode": "set_bounded", "params": {} },
      "traversal": "sequential",
      "repeat": 3,
      "slots": [{
        "exercise_id": "farmer-carry-uuid",
        "work_target": [
          { "metric": "distance", "value_form": "single", "value": 80, "role": "completion" },
          { "metric": "duration", "value_form": "open", "role": "observation" }
        ],
        "load": { "value": 60, "unit": "lb", "unit_type": "absolute" },
        "post_rest_sec": 90
      }]
    }]
  }]
}
```

Load + distance-completion is the carry semantic. No special exercise type.

### 7. EMOM

"10 min EMOM of 3 hang cleans @ 135 lb."

```json
{
  "blocks": [{
    "sets": [{
      "timing": { "mode": "time_bounded", "params": { "interval_sec": 60, "rounds": 10 } },
      "traversal": "sequential",
      "repeat": 1,
      "slots": [{
        "exercise_id": "hang-clean-uuid",
        "work_target": [{ "metric": "reps", "value_form": "single", "value": 3, "role": "completion" }],
        "load": { "value": 135, "unit": "lb", "unit_type": "absolute" }
      }]
    }]
  }]
}
```

No stimulus. The set's time-bounded timing (60s × 10 rounds) drives cadence.

### 8. CrossFit compound round (the canonical example)

"5 rounds of: AMRAP 5 min of (10 pushups + 10 pullups), then 1 km run."

```json
{
  "blocks": [{
    "title": "CrossFit compound",
    "repeat": 5,
    "sets": [
      {
        "title": "AMRAP pushup/pullup",
        "timing": { "mode": "cap_bounded", "params": { "cap_sec": 300 } },
        "traversal": "amrap",
        "repeat": 1,
        "work_target": [{ "metric": "rounds", "value_form": "open", "role": "observation" }],
        "slots": [
          {
            "exercise_id": "pushup-uuid",
            "work_target": [{ "metric": "reps", "value_form": "single", "value": 10, "role": "completion" }]
          },
          {
            "exercise_id": "pullup-uuid",
            "work_target": [{ "metric": "reps", "value_form": "single", "value": 10, "role": "completion" }]
          }
        ]
      },
      {
        "title": "1 km run",
        "timing": { "mode": "set_bounded", "params": {} },
        "traversal": "sequential",
        "repeat": 1,
        "slots": [{
          "exercise_id": "run-uuid",
          "work_target": [{ "metric": "distance", "value_form": "single", "value": 1000, "role": "completion" }]
        }]
      }
    ]
  }]
}
```

Block repeats 5 times. First set is a 5-minute AMRAP of two slots (`traversal: amrap`, counts rounds as observation). Second set is the run slot. Clean nesting; no mode-conflict flags.

### 9. For-time with cap

"5 rounds for time: 10 burpees + 200 m run. Cap 15 min."

```json
{
  "blocks": [{
    "timer": { "direction": "count_down", "duration_sec": 900 },
    "work_target": [{ "metric": "duration", "value_form": "open", "role": "observation" }],
    "sets": [{
      "timing": { "mode": "set_bounded", "params": {} },
      "traversal": "sequential",
      "repeat": 5,
      "slots": [
        { "exercise_id": "burpee-uuid",
          "work_target": [{ "metric": "reps", "value_form": "single", "value": 10, "role": "completion" }] },
        { "exercise_id": "run-uuid",
          "work_target": [{ "metric": "distance", "value_form": "single", "value": 200, "role": "completion" }] }
      ]
    }]
  }]
}
```

The 15-minute cap lives at `block.timer` (the outer deadline). The inner set is set-bounded (athlete commits each slot) with `repeat: 5`. Observed duration is a block-level outcome, so the `work_target` for it attaches at block level — which makes a `block_result` row emission consistent with the log-shape.md rule ("`block_result` row iff the block carries a block-level work_target").

### 10. 1RM test with warm-up ramp

"Back squat 1RM test. Estimated 295 lb. Build up (ramp at ~45 / 135 / 185 / 225 / 265), then attempt."

```json
{
  "blocks": [
    {
      "title": "Warm-up ramp",
      "sets": [{
        "timing": { "mode": "set_bounded", "params": {} },
        "traversal": "sequential",
        "repeat": 1,
        "slots": [
          { "exercise_id": "back-squat-uuid", "work_target": [{ "metric": "reps", "value_form": "single", "value": 5, "role": "completion" }], "load": { "value": 45, "unit": "lb", "unit_type": "absolute" }, "is_warmup": true, "post_rest_sec": 60 },
          { "exercise_id": "back-squat-uuid", "work_target": [{ "metric": "reps", "value_form": "single", "value": 5, "role": "completion" }], "load": { "value": 135, "unit": "lb", "unit_type": "absolute" }, "is_warmup": true, "post_rest_sec": 90 },
          { "exercise_id": "back-squat-uuid", "work_target": [{ "metric": "reps", "value_form": "single", "value": 3, "role": "completion" }], "load": { "value": 185, "unit": "lb", "unit_type": "absolute" }, "is_warmup": true, "post_rest_sec": 120 },
          { "exercise_id": "back-squat-uuid", "work_target": [{ "metric": "reps", "value_form": "single", "value": 2, "role": "completion" }], "load": { "value": 225, "unit": "lb", "unit_type": "absolute" }, "is_warmup": true, "post_rest_sec": 180 },
          { "exercise_id": "back-squat-uuid", "work_target": [{ "metric": "reps", "value_form": "single", "value": 1, "role": "completion" }], "load": { "value": 265, "unit": "lb", "unit_type": "absolute" }, "is_warmup": true, "post_rest_sec": 240 }
        ]
      }]
    },
    {
      "title": "Test attempt",
      "sets": [{
        "timing": { "mode": "set_bounded", "params": {} },
        "traversal": "sequential",
        "repeat": 1,
        "slots": [{
          "exercise_id": "back-squat-uuid",
          "work_target": [{ "metric": "reps", "value_form": "single", "value": 1, "role": "completion" }],
          "load": { "value": 295, "unit": "lb", "unit_type": "absolute" }
        }]
      }]
    }
  ]
}
```

Warm-up ramp is a set with multiple slots (same exercise, ascending load, `is_warmup: true`). Test attempt is a separate block. No "test" primitive.

## Current gaps

- `PDM-GAP-002`: Authoring-shape open questions need explicit disposition
  before code relies on the ambiguous shape. Current preferences favor
  structural multi-slot authoring for drop sets and clusters, and seed-time
  relative-load resolution as pinned in `runtime-resolution.md`.

## Open questions

**Q-C. `progressive` value-form for drop sets.** A drop set (225 × 5 → 185 × 8 → 155 × AMRAP) can be authored as one set with three slots (same exercise, descending load, `post_rest_sec: 0`) or as one slot with a `progressive` load value-form. **Preference: structural multi-slot** — the hierarchy already expresses it; adding `progressive` as a value-form creates a second way to say the same thing.

**Q-F. Relative-load resolution timing.** Resolved in runtime-resolution.md: cache once at seed against the local `user_parameters` mirror by `updated_at`-latest-before-pull. Pinning the source `user_parameters` row id on `ExecutionSlot` is deferred until a coordinated execution-plan/schema cutover needs that provenance.

**Q-H. Cluster authoring at seed-time.** Two valid authorings of a cluster (15 total reps across 4 sub-sets with 20s intra-set rest):
- **One slot with `sub_sets` metadata and total reps** — ergonomic; driver expands.
- **One set with N slots, same exercise, per-slot reps, `post_rest_sec: 20`** — explicit; composition already covers it.

Preference: explicit multi-slot under the hierarchy — see runtime-resolution.md.
