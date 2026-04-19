// SessionState.swift
//
// Live-session state as a pure value type. Every field listed in
// `app/README.md` § "Persistence (local session)" has a home here:
//
//   | Store          | Field                                    |
//   | Log            | `items[i].sets` (load/reps/rir/done/adj) |
//   | Cursor         | `cursor` (blockIndex, itemIndex, setIdx) |
//   | Route          | `route`                                  |
//   | Note           | `note` (workout-level, dictation append) |
//   | autoregHeld    | `items[i].autoregHeld`                   |
//   | Rest timer     | `restEndsAt` (absolute Date)             |
//
// The reducer (`SessionReducer.reduce`) never reaches outside this struct.
// Reloading the app — from a cold start, a background kill, or an iOS
// memory eviction — means re-materializing the same `SessionState` from
// persistence; nothing else is needed to resume.
//
// Why `restEndsAt: Date?` instead of an elapsed-remaining count:
//   absolute-timestamp semantics survive reload without drift. If the user
//   backgrounds the app mid-rest and comes back, `restEndsAt - now()` is
//   the correct remaining time; an elapsed-seconds store would lie. This
//   matches the spec in `app/README.md`: "Absolute `rest_ends_at`
//   timestamp (not elapsed) so reload re-derives remaining time without
//   drift."

import Foundation
import CoreAutoreg
import CorePrescription
import WorkoutCoreFoundation

public struct SessionState: Equatable, Sendable {

    /// Top-level navigation route during a session.
    ///
    /// `today` is the entry and exit state — pre-start and post-save. The
    /// active→rest→active loop repeats until the last set of the last item
    /// of the last block, at which point `complete` shows the ledger.
    public enum Route: String, Sendable, Equatable {
        case today
        case active
        case rest
        case complete
    }

    /// Per-item mutable session state.
    ///
    /// `autoregHeld` is set by `.holdAutoreg` and read by the Features
    /// layer when deciding whether to call `Autoreg.propose`. Core/Session
    /// only stores the flag; the decision to gate on it lives in Features.
    /// (The reducer's `applyAutoregProposal` handler honors the separation:
    /// if a proposal arrives, it is applied — the caller is expected to
    /// have skipped proposing in the first place when held.)
    ///
    /// `performedExerciseID` is set only when the user swaps. `nil` means
    /// the workout_item's default exerciseID is in effect. The workout
    /// template is not mutated on swap — that invariant belongs to the
    /// Features layer; Core/Session just records the override.
    ///
    /// `overrides` is populated when the user swaps to an alternative that
    /// carries a non-empty `parameter_overrides_json`. The reps/load
    /// overrides are also written onto the non-done `SetPlan` rows at
    /// swap time (so the Active screen and autoreg apply paths see the
    /// new values without a separate read), but `target_rir` cannot live
    /// on `SetPlan` — drivers read it from `overrides` instead. See
    /// `CorePrescription.AlternativeOverrides` for the field contract.
    public struct ItemLog: Equatable, Sendable {
        public let itemID: WorkoutItemID
        public var autoregHeld: Bool
        public var sets: [SetPlan]
        public var performedExerciseID: ExerciseID?
        public var overrides: AlternativeOverrides?

        public init(
            itemID: WorkoutItemID,
            autoregHeld: Bool = false,
            sets: [SetPlan],
            performedExerciseID: ExerciseID? = nil,
            overrides: AlternativeOverrides? = nil
        ) {
            self.itemID = itemID
            self.autoregHeld = autoregHeld
            self.sets = sets
            self.performedExerciseID = performedExerciseID
            self.overrides = overrides
        }
    }

    /// Where the user is in the workout. All indices zero-based except
    /// `setIndex`, which is 1-based to match the `set_log.set_index`
    /// convention on the server and the `SetPlan.setIndex` convention in
    /// CoreAutoreg. Callers should treat setIndex==0 as a sentinel for
    /// "no active set" (e.g., route == .today) if they need one; the
    /// reducer itself doesn't read cursor for state decisions other than
    /// advance.
    public struct Cursor: Equatable, Sendable {
        public let blockIndex: Int
        public let itemIndex: Int
        public let setIndex: Int

        public init(blockIndex: Int, itemIndex: Int, setIndex: Int) {
            self.blockIndex = blockIndex
            self.itemIndex = itemIndex
            self.setIndex = setIndex
        }
    }

    /// Cursor advancement policy for a block. Populated by the seeder
    /// per block based on `timingMode`. Keeps the reducer pure — the
    /// reducer reads policy from state, never reaches into CoreDomain's
    /// `Block`.
    ///
    /// - `setMajor`: walk all sets of item 0, then item 1, ... (straight
    ///   sets / rep_range / sets_detail / warmup / cluster / percent_1rm /
    ///   bodyweight). This is the legacy v0 advancement shape.
    /// - `roundRobin`: within one "round" (= one value of setIndex), walk
    ///   items 0..N-1; then bump setIndex and restart at item 0 (circuit,
    ///   superset, amrap, emom, forTime, tabata). The total rounds per
    ///   item live in `setsPerItem[blockIndex][itemIndex]` — the seeder
    ///   populates those from `block.rounds` (or a hard-coded constant
    ///   for tabata, or a sentinel cap for amrap/emom).
    /// - `zeroItem`: the block has no items (standalone `rest`). The
    ///   cursor lands on `(b, 0, 1)` and the VM routes to `.rest`.
    public enum BlockAdvancement: String, Sendable, Equatable {
        case setMajor
        case roundRobin
        case zeroItem
    }

    /// Flat layout of the workout structure needed for cursor advancement.
    /// Core/Session does not own Workout/Block/WorkoutItem — those live in
    /// CoreDomain and are heavy with metadata the reducer doesn't need.
    /// Instead the caller composes a `Structure` from the pulled workout
    /// and hands it to the reducer on `start` (implicit — embedded in the
    /// state) and `advanceFromRest` (explicit — via the state).
    ///
    /// The structure is intentionally minimal: just enough to know when
    /// the last set of the last item of the last block is reached so
    /// `advanceFromRest` can flip to `.complete`, plus the per-block
    /// advancement policy so `nextCursor` can pick between "walk sets
    /// then items" and "round-robin items then rounds".
    public struct Structure: Equatable, Sendable {
        /// Count of items per block, in block order. `itemsPerBlock[i]`
        /// is the number of items in block `i`. An empty block
        /// (e.g., a standalone `rest` block) has a zero here.
        public let itemsPerBlock: [Int]
        /// Count of sets per (block, item), keyed by `[blockIndex][itemIndex]`.
        /// `setsPerItem.count == itemsPerBlock.count`. For round-based
        /// modes this is `block.rounds` replicated across items; for
        /// set-major modes it's the per-item prescription's `sets`.
        public let setsPerItem: [[Int]]
        /// Per-block advancement policy. `advancementByBlock.count ==
        /// itemsPerBlock.count`. Pre-existing callers that don't supply
        /// a value default to `setMajor` (legacy straight-sets behavior)
        /// or `zeroItem` when the block has no items.
        public let advancementByBlock: [BlockAdvancement]

        public init(
            itemsPerBlock: [Int],
            setsPerItem: [[Int]],
            advancementByBlock: [BlockAdvancement]? = nil
        ) {
            self.itemsPerBlock = itemsPerBlock
            self.setsPerItem = setsPerItem
            if let advancementByBlock {
                self.advancementByBlock = advancementByBlock
            } else {
                // Back-compat default: zero-item blocks are `zeroItem`,
                // everything else is `setMajor`. Pre-existing tests that
                // construct `Structure` without the new field stay green.
                self.advancementByBlock = itemsPerBlock.map { $0 == 0 ? .zeroItem : .setMajor }
            }
        }
    }

    public let workoutID: WorkoutID
    public var route: Route
    public var cursor: Cursor
    public var items: [ItemLog]
    public var restEndsAt: Date?
    /// Absolute wall-clock deadline for the current time-capped block
    /// (AMRAP `time_cap_sec`, ForTime `time_cap_sec`, EMOM `total_minutes`,
    /// Tabata 8 × 30s total). The VM sets this on block entry via
    /// `enterBlockTimerIfNeeded`; the view compares `blockEndsAt` to
    /// `clock.now` at render time and dispatches `.complete` when elapsed.
    /// Absolute-timestamp semantics (not elapsed) so backgrounding +
    /// reload survives without drift, matching `restEndsAt`.
    public var blockEndsAt: Date?
    /// Absolute wall-clock deadline for the current "work" window of a
    /// Tabata round (20s from round entry). When elapsed, the VM
    /// auto-logs a placeholder `.logSet(0, nil)` and enters the 10s rest.
    /// Nil outside tabata or between work windows.
    public var workEndsAt: Date?
    /// Absolute wall-clock anchor for the CURRENT EMOM block's interval
    /// grid — the moment interval 1 started. All EMOM interval boundaries
    /// derive from this: boundary of interval N (1-based) is
    /// `intervalAnchorAt + N * interval_sec`. Stamped on block entry by
    /// `enterBlockTimerIfNeeded` (alongside `blockEndsAt`) and cleared on
    /// block change (alongside `blockEndsAt`/`workEndsAt`). Log-time does
    /// NOT re-anchor — EMOM drift-free correctness depends on the anchor
    /// staying fixed for the block's duration. Nil outside EMOM.
    /// Absolute-timestamp semantics so backgrounding + reload survives
    /// without drift, matching `restEndsAt` / `blockEndsAt`.
    public var intervalAnchorAt: Date?
    /// Wall-clock instant the user began the CURRENT working set — i.e.,
    /// when the previous rest ended (or when the session started, for the
    /// very first set). Read by the reducer's `.logSet` / `.logCardioSet`
    /// handlers and stamped onto the logged `SetPlan.startedAt`, then
    /// cleared back to nil so the next set's anchor must be set again by
    /// `.advanceFromRest` (or the equivalent VM-level entry helper).
    ///
    /// Distinct semantics from `SetPlan.completedAt` chaining — rest time
    /// is NOT part of set work time. A 10s bench press followed by a 90s
    /// rest stamps `startedAt = T`, `completedAt = T+10`; the next set's
    /// `startedAt` is T+100 (when rest ended), NOT T+10 (previous
    /// completedAt). Folding rest into set duration makes per-set working
    /// time un-analyzable.
    ///
    /// Set by the view model on workout start and rest-end via direct
    /// state mutation (matching the `workEndsAt` / `intervalAnchorAt`
    /// precedent — the reducer doesn't own wall-clock anchors). Persisted
    /// via `SessionStateCodable` so a kill-then-relaunch mid-set preserves
    /// the anchor rather than collapsing `startedAt == completedAt` for
    /// the resumed set.
    public var workStartedAt: Date?
    public var note: String
    public var structure: Structure

    public init(
        workoutID: WorkoutID,
        route: Route,
        cursor: Cursor,
        items: [ItemLog],
        restEndsAt: Date? = nil,
        blockEndsAt: Date? = nil,
        workEndsAt: Date? = nil,
        intervalAnchorAt: Date? = nil,
        workStartedAt: Date? = nil,
        note: String = "",
        structure: Structure
    ) {
        self.workoutID = workoutID
        self.route = route
        self.cursor = cursor
        self.items = items
        self.restEndsAt = restEndsAt
        self.blockEndsAt = blockEndsAt
        self.workEndsAt = workEndsAt
        self.intervalAnchorAt = intervalAnchorAt
        self.workStartedAt = workStartedAt
        self.note = note
        self.structure = structure
    }
}
