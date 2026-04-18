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

    init(
        workouts: [Workout] = [],
        blocksByWorkout: [UUID: [Block]] = [:],
        itemsByBlock: [UUID: [WorkoutItem]] = [:],
        exercises: [Exercise] = [],
        setLogsByWorkout: [UUID: [SetLog]] = [:]
    ) {
        self.workouts = workouts
        self.blocksByWorkout = blocksByWorkout
        self.itemsByBlock = itemsByBlock
        self.exercises = exercises
        self.setLogsByWorkout = setLogsByWorkout
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
        itemsByBlock[blockID] ?? []
    }

    func loadAlternatives(workoutItemID: WorkoutItemID) async throws -> [ExerciseAlternative] {
        []
    }

    func loadExercises() async throws -> [Exercise] {
        exercises
    }

    func loadUserParametersLatest() async throws -> [String: UserParameter] {
        [:]
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

    /// Records of every `saveSetLogs` call. Each entry is the full
    /// batch handed in. Used by the edit-past-set tests to assert the
    /// local write happens AND see the row it wrote.
    var savedSetLogBatches: [[SetLog]] = []

    func saveSetLogs(_ setLogs: [SetLog]) async throws {
        savedSetLogBatches.append(setLogs)
        // Mirror the update into `setLogsByWorkout` so `load()`
        // re-reads the edited values on the next `loadSetLogs(workoutID:)`
        // call. Real `WorkoutCacheImpl.saveSetLogs` upserts rows in
        // SwiftData; this fake upserts by `id` in the flat array.
        for newLog in setLogs {
            var attached = false
            for (workoutID, logs) in setLogsByWorkout {
                if logs.contains(where: { $0.id == newLog.id }) {
                    setLogsByWorkout[workoutID] = logs.map { old in
                        old.id == newLog.id ? newLog : old
                    }
                    attached = true
                    break
                }
            }
            if !attached {
                // Not tied to an existing workout in the fake — drop
                // silently. Matches the "caller is responsible for
                // passing coherent data" contract; none of the shipping
                // tests exercise this path today.
                _ = attached
            }
        }
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
