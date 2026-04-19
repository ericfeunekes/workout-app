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

        // Load all bodyweight history once — per-session window lookup
        // then filters this slice. The `user_parameters` log is append-
        // only but small (O(workouts) rows for the single user), so
        // pulling the full key history up-front is cheaper than
        // round-tripping the cache per session.
        // Literal key matches `ExecutionViewModel.enqueueBodyweight` — the
        // sole writer. A typed enum would belong in CoreDomain once a
        // second key appears; today it's one string in one call site.
        let bodyweightHistory = try await cache.loadUserParameters(
            key: "bodyweight_kg"
        )

        var sessions: [SessionDetail] = []
        for workout in completed {
            let session = try await buildSession(
                for: workout,
                bodyweightHistory: bodyweightHistory
            )
            sessions.append(session)
        }
        rawSessions = sessions
    }

    /// Fetch per-workout data (set_logs + item lookup) for one workout.
    private func buildSession(
        for workout: Workout,
        bodyweightHistory: [UserParameter]
    ) async throws -> SessionDetail {
        let logs = try await cache.loadSetLogs(workoutID: workout.id)
        let blocks = try await cache.loadBlocks(workoutID: workout.id)
        var lookup: [WorkoutItemID: ExerciseID] = [:]
        for block in blocks {
            let items = try await cache.loadItems(blockID: block.id)
            for item in items {
                lookup[item.id] = item.exerciseID
            }
        }
        let bodyweight = Self.bodyweight(
            for: workout,
            setLogs: logs,
            history: bodyweightHistory
        )
        return SessionDetail(
            workout: workout,
            setLogs: logs,
            plannedExerciseByItem: lookup,
            bodyweightKg: bodyweight
        )
    }

    /// Find the bodyweight captured during this workout's wall-clock
    /// window. `saveAndDone` fires the bodyweight user_parameter with
    /// `observedAt = clock.now` at completion time, so the match is
    /// typically within a second or two of `completedAt`. We allow a
    /// +2min grace window past `completedAt` to tolerate a late push
    /// flush (the enqueue is synchronous but the row write is fire-and-
    /// forget) and backdate the start of the window to the first
    /// logged set's `startedAt` / `completedAt` (falling back to
    /// `scheduledDate`) so a pre-workout weigh-in also binds to this
    /// session. Returns nil when no matching row exists — the header
    /// then renders without the "82 KG BW" chip.
    static func bodyweight(
        for workout: Workout,
        setLogs: [SetLog],
        history: [UserParameter]
    ) -> Double? {
        guard let completedAt = workout.completedAt else { return nil }
        let end = completedAt.addingTimeInterval(120)
        let start: Date = setLogs.compactMap(\.startedAt).min()
            ?? setLogs.map(\.completedAt).min()
            ?? workout.scheduledDate
            ?? completedAt.addingTimeInterval(-3 * 60 * 60)
        // `history` is newest-first; the first row whose timestamp
        // sits inside [start, end] wins — that's the most recent
        // capture bound to this session.
        for row in history where row.updatedAt >= start && row.updatedAt <= end {
            return Double(row.value)
        }
        return nil
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
