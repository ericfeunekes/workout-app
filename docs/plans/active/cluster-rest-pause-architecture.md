---
title: Cluster and rest-pause execution architecture
status: draft
purpose: Define the smallest sound build shape for executing cluster/rest-pause sets without turning them into a new timing mode or leaking slot state into autoreg.
covers:
  - docs/prescription.md
  - docs/workout-execution-requirements.md
  - app/Packages/Core/Session/
  - app/Packages/Features/Execution/
  - app/Packages/Core/Autoreg/
---

# Cluster and rest-pause execution architecture

## Context

Cluster/rest-pause is already part of the authoring vocabulary. Claude can push a strength prescription like `sets=4`, `reps=5`, `sub_sets=4`, and `intra_set_rest_sec=15`, and the target behavior is clear: each top-level set is a composed set made of sub-set work slots separated by intra-set rest. The app should guide the athlete through those slots, then write one top-level `set_log` with total reps, duration, load, and one RIR value.

The current implementation does not preserve that structure into live execution. Parsing and Today rendering know about `.cluster`, but session seeding collapses each cluster top-level set into a plain `SetPlan` row with only one rep target. The execution state machine then only knows `block/item/set`; it has no slot/sub-set cursor or intra-set rest anchor. That is why cluster/rest-pause was deferred: building it correctly requires a small new session primitive, not another UI patch.

The important constraint is that this is still strength set execution, not a new block timing mode. A cluster set belongs inside `straight_sets` or other set-based blocks; block-level rest still happens only after the composed set is logged.

## Architecture Snapshot

Current structure:

- `CorePrescription` parses `prescription_json` and exposes `Prescription.cluster(sets, reps, loadKg, unit, subSets, intraSetRestSec, targetRir, autoreg)`.
- `FeaturesExecution.SessionSeeder` materializes prescriptions into `SessionState.ItemLog` rows.
- `CoreSession.SessionState` owns pure route, cursor, anchors, item logs, structure, and reducer mutations.
- `CoreAutoreg.SetPlan` is the flat pending/logged set row used by autoreg, local persistence, history, and push.
- `FeaturesExecution.ExecutionViewModel` owns clock, side effects, persistence, sheet routing, and driver integration.
- `SessionStateCodable` owns the local snapshot shape; CoreSession intentionally remains non-Codable.

Current evidence:

- `docs/specs/v2-architecture.md` says the app only shows, times, and logs workouts, while timing behavior is driven by block timing mode and prescriptions describe what to do inside the block.
- `docs/prescription.md` defines cluster/rest-pause as one top-level set made of sub-sets, with one `set_log` per top-level set and `duration_sec` covering the cluster.
- `Prescription.cluster` exists in `CorePrescription`.
- `SessionSeeder.setsFor(.cluster)` currently calls `seedUniform(sets: sets, reps: reps)`, dropping `subSets` and `intraSetRestSec`.
- Round-based extraction also collapses `.cluster` to `(reps, load, unit)`.
- `SessionState.Cursor` only has `blockIndex`, `itemIndex`, and `setIndex`.
- `SessionState` has anchors for global rest, block caps, interval work, ready, and working-set start, but no intra-set rest anchor or slot state.
- `.logSet` commits a whole `SetPlan` at once and clears `workStartedAt`.

## Pressure Map

The dominant pressure is semantic loss at the seeding boundary. Once a cluster becomes a plain `SetPlan`, every downstream layer correctly treats it as a normal set. Fixing this in the view alone would create a fake cluster UI over a flat execution model and would fail on persistence, reload, push, and autoreg.

The second pressure is package ownership. `SetPlan` lives in `CoreAutoreg`, even though it is reused by session execution. Adding cluster slot progression directly to `SetPlan` would make the autoreg package own execution state it should not understand.

The third pressure is timer integrity. Intra-set rest looks like rest to the athlete, but it is not the app's global `.rest` route: the top-level set is not logged yet, autoreg should not run yet, and block-level rest should not start yet.

The fourth pressure is log classification. `SetPlan.durationSec` currently implies "cardio" in the local completion/push builder. Cluster needs a strength row that can also carry duration, so the implementation must fix that classification before writing cluster duration.

## Hotspot Register

| Rank | Hotspot | Score | Evidence | Risk |
|---:|---|---:|---|---|
| 1 | `ExecutionViewModel.logSet` | 7/10 | Churn 1, complexity 3, leakage 1, blast 2. It assumes `Done` means the whole set logs immediately. | A sub-set `Done` could accidentally commit the top-level set and trigger global rest/autoreg too early. |
| 2 | `SessionState` cursor and anchors | 6/10 | Churn 1, complexity 2, leakage 1, blast 2. It can represent set-level work/rest but not slot-level progress. | Intra-set rest will be confused with block rest or lost across background/relaunch. |
| 3 | `SetPlan` as shared log/autoreg row | 6/10 | Churn 1, complexity 2, leakage 1, blast 2. It is the authoritative pending/logged row, but it lives in `CoreAutoreg`. | Adding cluster fields here would leak execution concerns into autoreg and widen the blast radius. |
| 4 | `SessionSeeder.setsFor(.cluster)` | 5/10 | Churn 0, complexity 1, leakage 2, blast 2. It collapses `subSets` and `intraSetRestSec` before runtime. | Any UI built later cannot recover the authored cluster shape. Task-critical despite a moderate hotspot score. |
| 5 | `SessionStateCodable` | 5/10 | Churn 0, complexity 2, leakage 1, blast 2. It persists anchors and set rows, but not composed-set progress. | A kill/relaunch mid-cluster could resume as a plain set unless the new state is persisted. |

## Boundary Matrix

| From / To | CorePrescription | CoreAutoreg | CoreSession | FeaturesExecution | Persistence/Sync |
|---|---|---|---|---|---|
| `CorePrescription` | internal | no dependency | no dependency | no dependency | no dependency |
| `CoreAutoreg` | allowed for autoreg config | internal | no dependency | no dependency | no dependency |
| `CoreSession` | current allowed dependency for prescription-adjacent session types | allowed for `SetPlan` | internal | no dependency | no dependency |
| `FeaturesExecution` | allowed parse/format/driver dependency | allowed through session/autoreg surfaces | allowed state/mutation dependency | internal | allowed edge dependency |
| `Persistence/Sync` | DTO/schema mapping only | no runtime mutation | no reducer dependency | no UI dependency | internal |

Boundary rule for this slice:

- `CorePrescription` owns parsing the authored cluster shape.
- `FeaturesExecution.SessionSeeder` owns translating the parsed prescription into session runtime state.
- `CoreSession` owns pure cluster progress state and mutations.
- `CoreAutoreg.SetPlan` stays a flat top-level set row; it does not know about sub-sets or intra-set rest.
- `FeaturesExecution` owns presentation, clocks, sheets, side effects, and local snapshot encoding.
- Server/schema stays unchanged for the first slice because the accepted logging shape is one `set_log` per top-level set.

## Target Shape

Introduce a CoreSession-level runtime sidecar for composed sets:

```swift
public struct CompositeSetProgress: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case cluster
    }

    public enum Phase: Equatable, Sendable {
        case ready(slotIndex: Int)
        case working(slotIndex: Int, startedAt: Date)
        case intraRest(afterSlotIndex: Int, endsAt: Date)
        case completePendingLog
    }

    public let itemID: WorkoutItemID
    public let setIndex: Int
    public let kind: Kind
    public let targetRepsPerSlot: Int
    public let slotCount: Int
    public let intraRestSec: Double
    public var firstStartedAt: Date?
    public var phase: Phase
    public var completedSlots: Int
}
```

The exact names can change during implementation, but the ownership should not: this state belongs in `CoreSession`, not `CoreAutoreg`.

Seed behavior:

- For `.cluster(sets, reps, load, unit, subSets, intraRest, targetRir, autoreg)`, create one normal top-level `SetPlan` per authored top-level set.
- The top-level `SetPlan.reps` should represent the top-level logged target: `reps * subSets`. This preserves undershoot/autoreg semantics against the actual logged total.
- Add one `CompositeSetProgress` entry for each top-level set with `targetRepsPerSlot = reps`, `slotCount = subSets`, and `intraRestSec = intraRest`.
- The UI should render the composed target from `CompositeSetProgress`, not from `SetPlan.reps`, so the athlete sees `4 x 5`, not a confusing `20`.

Execution behavior:

- The existing route remains `.active`; intra-set rest is a sub-phase of active work, not global `.rest`.
- The athlete must explicitly start each work slot for now.
- `Set Start` starts the current slot, stamps the current slot work start, and sets `firstStartedAt` if this is the first slot.
- `Done` during a non-final slot marks that slot complete and enters intra-set rest.
- Intra-set rest counts down. After expiry it turns into the same kind of red over-rest count-up, but still inside the active composite set.
- Starting the next slot exits intra-set rest and stamps a new slot work start.
- `Done` on the final slot opens the existing row-based log sheet for the top-level set.
- Final log should use a dedicated composite finalization mutation rather than the existing plain `.logSet`, because the plain path cannot stamp `durationSec`. The mutation commits one `SetPlan`: total reps, load, one RIR, `startedAt` from `firstStartedAt`, `completedAt` at final log, and `durationSec = completedAt - firstStartedAt`.
- The local completion/push builder must classify the row as strength-with-duration, not cardio. Do not rely on `durationSec != nil` as the cardio discriminator once clusters can write duration.
- Only after final log does normal block-level rest start, autoreg evaluate, and the cursor advance.

Autoreg behavior:

- Resolve the existing open question as: cluster autoreg fires only after the top-level composed set is logged.
- It never fires per sub-set.
- It uses `SetPlan.reps == reps * subSets` as the prescribed total for undershoot detection.
- RIR is the athlete's subjective RIR for the final effort in the composed set.
- Implementing this requires updating the current `StraightSetsDriver` guard that suppresses `.cluster` autoreg, and updating `docs/open-questions.md` / `docs/prescription.md` so the decision is durable.

Swap/resizing behavior:

- Composite progress rows must follow the same lifecycle as pending `SetPlan` rows.
- If a set-major swap extends pending set rows, add matching pending composite progress rows only when the current performed prescription is still cluster-shaped.
- If a swap truncates pending set rows, remove matching pending composite progress rows but preserve already-logged composite rows until completion/push classification is finished.
- If a swap changes the active item away from cluster-shaped work, clear pending composite progress for that item and continue as plain set execution.
- Add tests for swap resize and shape-change behavior; otherwise the sidecar can silently desync from the authoritative set rows.

This preserves the athlete model: sub-slots are guided, but the training log still sees one top-level set.

## What Is Not Generalized Yet

- No generalized "composite set algebra" for every future shape.
- No drop-set execution changes in this slice.
- No myo-rep activation-set semantics beyond the existing `cluster` shape.
- No per-slot load changes unless the user edits the final top-level load.
- No per-slot actual-reps persistence to the server.
- No round-robin or AMRAP cluster execution.
- No automatic transition between sub-set work slots.
- No schema migration.
- No new timing mode.
- No broad rewrite of all `SetPlan.durationSec` semantics beyond the classification change needed to let a strength row carry duration.

Those are future decisions. The first slice should only prove uniform cluster/rest-pause execution inside set-major strength work.

## Ownership And Dependency Direction

Allowed dependency direction:

- `CorePrescription -> CoreDomain/Foundation`
- `CoreAutoreg -> CorePrescription/CoreDomain/Foundation`
- `CoreSession -> CoreAutoreg/CorePrescription/Foundation`
- `FeaturesExecution -> CoreSession/CorePrescription/CoreDomain/CoreAutoreg/Persistence`
- `Persistence/Sync -> CoreDomain/schema DTOs`

Ownership:

- Parser owner: `CorePrescription`.
- Session progress owner: `CoreSession`.
- Clock and side-effect owner: `FeaturesExecution.ExecutionViewModel`.
- Local snapshot owner: `FeaturesExecution.SessionStateCodable`.
- Log row owner: `CoreAutoreg.SetPlan`, but only for top-level set values.
- Push/server owner: unchanged one-row `set_log`.

Forbidden for this slice:

- `CoreAutoreg` must not import or model cluster slot progress.
- `Persistence` must not become the owner of the in-flight composite state.
- Views must not derive cluster progress from raw `prescription_json`.
- Drivers must not treat cluster as a new block timing mode.

## Checks And Fitness Functions

Add tests before implementation where practical:

- Parser fixture already exists; keep it as proof that the authoring shape is valid.
- Seeder test: `.cluster(sets: 4, reps: 5, subSets: 4)` creates four top-level `SetPlan` rows with `reps == 20` and four `CompositeSetProgress` entries.
- Reducer tests: start slot 1, complete slot 1, enter intra-rest, over-rest can be represented, start slot 2, complete final slot, final log is the only whole-set commit.
- VM test: `logSet` during a non-final cluster slot does not call `.logSet` on the top-level `SetPlan`.
- VM test: final cluster log uses the composite finalization path, stamps duration, starts global rest, and runs autoreg exactly once.
- Codable test: active cluster slot and intra-set rest restore after encode/decode.
- Push/local-cache test: completed cluster writes one strength set log with total reps, load, RIR, started-at, completed-at, and duration. Regress a duration-only cardio row so the classification fix does not break cardio.
- Swap tests: resizing cluster pending rows also resizes composite progress, and swapping away from cluster clears pending composite progress without deleting logged rows.
- Regression tests: straight sets, AMRAP, EMOM, Tabata, intervals, superset, circuit still pass.
- Simulator QA: cluster set from first Set Start through intra-set over-rest, final log, global rest, next top-level set.

Architectural check to add later:

- A lightweight test or lint check should fail if `CoreAutoreg` starts depending on `CoreSession` or any Features package. That protects the "autoreg does math, session owns execution" boundary.

## Top Interventions

1. Add `CompositeSetProgress` and composite finalization in `CoreSession`.

Effort: medium. Risk: restore/codable, timestamp stamping, and reducer correctness. Payoff: creates the missing session primitive without changing server schema or timing modes.

2. Preserve cluster shape during seeding.

Effort: small-medium. Risk: existing tests may expect cluster `SetPlan.reps == reps`; those tests should be updated only if they assert old flattened behavior. Payoff: fixes the semantic loss at the first boundary.

3. Split sub-slot completion from whole-set logging in the VM.

Effort: medium. Risk: accidental early autoreg/rest/cursor advancement. Payoff: makes cluster execution behave like a real composed set while reusing the existing final log sheet and push path.

4. Fix set-log classification for strength rows with duration.

Effort: small-medium. Risk: duration-only cardio rows currently depend on the old heuristic. Payoff: makes cluster duration safe without losing reps/load in push/history.

## Draft ADRs

### ADR: Cluster is a composed set, not a timing mode

Decision: Do not add a `cluster` timing mode. Treat cluster/rest-pause as a prescription shape inside set-major strength execution.

Consequences:

- Block-level timing modes stay focused on workout flow.
- Cluster can live inside `straight_sets` without schema changes.
- UI must render slot progress from session state, not block timing mode.

Tradeoff: Round-robin clusters remain intentionally unsupported until there is a real authored workout that needs them.

### ADR: Composite progress lives in CoreSession, not SetPlan

Decision: Add a CoreSession composite-set sidecar keyed by item and set index instead of adding cluster fields to `SetPlan`.

Consequences:

- `SetPlan` remains the top-level log/autoreg row.
- `CoreAutoreg` stays pure and does not own execution-slot state.
- Session reducers can own slot transitions and intra-set rest.

Tradeoff: There is a parallel runtime structure that must stay aligned with `SetPlan` lifecycle. Seeder and tests must enforce that alignment.

### ADR: First slice logs one set row per top-level cluster set

Decision: Preserve the accepted one-row logging shape for the first implementation.

Consequences:

- No server migration.
- Existing push/history/completion surfaces continue to work.
- RIR and autoreg run once per top-level set.
- The completion/push builder must allow a strength row to carry duration without dropping reps/load.

Tradeoff: Per-slot actuals and expanded after-the-fact editing remain a follow-up. The runtime model should leave room for slot actuals, but the first shipped log contract stays one row.

### ADR: Cluster autoreg is top-level only

Decision: A cluster set can use autoreg when authored, but only after the full composed set is logged.

Consequences:

- Sub-set transitions never trigger autoreg.
- The logged total reps are compared against the top-level total target.
- RIR means final-effort RIR for the composed set.
- The existing `StraightSetsDriver` suppression for `.cluster` must be removed or narrowed.

Tradeoff: This does not solve autoreg for drop sets, pyramids, round-robin strength stations, or per-slot cluster actuals.

## Smallest Next Step

Build a narrow strength-only cluster slice:

1. Add CoreSession composite progress types and pure mutations for start slot, complete slot, start/expire intra-rest, and finalize top-level set.
2. Update `SessionSeeder` to retain cluster shape for `straight_sets` by creating composite progress entries and top-level total-rep `SetPlan` rows.
3. Update `SessionStateCodable` to persist composite progress.
4. Add a composite finalization mutation that can stamp `startedAt`, `completedAt`, and `durationSec` on the one top-level `SetPlan`.
5. Fix completion/push row classification so strength rows can carry duration without being treated as cardio.
6. Update `StraightSetsDriver` and docs so cluster autoreg is top-level-only instead of suppressed.
7. Make swap/resize logic mirror pending composite progress rows with pending `SetPlan` rows.
8. Update `ExecutionViewModel` so non-final cluster `Done` advances the composite sub-slot instead of logging the set.
9. Reuse the existing row-based log sheet UI only for final cluster completion, but commit through the composite finalization mutation.
10. Prove with focused Swift tests before touching visual polish.

Stop after that slice. Do not implement generalized composite sets, round-robin clusters, or per-slot server logs until this first path is working and QA has shown where the real friction is.
