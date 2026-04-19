// WorkoutCache+Reconcile.swift
//
// Orphan-delete logic for `WorkoutCacheImpl.save(_:)`. Pulled workouts
// need more than upsert — when Claude edits a workout on the server and
// removes a block, item, or alternative, the on-device cache still holds
// the old rows under the upsert-only semantics described in
// `WorkoutCache.swift`. That leaks stale rows into rendered workouts.
//
// This file reconciles per-workout: for every incoming `Workout`, the
// existing block / item / alternative descendants are fetched, the
// incoming IDs are subtracted, and the difference is deleted before the
// upsert phase runs. Scope is the workout subtree only:
//
//   • Exercises (the catalog) are upsert-only. Claude owns the UUID
//     space; never drop old catalog rows.
//   • UserParameters are append-only history. Don't drop old rows.
//   • SetLogs are client-owned. They survive reconcile by a two-step
//     defense: (1) `detachSetLogs(fromItem:)` below nulls the SwiftData
//     relationship so the cascade rule can't take them with the parent
//     delete, and (2) each SetLog carries its own denormalized
//     `workoutID` / `plannedExerciseID` (R1.4, see
//     `SwiftDataModels.swift`) so the public `WorkoutCache` history
//     queries resolve by column predicate rather than by walking from
//     the (now-gone) parent item. Either defense alone is insufficient:
//     without the detach, the cascade deletes the row; without the
//     denormalized columns, the row stays on disk but is unreachable
//     via the public API (the Codex-caught leak this fix-it closes).
//
// Split out of `WorkoutCache.swift` so the actor body stays under
// SwiftLint's `type_body_length` cap, matching the pattern of
// `WorkoutCache+Upserts.swift` and `WorkoutCache+History.swift`.

import Foundation
import SwiftData
import CoreDomain
import WorkoutCoreFoundation

extension WorkoutCacheImpl {

    /// For every Workout in the dataset, compare the existing on-disk
    /// block / item / alternative subtree against the incoming shape and
    /// delete rows that are no longer present. SetLogs are intentionally
    /// left alone — they're client-owned and survive server edits.
    ///
    /// Runs inside `save(_:)`'s do/catch; a throw here propagates to the
    /// same `rollback()` path that an upsert throw would.
    func reconcileWorkoutSubtrees(dataset: PulledDataset) throws {
        let incomingWorkoutIDs = Set(dataset.workouts.map(\.id))
        guard !incomingWorkoutIDs.isEmpty else { return }

        // Group incoming rows by their parent so per-workout reconcile is
        // O(rows) not O(workouts × rows).
        let incomingBlocksByWorkout = Dictionary(grouping: dataset.blocks, by: \.workoutID)
        let incomingItemsByBlock = Dictionary(grouping: dataset.items, by: \.blockID)
        let incomingAltsByItem = Dictionary(grouping: dataset.alternatives, by: \.workoutItemID)

        for workoutID in incomingWorkoutIDs {
            let incomingBlockIDs = Set(
                (incomingBlocksByWorkout[workoutID] ?? []).map(\.id)
            )
            let existingBlocks = try fetchExistingBlocks(workoutID: workoutID)
            try reconcileBlocks(
                existingBlocks: existingBlocks,
                incomingBlockIDs: incomingBlockIDs,
                incomingItemsByBlock: incomingItemsByBlock,
                incomingAltsByItem: incomingAltsByItem
            )
        }
    }

    private func reconcileBlocks(
        existingBlocks: [BlockModel],
        incomingBlockIDs: Set<UUID>,
        incomingItemsByBlock: [UUID: [WorkoutItem]],
        incomingAltsByItem: [UUID: [ExerciseAlternative]]
    ) throws {
        for existingBlock in existingBlocks {
            if !incomingBlockIDs.contains(existingBlock.id) {
                // Orphaned block. Detach any grand-descendant set_logs
                // so the cascade rule (see SwiftDataModels.swift on
                // WorkoutItemModel.setLogs) doesn't take them with the
                // subtree — set_logs are client-owned and must survive
                // a server edit that removes the item.
                try detachSetLogs(fromBlock: existingBlock)
                modelContext.delete(existingBlock)
                continue
            }

            let incomingItemIDs = Set(
                (incomingItemsByBlock[existingBlock.id] ?? []).map(\.id)
            )
            let existingItems = try fetchExistingItems(blockID: existingBlock.id)
            try reconcileItems(
                existingItems: existingItems,
                incomingItemIDs: incomingItemIDs,
                incomingAltsByItem: incomingAltsByItem
            )
        }
    }

    private func reconcileItems(
        existingItems: [WorkoutItemModel],
        incomingItemIDs: Set<UUID>,
        incomingAltsByItem: [UUID: [ExerciseAlternative]]
    ) throws {
        for existingItem in existingItems {
            if !incomingItemIDs.contains(existingItem.id) {
                // Orphaned item. Same rationale as block deletion: detach
                // set_logs first so cascade delete only takes the item +
                // its alternatives.
                try detachSetLogs(fromItem: existingItem)
                modelContext.delete(existingItem)
                continue
            }

            let incomingAltIDs = Set(
                (incomingAltsByItem[existingItem.id] ?? []).map(\.id)
            )
            let existingAlts = try fetchExistingAlternatives(workoutItemID: existingItem.id)
            for existingAlt in existingAlts where !incomingAltIDs.contains(existingAlt.id) {
                modelContext.delete(existingAlt)
            }
        }
    }

    /// Null out every `SetLogModel.workoutItem` link under the given block
    /// before the block is cascade-deleted. The loose `workoutItemID`
    /// column stays intact — History reads by UUID, not by relationship —
    /// so the set_log remains queryable.
    private func detachSetLogs(fromBlock block: BlockModel) throws {
        let items = try fetchExistingItems(blockID: block.id)
        for item in items {
            try detachSetLogs(fromItem: item)
        }
    }

    private func detachSetLogs(fromItem item: WorkoutItemModel) throws {
        let itemID = item.id
        let descriptor = FetchDescriptor<SetLogModel>(
            predicate: #Predicate<SetLogModel> { $0.workoutItemID == itemID }
        )
        let logs = try modelContext.fetch(descriptor)
        for log in logs {
            log.workoutItem = nil
        }
    }

    private func fetchExistingBlocks(workoutID: UUID) throws -> [BlockModel] {
        let descriptor = FetchDescriptor<BlockModel>(
            predicate: #Predicate<BlockModel> { $0.workoutID == workoutID }
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchExistingItems(blockID: UUID) throws -> [WorkoutItemModel] {
        let descriptor = FetchDescriptor<WorkoutItemModel>(
            predicate: #Predicate<WorkoutItemModel> { $0.blockID == blockID }
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchExistingAlternatives(workoutItemID: UUID) throws -> [ExerciseAlternativeModel] {
        let descriptor = FetchDescriptor<ExerciseAlternativeModel>(
            predicate: #Predicate<ExerciseAlternativeModel> { $0.workoutItemID == workoutItemID }
        )
        return try modelContext.fetch(descriptor)
    }
}
