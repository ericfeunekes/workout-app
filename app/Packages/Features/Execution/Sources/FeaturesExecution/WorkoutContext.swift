// WorkoutContext.swift
//
// Read-only snapshot of the workout being executed. Mirrors the shape of
// `TodayContext` in Features/Today — one value type holding everything the
// Execution view model needs to render and reduce over. Assembled by the
// app shell (or a future ExecutionLoader) from pulled data and handed to
// `ExecutionViewModel` at construction.
//
// The Execution layer does not reach back into Persistence for workout
// shape; it operates on this context in memory. Session mutations write
// through a `SessionStore` byte bucket (see `ExecutionViewModel`).

import Foundation
import CoreDomain
import WorkoutCoreFoundation

/// Everything the Execution screens need to render a live workout.
public struct WorkoutContext: Sendable {
    /// The workout being executed.
    public let workout: Workout

    /// Blocks in position order.
    public let blocks: [Block]

    /// Items, keyed by block position for O(1) lookup during render. The
    /// outer array is block-position-ordered; the inner array is
    /// item-position-ordered within each block.
    public let itemsByBlock: [[WorkoutItem]]

    /// Exercise catalog keyed by exerciseID. Missing entries render as
    /// "(unknown exercise)" — consistent with Today.
    public let exercises: [UUID: Exercise]

    /// Pre-formatted "last time" summary per exercise id (e.g.
    /// "5×5 @ 100 kg · RIR 2"). Surfaced on the Active screen's last-time
    /// chip. Empty map means no history — the chip hides.
    public let lastPerformed: [UUID: String]

    /// Pre-computed alternatives keyed by `WorkoutItemID`. Drives the
    /// long-press → swap sheet on the Active screen. An empty array (or
    /// missing key) means "no alternatives authored" — the sheet renders
    /// an empty state rather than failing to open.
    public let alternativesByItem: [UUID: [ExerciseAlternative]]

    /// Latest-per-key numeric user_parameters. Keys follow the server
    /// convention (`1rm_<slug>_kg`, `bodyweight_kg`, …); values are
    /// parsed from the append-only `user_parameters` log's latest row
    /// for each key. Populated by `AppBootstrap.buildWorkoutContext`
    /// from `WorkoutCache.loadUserParametersLatest()`.
    ///
    /// qa-045: load resolvers (e.g. `percent_1rm`) read from this map
    /// at seed time to resolve prescriptions like "3 × 5 @ 60% 1RM"
    /// into a concrete load in kg. Missing keys leave `loadKg = nil`
    /// so the execution UI falls back to "BW" — the user can still
    /// log the set, just without a pre-filled load suggestion.
    public let userParameters: [String: Double]

    public init(
        workout: Workout,
        blocks: [Block],
        itemsByBlock: [[WorkoutItem]],
        exercises: [UUID: Exercise],
        lastPerformed: [UUID: String] = [:],
        alternativesByItem: [UUID: [ExerciseAlternative]] = [:],
        userParameters: [String: Double] = [:]
    ) {
        self.workout = workout
        self.blocks = blocks
        self.itemsByBlock = itemsByBlock
        self.exercises = exercises
        self.lastPerformed = lastPerformed
        self.alternativesByItem = alternativesByItem
        self.userParameters = userParameters
    }

    // MARK: - Convenience lookups

    /// Item at a (blockIndex, itemIndex) position, or nil if out of range.
    public func item(at blockIndex: Int, itemIndex: Int) -> WorkoutItem? {
        guard blockIndex < itemsByBlock.count else { return nil }
        let items = itemsByBlock[blockIndex]
        guard itemIndex < items.count else { return nil }
        return items[itemIndex]
    }

    /// Block at a blockIndex, or nil if out of range.
    public func block(at blockIndex: Int) -> Block? {
        guard blockIndex < blocks.count else { return nil }
        return blocks[blockIndex]
    }

    /// Exercise name for an item — honors a session-time swap override by
    /// preferring `performedExerciseID` when given.
    public func exerciseName(
        for item: WorkoutItem,
        performedExerciseID: UUID? = nil
    ) -> String {
        let id = performedExerciseID ?? item.exerciseID
        return exercises[id]?.name ?? "(unknown exercise)"
    }

    /// Alternatives for a given item id. Returns `[]` when none are
    /// authored — the swap sheet handles the empty case.
    public func alternatives(for itemID: UUID) -> [ExerciseAlternative] {
        alternativesByItem[itemID] ?? []
    }
}
