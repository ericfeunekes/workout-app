// FakeHistoryCache.swift
//
// In-memory `WorkoutCache` double used by the FeaturesHistory tests.
// Stores everything in plain arrays so tests can seed data without
// touching SwiftData.
//
// Only the methods the History feature actually reads are backed by
// meaningful fixtures; unused methods return empty arrays.

import Foundation
import CoreDomain
import Persistence
import WorkoutCoreFoundation

final class FakeHistoryCache: WorkoutCache, @unchecked Sendable {
    var workouts: [Workout]
    var blocksByWorkout: [UUID: [Block]]
    var itemsByBlock: [UUID: [WorkoutItem]]
    var exercises: [Exercise]
    var setLogsByWorkout: [UUID: [SetLog]]
    /// `user_parameters` rows indexed by `key`. Tests that exercise the
    /// History bodyweight-window lookup seed this directly; the rest
    /// ignore it.
    var userParametersByKey: [String: [UserParameter]]

    init(
        workouts: [Workout] = [],
        blocksByWorkout: [UUID: [Block]] = [:],
        itemsByBlock: [UUID: [WorkoutItem]] = [:],
        exercises: [Exercise] = [],
        setLogsByWorkout: [UUID: [SetLog]] = [:],
        userParametersByKey: [String: [UserParameter]] = [:]
    ) {
        self.workouts = workouts
        self.blocksByWorkout = blocksByWorkout
        self.itemsByBlock = itemsByBlock
        self.exercises = exercises
        self.setLogsByWorkout = setLogsByWorkout
        self.userParametersByKey = userParametersByKey
    }

    func save(_ dataset: PulledDataset) async throws {}

    func loadWorkouts(status: WorkoutStatus?, since: Date?) async throws -> [Workout] {
        guard let status else { return workouts }
        return workouts.filter { $0.status == status }
    }

    func loadBlocks(workoutID: WorkoutID) async throws -> [Block] {
        blocksByWorkout[workoutID] ?? []
    }

    func loadItems(blockID: BlockID) async throws -> [WorkoutItem] {
        loadItemsCallCount += 1
        return itemsByBlock[blockID] ?? []
    }

    func loadItems(
        workoutIDs: [WorkoutID]
    ) async throws -> [WorkoutID: [WorkoutItem]] {
        loadItemsBulkCallCount += 1
        guard !workoutIDs.isEmpty else { return [:] }
        let wanted = Set(workoutIDs)
        var out: [WorkoutID: [WorkoutItem]] = [:]
        for (workoutID, blocks) in blocksByWorkout where wanted.contains(workoutID) {
            var items: [WorkoutItem] = []
            // Emit in (block position, item position) order so the
            // real `WorkoutCacheImpl.loadItems(workoutIDs:)` contract
            // and the fake agree.
            let orderedBlocks = blocks.sorted { $0.position < $1.position }
            for block in orderedBlocks {
                let blockItems = (itemsByBlock[block.id] ?? [])
                    .sorted { $0.position < $1.position }
                items.append(contentsOf: blockItems)
            }
            if !items.isEmpty {
                out[workoutID] = items
            }
        }
        return out
    }

    /// Per-block single fetch counter — the old per-session path drove
    /// this N_blocks times per loaded workout. Post-perf-003 it MUST
    /// stay at zero over a full `HistoryViewModel.load()`.
    var loadItemsCallCount: Int = 0
    /// Bulk fetch counter — `load()` should fire this at most twice
    /// (once for completed sessions, once for current program).
    var loadItemsBulkCallCount: Int = 0

    func loadAlternatives(workoutItemID: WorkoutItemID) async throws -> [ExerciseAlternative] {
        []
    }

    func loadExercises() async throws -> [Exercise] {
        exercises
    }

    func loadUserParametersLatest() async throws -> [String: UserParameter] {
        var latest: [String: UserParameter] = [:]
        for (key, rows) in userParametersByKey {
            if let newest = rows.max(by: { $0.updatedAt < $1.updatedAt }) {
                latest[key] = newest
            }
        }
        return latest
    }

    func loadUserParameters(key: String) async throws -> [UserParameter] {
        (userParametersByKey[key] ?? [])
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func loadCompletedWorkouts(limit: Int, offset: Int) async throws -> [Workout] {
        let completed = workouts
            .filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        let start = max(0, offset)
        guard start < completed.count, limit > 0 else { return [] }
        let end = min(completed.count, start + limit)
        return Array(completed[start..<end])
    }

    func loadSetLogs(workoutID: WorkoutID) async throws -> [SetLog] {
        setLogsByWorkout[workoutID] ?? []
    }

    func loadSetLogs(exerciseID: ExerciseID, limit: Int) async throws -> [SetLog] {
        guard limit > 0 else { return [] }
        let allItemIDs = itemsByBlock.values
            .flatMap { $0 }
            .filter { $0.exerciseID == exerciseID }
            .map(\.id)
        let itemIDSet = Set(allItemIDs)
        let allLogs = setLogsByWorkout.values.flatMap { $0 }
        let matching = allLogs.filter { log in
            if log.performedExerciseID == exerciseID { return true }
            return log.performedExerciseID == nil
                && itemIDSet.contains(log.workoutItemID)
        }
        return matching
            .sorted { $0.completedAt > $1.completedAt }
            .prefix(limit)
            .map { $0 }
    }

    func loadOrphanedSetLogs() async throws -> [SetLog] {
        // FakeHistoryCache doesn't model the post-V2→V3 orphan state —
        // none of the History feature tests drive the backfill-fallback
        // path. Returning empty keeps the fake honest about what it
        // does simulate.
        []
    }

    /// Records of every `saveSetLogs` call. Each entry is the full
    /// batch handed in. Used by the edit-past-set tests to assert the
    /// local write happens AND see the row it wrote.
    var savedSetLogBatches: [[SetLog]] = []

    /// Records the workoutID passed with each `saveSetLogs` call so
    /// tests can assert the R1.4 denormalization threading reached the
    /// cache. Paired with `savedSetLogBatches` by index.
    var savedSetLogWorkoutIDs: [WorkoutID] = []

    func saveSetLogs(_ setLogs: [SetLog], workoutID: WorkoutID) async throws {
        savedSetLogBatches.append(setLogs)
        savedSetLogWorkoutIDs.append(workoutID)
        // Upsert-by-id into the workout-indexed bucket. The fake
        // respects the caller's `workoutID` (R1.4 denormalization)
        // rather than scanning existing buckets — this matches the
        // real `WorkoutCacheImpl.saveSetLogs` contract and makes it
        // possible to land a brand-new row via this fake in tests.
        var bucket = setLogsByWorkout[workoutID] ?? []
        for newLog in setLogs {
            if let idx = bucket.firstIndex(where: { $0.id == newLog.id }) {
                bucket[idx] = newLog
            } else {
                bucket.append(newLog)
            }
        }
        setLogsByWorkout[workoutID] = bucket
    }

    func saveWorkout(_ workout: Workout) async throws {
        // Not used by the FeaturesHistory tests but required by the
        // protocol. No-op keeps behavior predictable.
    }

    func saveUserParameter(_ param: UserParameter) async throws {
        // Not used by the FeaturesHistory tests but required by the
        // protocol. No-op keeps behavior predictable.
    }

    func clear() async throws {}
}
