// WorkoutCache+Reconcile.swift
//
// Orphan-delete logic for `WorkoutCacheImpl.save(_:)`. Pulled workouts
// need more than upsert — when Claude edits a workout on the server and
// removes a block, item, or alternative, the on-device cache still holds
// the old rows under the upsert-only semantics described in
// `WorkoutCache.swift`. That leaks stale rows into rendered workouts.
//
// This file reconciles per-workout: for every incoming `Workout`, the
// existing block / item / alternative descendants are looked up in the
// `PullPreload` (built once at the top of `save(_:)`), the incoming IDs
// are subtracted, and the difference is deleted before the upsert phase
// runs. Scope is the workout subtree only:
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
    ///
    /// Uses the pre-built `PullPreload` to resolve existing subtrees in
    /// memory — no per-workout fetch.
    func reconcileWorkoutSubtrees(dataset: PulledDataset, preload: PullPreload) throws {
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
            let existingBlocks = preload.blocksByWorkoutID[workoutID] ?? []
            try reconcileBlocks(
                existingBlocks: existingBlocks,
                incomingBlockIDs: incomingBlockIDs,
                incomingItemsByBlock: incomingItemsByBlock,
                incomingAltsByItem: incomingAltsByItem,
                preload: preload
            )
        }
    }

    private func reconcileBlocks(
        existingBlocks: [BlockModel],
        incomingBlockIDs: Set<UUID>,
        incomingItemsByBlock: [UUID: [WorkoutItem]],
        incomingAltsByItem: [UUID: [ExerciseAlternative]],
        preload: PullPreload
    ) throws {
        for existingBlock in existingBlocks {
            if !incomingBlockIDs.contains(existingBlock.id) {
                // Orphaned block. Detach any grand-descendant set_logs
                // so the cascade rule (see SwiftDataModels.swift on
                // WorkoutItemModel.setLogs) doesn't take them with the
                // subtree — set_logs are client-owned and must survive
                // a server edit that removes the item.
                try detachSetLogs(fromBlock: existingBlock, preload: preload)
                modelContext.delete(existingBlock)
                // Drop references from the preload so a subsequent upsert
                // in the same save() can't re-attach a parent to a
                // tombstoned model or look up a cascade-deleted item.
                // Dataset coherence means incoming items/alts under a
                // reconciled-away block shouldn't exist, but defending
                // against a malformed pull is cheap.
                let cascadedItems = preload.itemsByBlockID.removeValue(
                    forKey: existingBlock.id
                ) ?? []
                for cascadedItem in cascadedItems {
                    preload.itemsByID.removeValue(forKey: cascadedItem.id)
                    let cascadedAlts = preload.alternativesByItemID.removeValue(
                        forKey: cascadedItem.id
                    ) ?? []
                    for cascadedAlt in cascadedAlts {
                        preload.alternativesByID.removeValue(forKey: cascadedAlt.id)
                    }
                }
                preload.blocksByID.removeValue(forKey: existingBlock.id)
                preload.blocksByWorkoutID[existingBlock.workoutID]?.removeAll {
                    $0.id == existingBlock.id
                }
                continue
            }

            let incomingItemIDs = Set(
                (incomingItemsByBlock[existingBlock.id] ?? []).map(\.id)
            )
            let existingItems = preload.itemsByBlockID[existingBlock.id] ?? []
            try reconcileItems(
                existingItems: existingItems,
                incomingItemIDs: incomingItemIDs,
                incomingAltsByItem: incomingAltsByItem,
                preload: preload
            )
        }
    }

    private func reconcileItems(
        existingItems: [WorkoutItemModel],
        incomingItemIDs: Set<UUID>,
        incomingAltsByItem: [UUID: [ExerciseAlternative]],
        preload: PullPreload
    ) throws {
        for existingItem in existingItems {
            if !incomingItemIDs.contains(existingItem.id) {
                // Orphaned item. Same rationale as block deletion: detach
                // set_logs first so cascade delete only takes the item +
                // its alternatives.
                try detachSetLogs(fromItem: existingItem)
                modelContext.delete(existingItem)
                let cascadedAlts = preload.alternativesByItemID.removeValue(
                    forKey: existingItem.id
                ) ?? []
                for cascadedAlt in cascadedAlts {
                    preload.alternativesByID.removeValue(forKey: cascadedAlt.id)
                }
                preload.itemsByID.removeValue(forKey: existingItem.id)
                preload.itemsByBlockID[existingItem.blockID]?.removeAll {
                    $0.id == existingItem.id
                }
                continue
            }

            let incomingAltIDs = Set(
                (incomingAltsByItem[existingItem.id] ?? []).map(\.id)
            )
            let existingAlts = preload.alternativesByItemID[existingItem.id] ?? []
            for existingAlt in existingAlts where !incomingAltIDs.contains(existingAlt.id) {
                modelContext.delete(existingAlt)
                preload.alternativesByID.removeValue(forKey: existingAlt.id)
                preload.alternativesByItemID[existingItem.id]?.removeAll {
                    $0.id == existingAlt.id
                }
            }
        }
    }

    /// Null out every `SetLogModel.workoutItem` link under the given block
    /// before the block is cascade-deleted. The loose `workoutItemID`
    /// column stays intact — History reads by UUID, not by relationship —
    /// so the set_log remains queryable.
    private func detachSetLogs(fromBlock block: BlockModel, preload: PullPreload) throws {
        let items = preload.itemsByBlockID[block.id] ?? []
        for item in items {
            try detachSetLogs(fromItem: item)
        }
    }

    private func detachSetLogs(fromItem item: WorkoutItemModel) throws {
        // The SetLog fetch here is NOT an N+1 on dataset size — it runs
        // once per orphaned item (typically zero in the common pull path
        // and at most a handful on a Claude-side edit). We keep this as a
        // direct fetch because set_logs aren't in the preload: they're
        // write-only during a pull and reading them speculatively for
        // every pull would be wasted work.
        let itemID = item.id
        let descriptor = FetchDescriptor<SetLogModel>(
            predicate: #Predicate<SetLogModel> { $0.workoutItemID == itemID }
        )
        let logs = try recordedFetch(descriptor)
        for log in logs {
            log.workoutItem = nil
        }
    }
}
