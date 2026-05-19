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

        // Single bulk fetch replaces the per-workout block-and-item
        // walk. For N completed workouts with ~3 blocks each the prior
        // shape issued ~4N cache round-trips just to build
        // `plannedExerciseByItem`; this is 2 total regardless of N.
        let itemsByWorkout = try await cache.loadItems(
            workoutIDs: completed.map(\.id)
        )

        let primitiveWorkouts = try await cache.loadPrimitiveWorkouts()
        let primitiveWorkoutByID = Dictionary(
            uniqueKeysWithValues: primitiveWorkouts.map { ($0.id, $0) }
        )

        var sessions: [SessionDetail] = []
        sessions.reserveCapacity(completed.count)
        for workout in completed {
            let session = try await buildSession(
                for: workout,
                items: itemsByWorkout[workout.id] ?? [],
                primitiveWorkout: primitiveWorkoutByID[workout.id],
                bodyweightHistory: bodyweightHistory
            )
            sessions.append(session)
        }
        rawSessions = sessions
    }

    /// Fetch per-workout data (set_logs + item lookup) for one workout.
    /// `items` comes from the bulk `loadItems(workoutIDs:)` fetch in
    /// `loadCompleted` so this path is a single set_logs round-trip.
    private func buildSession(
        for workout: Workout,
        items: [WorkoutItem],
        primitiveWorkout: PrimitiveWorkout?,
        bodyweightHistory: [UserParameter]
    ) async throws -> SessionDetail {
        let logs = try await cache.loadSetLogs(workoutID: workout.id)
        let primitiveLogs = try await cache.loadPrimitiveSetLogs(workoutID: workout.id)
        var lookup: [WorkoutItemID: ExerciseID] = [:]
        lookup.reserveCapacity(items.count)
        for item in items {
            lookup[item.id] = item.exerciseID
        }
        if let primitiveWorkout {
            for block in primitiveWorkout.blocks {
                for set in block.sets {
                    for slot in set.slots {
                        lookup[slot.id] = slot.exerciseID
                    }
                }
            }
        }
        let bodyweight = Self.bodyweight(
            for: workout,
            setLogs: logs,
            primitiveSetLogs: primitiveLogs,
            history: bodyweightHistory
        )
        return SessionDetail(
            workout: workout,
            setLogs: primitiveWorkout == nil ? logs : [],
            primitiveSetLogs: primitiveLogs,
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
        primitiveSetLogs: [PrimitiveSetLog] = [],
        history: [UserParameter]
    ) -> Double? {
        guard let completedAt = workout.completedAt else { return nil }
        let end = completedAt.addingTimeInterval(120)
        let primitiveStart = primitiveSetLogs.map(\.completedAt).min()
        let start: Date = primitiveStart
            ?? setLogs.compactMap(\.startedAt).min()
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
        guard !planned.isEmpty else {
            currentProgramExerciseIDs = []
            return
        }
        // Bulk fetch every planned item in two cache round-trips instead
        // of `1 + N_blocks` per workout.
        let itemsByWorkout = try await cache.loadItems(
            workoutIDs: planned.map(\.id)
        )
        var currentIDs: Set<ExerciseID> = []
        for items in itemsByWorkout.values {
            for item in items {
                currentIDs.insert(item.exerciseID)
            }
        }
        currentProgramExerciseIDs = currentIDs
    }
}
