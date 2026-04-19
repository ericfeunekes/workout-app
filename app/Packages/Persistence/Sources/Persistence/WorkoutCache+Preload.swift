// WorkoutCache+Preload.swift
//
// Batched preload of the existing rows a `save(_:)` call needs, so the
// upsert + reconcile phases can resolve every parent and same-id lookup
// against an in-memory dictionary instead of a per-row
// `modelContext.fetch(descriptor)`.
//
// The old shape issued one fetch per row in `upsertWorkout` /
// `upsertBlock` / etc. (and another per parent attachment), turning a
// 50-workout pull into thousands of SQL queries. perf-004 — the
// first-launch bootstrap hot path.
//
// Shape of the preload, keyed by the incoming dataset:
//
//   • workoutsByID       : existing workouts whose id ∈ incoming workout ids
//   • blocksByID         : existing blocks whose id ∈ incoming block ids OR
//                          workoutID ∈ incoming workout ids
//                          (the union covers both same-id upsert matching
//                           and reconcile's per-workout child walk)
//   • itemsByID          : existing items whose id ∈ incoming item ids OR
//                          blockID ∈ existing block ids ∪ incoming block ids
//   • alternativesByID   : existing alternatives whose id ∈ incoming alt
//                          ids OR workoutItemID ∈ existing item ids ∪
//                          incoming item ids
//   • exercisesByID      : existing exercises whose id ∈ incoming exercise
//                          ids (no parent to walk)
//   • userParametersByID : existing rows whose id ∈ incoming param ids
//
// The dictionaries are mutable so upsert helpers can seed freshly-inserted
// rows — child rows in the same batch then attach via `preload.blocksByID`
// without a second fetch.
//
// The class is a reference type purely so the mutable dictionaries thread
// through the upsert helpers without having to return a mutated copy at
// every step. It's internal to `Persistence` and never crosses an actor
// boundary, so no `Sendable` dance is needed.

import Foundation
import SwiftData

final class PullPreload {
    var workoutsByID: [UUID: WorkoutModel] = [:]
    var blocksByID: [UUID: BlockModel] = [:]
    var itemsByID: [UUID: WorkoutItemModel] = [:]
    var alternativesByID: [UUID: ExerciseAlternativeModel] = [:]
    var exercisesByID: [UUID: ExerciseModel] = [:]
    var userParametersByID: [UUID: UserParameterModel] = [:]

    /// Existing blocks grouped by `workoutID`. Populated alongside
    /// `blocksByID` so the reconcile path can walk per-workout children
    /// without a second fetch or a re-group.
    var blocksByWorkoutID: [UUID: [BlockModel]] = [:]

    /// Existing items grouped by `blockID`, same rationale as above for
    /// the items → block relationship.
    var itemsByBlockID: [UUID: [WorkoutItemModel]] = [:]

    /// Existing alternatives grouped by `workoutItemID`.
    var alternativesByItemID: [UUID: [ExerciseAlternativeModel]] = [:]
}

extension WorkoutCacheImpl {

    /// Build a `PullPreload` for the given dataset. Issues one batched
    /// IN-predicate fetch per entity class (six total) regardless of the
    /// dataset size.
    func preloadModels(for dataset: PulledDataset) throws -> PullPreload {
        let preload = PullPreload()

        let incomingWorkoutIDs = Set(dataset.workouts.map(\.id))
        let incomingBlockIDs = Set(dataset.blocks.map(\.id))
        let incomingItemIDs = Set(dataset.items.map(\.id))
        let incomingAlternativeIDs = Set(dataset.alternatives.map(\.id))
        let incomingExerciseIDs = Set(dataset.exercises.map(\.id))
        let incomingUserParameterIDs = Set(dataset.userParameters.map(\.id))

        // --- Workouts ---------------------------------------------------
        if !incomingWorkoutIDs.isEmpty {
            let workoutIDSet = incomingWorkoutIDs
            let rows = try recordedFetch(
                FetchDescriptor<WorkoutModel>(
                    predicate: #Predicate<WorkoutModel> { workoutIDSet.contains($0.id) }
                )
            )
            for row in rows {
                preload.workoutsByID[row.id] = row
            }
        }

        // --- Blocks -----------------------------------------------------
        // Reconcile walks by workoutID; upsert matches by block id. Fetch
        // the union so one query covers both.
        if !incomingBlockIDs.isEmpty || !incomingWorkoutIDs.isEmpty {
            let blockIDSet = incomingBlockIDs
            let workoutIDSet = incomingWorkoutIDs
            let rows = try recordedFetch(
                FetchDescriptor<BlockModel>(
                    predicate: #Predicate<BlockModel> { row in
                        blockIDSet.contains(row.id) || workoutIDSet.contains(row.workoutID)
                    }
                )
            )
            for row in rows {
                preload.blocksByID[row.id] = row
                preload.blocksByWorkoutID[row.workoutID, default: []].append(row)
            }
        }

        // --- Items ------------------------------------------------------
        // For reconcile the scope is "items under any existing block
        // that belongs to an incoming workout". `preload.blocksByID`
        // already holds every such block, so its keys are the authoritative
        // parent-id set.
        let blockParentIDs = Set(preload.blocksByID.keys).union(incomingBlockIDs)
        if !incomingItemIDs.isEmpty || !blockParentIDs.isEmpty {
            let itemIDSet = incomingItemIDs
            let parentBlockIDSet = blockParentIDs
            let rows = try recordedFetch(
                FetchDescriptor<WorkoutItemModel>(
                    predicate: #Predicate<WorkoutItemModel> { row in
                        itemIDSet.contains(row.id) || parentBlockIDSet.contains(row.blockID)
                    }
                )
            )
            for row in rows {
                preload.itemsByID[row.id] = row
                preload.itemsByBlockID[row.blockID, default: []].append(row)
            }
        }

        // --- Alternatives -----------------------------------------------
        let itemParentIDs = Set(preload.itemsByID.keys).union(incomingItemIDs)
        if !incomingAlternativeIDs.isEmpty || !itemParentIDs.isEmpty {
            let altIDSet = incomingAlternativeIDs
            let parentItemIDSet = itemParentIDs
            let rows = try recordedFetch(
                FetchDescriptor<ExerciseAlternativeModel>(
                    predicate: #Predicate<ExerciseAlternativeModel> { row in
                        altIDSet.contains(row.id)
                            || parentItemIDSet.contains(row.workoutItemID)
                    }
                )
            )
            for row in rows {
                preload.alternativesByID[row.id] = row
                preload.alternativesByItemID[row.workoutItemID, default: []].append(row)
            }
        }

        // --- Exercises --------------------------------------------------
        if !incomingExerciseIDs.isEmpty {
            let exerciseIDSet = incomingExerciseIDs
            let rows = try recordedFetch(
                FetchDescriptor<ExerciseModel>(
                    predicate: #Predicate<ExerciseModel> { exerciseIDSet.contains($0.id) }
                )
            )
            for row in rows {
                preload.exercisesByID[row.id] = row
            }
        }

        // --- User parameters --------------------------------------------
        if !incomingUserParameterIDs.isEmpty {
            let userParameterIDSet = incomingUserParameterIDs
            let rows = try recordedFetch(
                FetchDescriptor<UserParameterModel>(
                    predicate: #Predicate<UserParameterModel> {
                        userParameterIDSet.contains($0.id)
                    }
                )
            )
            for row in rows {
                preload.userParametersByID[row.id] = row
            }
        }

        return preload
    }
}
