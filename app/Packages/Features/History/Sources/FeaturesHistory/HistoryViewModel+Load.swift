// HistoryViewModel+Load.swift
//
// Loading + source-of-truth refresh split out so the main
// HistoryViewModel file stays under SwiftLint's type_body_length cap.
// All mutation still flows through the main-actor VM.

import Foundation
import CoreDomain
import Persistence
import WorkoutCoreFoundation

extension HistoryViewModel {

    /// Load everything once. Re-run on pull-to-refresh or after a
    /// corrective edit. Safe to call multiple times — overwrites the
    /// cached shapes.
    public func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await loadCompleted()
            try await loadCurrentProgram()
            rederive()
        } catch {
            // Errors during history load are never fatal — the surface is
            // read-only and offline. Leave the cached shapes as they were.
            rederive()
        }
    }

    /// Pull completed workouts + their set_logs + items. `rawSessions`
    /// is the source of truth for every derived shape.
    func loadCompleted() async throws {
        let completed = try await cache.loadCompletedWorkouts(
            limit: workoutFetchLimit,
            offset: 0
        )
        let exercises = try await cache.loadExercises()
        exerciseName = Dictionary(
            uniqueKeysWithValues: exercises.map { ($0.id, $0.name) }
        )

        var sessions: [SessionDetail] = []
        for workout in completed {
            let session = try await buildSession(for: workout)
            sessions.append(session)
        }
        rawSessions = sessions
    }

    /// Fetch per-workout data (set_logs + item lookup) for one workout.
    private func buildSession(for workout: Workout) async throws -> SessionDetail {
        let logs = try await cache.loadSetLogs(workoutID: workout.id)
        let blocks = try await cache.loadBlocks(workoutID: workout.id)
        var lookup: [WorkoutItemID: ExerciseID] = [:]
        for block in blocks {
            let items = try await cache.loadItems(blockID: block.id)
            for item in items {
                lookup[item.id] = item.exerciseID
            }
        }
        return SessionDetail(
            workout: workout,
            setLogs: logs,
            plannedExerciseByItem: lookup
        )
    }

    /// Pull planned workouts' exercise ids so the picker can group
    /// "current program" vs "past programs".
    func loadCurrentProgram() async throws {
        let planned = try await cache.loadWorkouts(
            status: .planned,
            since: nil
        )
        var currentIDs: Set<ExerciseID> = []
        for workout in planned {
            let blocks = try await cache.loadBlocks(workoutID: workout.id)
            for block in blocks {
                let items = try await cache.loadItems(blockID: block.id)
                for item in items {
                    currentIDs.insert(item.exerciseID)
                }
            }
        }
        currentProgramExerciseIDs = currentIDs
    }
}
