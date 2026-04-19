// TodayLoaderTests.swift
//
// Exercises `TodayLoader` against a hand-rolled fake `WorkoutCache`. We
// don't import SwiftData — the loader is pure in terms of the protocol
// surface.

import XCTest
import CoreDomain
import Persistence
import WorkoutCoreFoundation
@testable import FeaturesToday

final class TodayLoaderTests: XCTestCase {

    func testLoadReturnsContextForPlannedWorkout() async throws {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let benchID = UUID()
        let rowID = UUID()
        let scheduledDate = Date(timeIntervalSince1970: 1_700_000_000)

        let workout = Workout(
            id: workoutID, userID: userID, name: "Push A",
            scheduledDate: scheduledDate, status: .planned, source: .claude,
            notes: nil, createdAt: scheduledDate, updatedAt: scheduledDate,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: "{}", rounds: nil,
            roundsRepSchemeJSON: nil, notes: nil
        )
        let items = [
            WorkoutItem(id: UUID(), blockID: blockID, position: 0,
                        exerciseID: benchID,
                        prescriptionJSON: #"{"sets":4,"reps":5,"load_kg":102.5}"#),
            WorkoutItem(id: UUID(), blockID: blockID, position: 1,
                        exerciseID: rowID,
                        prescriptionJSON: #"{"sets":3,"reps":8,"load_kg":80}"#),
        ]
        let exercises = [
            Exercise(id: benchID, name: "Bench"),
            Exercise(id: rowID, name: "Row"),
            // An extra exercise that no item references — it must not
            // leak into the returned context.
            Exercise(id: UUID(), name: "Unused"),
        ]

        let fake = FakeCache(
            workouts: [workout],
            blocks: [workoutID: [block]],
            items: [blockID: items],
            exercises: exercises
        )
        let loader = TodayLoader(cache: fake, clock: { scheduledDate })

        let ctx = try await loader.load()
        let unwrapped = try XCTUnwrap(ctx)
        XCTAssertEqual(unwrapped.workout.id, workoutID)
        XCTAssertEqual(unwrapped.blocks.map(\.id), [blockID])
        XCTAssertEqual(unwrapped.items.count, 2)
        XCTAssertEqual(unwrapped.exercises.count, 2)
        XCTAssertNotNil(unwrapped.exercises[benchID])
        XCTAssertNotNil(unwrapped.exercises[rowID])
    }

    func testLoadReturnsNilWhenNoPlannedWorkout() async throws {
        let fake = FakeCache(
            workouts: [],
            blocks: [:],
            items: [:],
            exercises: []
        )
        let loader = TodayLoader(cache: fake, clock: { Date() })
        let ctx = try await loader.load()
        XCTAssertNil(ctx)
    }

    func testPickClosest_prefersPastOrTodayOverFuture() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let past = makeWorkout(name: "past", scheduledDate: now.addingTimeInterval(-3 * 86400))
        let futureClose = makeWorkout(name: "future", scheduledDate: now.addingTimeInterval(1 * 3600))
        let pickedA = TodayLoader.pickClosest(to: now, from: [futureClose, past])
        // Even though future is temporally closer (1h vs 3d), past wins
        // because past-or-today ranks ahead of future.
        XCTAssertEqual(pickedA?.name, "past")

        let todayMorning = makeWorkout(name: "today", scheduledDate: now.addingTimeInterval(-6 * 3600))
        let pickedB = TodayLoader.pickClosest(to: now, from: [past, todayMorning])
        // Today (6h ago) beats past (3d ago) — both are in the past group,
        // closer absolute distance wins.
        XCTAssertEqual(pickedB?.name, "today")
    }

    // MARK: - Helpers

    private func makeWorkout(name: String, scheduledDate: Date?) -> Workout {
        Workout(
            id: UUID(), userID: UUID(), name: name,
            scheduledDate: scheduledDate, status: .planned, source: .claude,
            notes: nil, createdAt: Date(), updatedAt: Date(),
            completedAt: nil, tagsJSON: nil
        )
    }
}

// MARK: - Fake cache

/// Minimal `WorkoutCache` fake that returns injected data. The loader
/// only reads from the cache; write methods are no-ops.
private final class FakeCache: WorkoutCache, @unchecked Sendable {
    private let workouts: [Workout]
    private let blocksByWorkout: [UUID: [Block]]
    private let itemsByBlock: [UUID: [WorkoutItem]]
    private let exercises: [Exercise]

    init(
        workouts: [Workout],
        blocks: [UUID: [Block]],
        items: [UUID: [WorkoutItem]],
        exercises: [Exercise]
    ) {
        self.workouts = workouts
        self.blocksByWorkout = blocks
        self.itemsByBlock = items
        self.exercises = exercises
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

    func loadUserParameters(key: String) async throws -> [UserParameter] {
        []
    }

    func loadCompletedWorkouts(limit: Int, offset: Int) async throws -> [Workout] {
        []
    }

    func loadSetLogs(workoutID: WorkoutID) async throws -> [SetLog] {
        []
    }

    func loadSetLogs(exerciseID: ExerciseID, limit: Int) async throws -> [SetLog] {
        []
    }

    func loadOrphanedSetLogs() async throws -> [SetLog] { [] }

    func saveSetLogs(_ setLogs: [SetLog], workoutID: WorkoutID) async throws {}

    func saveWorkout(_ workout: Workout) async throws {}

    func saveUserParameter(_ param: UserParameter) async throws {}

    func clear() async throws {}
}
