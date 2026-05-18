// TodayLoaderTests.swift
//
// Exercises `TodayLoader` against a hand-rolled fake `WorkoutCache`. We
// don't import SwiftData — the loader is pure in terms of the protocol
// surface.

import XCTest
import CoreDomain
import CoreSession
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

    func testLoadAttachesPrimitiveWorkoutPlanAndNumericUserParameters() async throws {
        let userID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let scheduledDate = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = makeWorkout(userID: userID, name: "Primitive Push", scheduledDate: scheduledDate)
        let block = Block(
            id: blockID,
            workoutID: workout.id,
            parentBlockID: nil,
            position: 0,
            name: "Strength",
            timingMode: .straightSets,
            timingConfigJSON: "{}",
            rounds: nil,
            roundsRepSchemeJSON: nil,
            notes: nil
        )
        let item = WorkoutItem(
            id: UUID(),
            blockID: blockID,
            position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: #"{"sets":3,"reps":5,"percent_1rm":0.8}"#
        )
        let primitive = PrimitiveWorkout(
            id: workout.id,
            name: workout.name,
            blocks: [
                PrimitiveBlock(id: blockID, sets: [
                    PrimitiveSet(
                        id: UUID(),
                        timing: .init(mode: .setBounded),
                        slots: [
                            PrimitiveSlot(
                                id: UUID(),
                                exerciseID: exerciseID,
                                workTargets: [
                                    .init(metric: .reps, valueForm: .single, value: 5, role: .completion),
                                ],
                                load: .init(value: 0.8, unit: .oneRepMax, unitType: .relative)
                            ),
                        ]
                    ),
                ]),
            ]
        )
        let parameterKey = "one_rep_max_\(exerciseID.uuidString.lowercased())_kg"
        let fake = FakeCache(
            workouts: [workout],
            blocks: [workout.id: [block]],
            items: [blockID: [item]],
            exercises: [Exercise(id: exerciseID, name: "Bench")],
            primitiveWorkouts: [primitive],
            userParameters: [
                parameterKey: UserParameter(
                    id: UUID(),
                    userID: userID,
                    key: parameterKey,
                    value: "150",
                    updatedAt: scheduledDate,
                    source: .manual
                ),
                "ignored": UserParameter(
                    id: UUID(),
                    userID: userID,
                    key: "ignored",
                    value: "not numeric",
                    updatedAt: scheduledDate,
                    source: .manual
                ),
            ]
        )
        let loader = TodayLoader(cache: fake, clock: { scheduledDate })

        let loaded = try await loader.load()
        let ctx = try XCTUnwrap(loaded)

        XCTAssertEqual(ctx.primitiveWorkout, primitive)
        XCTAssertEqual(ctx.userParameters, [parameterKey: 150])
        XCTAssertEqual(ctx.primitiveExecutionPlan?.blocks[0].sets[0].slots[0].loadKg, 120)
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

    func testLoadPlanReturnsMissedTodayAndUpcomingQueueWithTodaySelected() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let userID = UUID()
        let missed = makeWorkout(
            userID: userID,
            name: "Missed Lower",
            scheduledDate: now.addingTimeInterval(-86_400)
        )
        let today = makeWorkout(
            userID: userID,
            name: "Today Push",
            scheduledDate: now
        )
        let tomorrow = makeWorkout(
            userID: userID,
            name: "Tomorrow Conditioning",
            scheduledDate: now.addingTimeInterval(86_400)
        )

        let fake = FakeCache(
            workouts: [tomorrow, missed, today],
            blocks: [:],
            items: [:],
            exercises: []
        )
        let loader = TodayLoader(cache: fake, clock: { now })

        let plan = try await loader.loadPlan()
        let unwrapped = try XCTUnwrap(plan)
        XCTAssertEqual(unwrapped.selected.workout.id, today.id)
        XCTAssertEqual(
            unwrapped.workouts.map(\.workout.name),
            ["Today Push", "Missed Lower", "Tomorrow Conditioning"]
        )
    }

    func testLoadPlanAttachesPrimitivePlansAndResolvesNumericUserParameters() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let userID = UUID()
        let exerciseID = UUID()
        let today = makeWorkout(
            userID: userID,
            name: "Today Primitive",
            scheduledDate: now
        )
        let block = Block(
            id: UUID(),
            workoutID: today.id,
            parentBlockID: nil,
            position: 0,
            name: "Strength",
            timingMode: .straightSets,
            timingConfigJSON: "{}",
            rounds: nil,
            roundsRepSchemeJSON: nil,
            notes: nil
        )
        let item = WorkoutItem(
            id: UUID(),
            blockID: block.id,
            position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: #"{"sets":3,"reps":5,"percent_1rm":0.8}"#
        )
        let primitive = PrimitiveWorkout(
            id: today.id,
            name: today.name,
            blocks: [
                PrimitiveBlock(id: block.id, sets: [
                    PrimitiveSet(
                        id: UUID(),
                        timing: .init(mode: .setBounded),
                        slots: [
                            PrimitiveSlot(
                                id: UUID(),
                                exerciseID: exerciseID,
                                workTargets: [
                                    .init(metric: .reps, valueForm: .single, value: 5, role: .completion),
                                ],
                                load: .init(value: 0.8, unit: .oneRepMax, unitType: .relative)
                            ),
                        ]
                    ),
                ]),
            ]
        )
        let parameterKey = "one_rep_max_\(exerciseID.uuidString.lowercased())_kg"
        let fake = FakeCache(
            workouts: [today],
            blocks: [today.id: [block]],
            items: [block.id: [item]],
            exercises: [Exercise(id: exerciseID, name: "Bench")],
            primitiveWorkouts: [primitive],
            userParameters: [
                parameterKey: UserParameter(
                    id: UUID(),
                    userID: userID,
                    key: parameterKey,
                    value: "150",
                    updatedAt: now,
                    source: .manual
                ),
            ]
        )
        let loader = TodayLoader(cache: fake, clock: { now })

        let plan = try await loader.loadPlan()
        let selected = try XCTUnwrap(plan?.selected)

        XCTAssertEqual(selected.primitiveWorkout, primitive)
        XCTAssertEqual(selected.userParameters, [parameterKey: 150])
        XCTAssertEqual(selected.primitiveExecutionPlan?.blocks[0].sets[0].slots[0].loadKg, 120)
        XCTAssertEqual(plan?.workouts.first?.primitiveExecutionPlan?.blocks[0].sets[0].slots[0].loadKg, 120)
    }

    func testLoadPlanLoadsPrimitiveOnlyExerciseCatalogEntries() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = makeWorkout(name: "Primitive only", scheduledDate: now)
        let block = makeBlock(workoutID: workout.id, name: "Main")
        let exerciseID = UUID()
        let primitive = PrimitiveWorkout(
            id: workout.id,
            name: workout.name,
            blocks: [
                PrimitiveBlock(id: block.id, sets: [
                    PrimitiveSet(
                        id: UUID(),
                        timing: .init(mode: .setBounded),
                        slots: [
                            PrimitiveSlot(
                                id: UUID(),
                                exerciseID: exerciseID,
                                workTargets: [
                                    .init(metric: .reps, valueForm: .single, value: 5, role: .completion),
                                ]
                            ),
                        ]
                    ),
                ]),
            ]
        )
        let fake = FakeCache(
            workouts: [workout],
            blocks: [workout.id: [block]],
            items: [:],
            exercises: [Exercise(id: exerciseID, name: "Kettlebell swing")],
            primitiveWorkouts: [primitive]
        )
        let loader = TodayLoader(cache: fake, clock: { now })

        let plan = try await loader.loadPlan()

        XCTAssertEqual(plan?.selected.exercises[exerciseID]?.name, "Kettlebell swing")
    }

    func testLoadPlanFailsWhenSelectedPrimitivePlanIsInvalid() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let selected = makeWorkout(name: "Selected", scheduledDate: now)
        let selectedBlock = makeBlock(workoutID: selected.id, name: "Selected block")
        let invalidPrimitive = PrimitiveWorkout(
            id: selected.id,
            name: selected.name,
            blocks: [
                PrimitiveBlock(id: selectedBlock.id, sets: [
                    PrimitiveSet(
                        id: UUID(),
                        timing: .init(mode: .setBounded),
                        traversal: .amrap,
                        slots: [
                            PrimitiveSlot(id: UUID(), exerciseID: UUID(), workTargets: []),
                        ]
                    ),
                ]),
            ]
        )
        let fake = FakeCache(
            workouts: [selected],
            blocks: [selected.id: [selectedBlock]],
            items: [:],
            exercises: [],
            primitiveWorkouts: [invalidPrimitive]
        )
        let loader = TodayLoader(cache: fake, clock: { now })

        do {
            _ = try await loader.loadPlan()
            XCTFail("loadPlan must surface invalid selected primitive workouts")
        } catch {
            XCTAssertTrue(error is PrimitiveSemanticError)
        }
    }

    func testLoadPlanContainsInvalidPrimitivePlanForNonSelectedWorkout() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let selected = makeWorkout(name: "Selected", scheduledDate: now)
        let nonSelected = makeWorkout(name: "Non selected", scheduledDate: now.addingTimeInterval(3600))
        let selectedBlock = makeBlock(workoutID: selected.id, name: "Selected block")
        let nonSelectedBlock = makeBlock(workoutID: nonSelected.id, name: "Non selected block")
        let invalidPrimitive = PrimitiveWorkout(
            id: nonSelected.id,
            name: nonSelected.name,
            blocks: [
                PrimitiveBlock(id: nonSelectedBlock.id, sets: [
                    PrimitiveSet(
                        id: UUID(),
                        timing: .init(mode: .setBounded),
                        traversal: .amrap,
                        slots: [
                            PrimitiveSlot(id: UUID(), exerciseID: UUID(), workTargets: []),
                        ]
                    ),
                ]),
            ]
        )
        let fake = FakeCache(
            workouts: [selected, nonSelected],
            blocks: [selected.id: [selectedBlock], nonSelected.id: [nonSelectedBlock]],
            items: [:],
            exercises: [],
            primitiveWorkouts: [invalidPrimitive]
        )
        let loader = TodayLoader(cache: fake, clock: { now })

        let plan = try await loader.loadPlan()
        let context = try XCTUnwrap(plan?.workouts.first { $0.workout.id == nonSelected.id })

        XCTAssertEqual(context.primitiveWorkout, invalidPrimitive)
        XCTAssertNil(context.primitiveExecutionPlan)
    }

    func testLoadPlanSurfacesUserParameterReadFailureForSelectedWorkout() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = makeWorkout(name: "Selected", scheduledDate: now)
        let block = makeBlock(workoutID: workout.id, name: "Selected block")
        let exerciseID = UUID()
        let primitive = PrimitiveWorkout(
            id: workout.id,
            name: workout.name,
            blocks: [
                PrimitiveBlock(id: block.id, sets: [
                    PrimitiveSet(
                        id: UUID(),
                        timing: .init(mode: .setBounded),
                        slots: [
                            PrimitiveSlot(
                                id: UUID(),
                                exerciseID: exerciseID,
                                workTargets: [
                                    .init(metric: .reps, valueForm: .single, value: 5, role: .completion),
                                ]
                            ),
                        ]
                    ),
                ]),
            ]
        )
        let fake = FakeCache(
            workouts: [workout],
            blocks: [workout.id: [block]],
            items: [:],
            exercises: [],
            primitiveWorkouts: [primitive],
            userParametersError: TestError.userParameters
        )
        let loader = TodayLoader(cache: fake, clock: { now })

        do {
            _ = try await loader.loadPlan()
            XCTFail("loadPlan must keep selected primitive execution aligned with start")
        } catch {
            XCTAssertEqual(error as? TestError, .userParameters)
        }
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
        makeWorkout(userID: UUID(), name: name, scheduledDate: scheduledDate)
    }

    private func makeWorkout(userID: UUID, name: String, scheduledDate: Date?) -> Workout {
        Workout(
            id: UUID(), userID: userID, name: name,
            scheduledDate: scheduledDate, status: .planned, source: .claude,
            notes: nil, createdAt: Date(), updatedAt: Date(),
            completedAt: nil, tagsJSON: nil
        )
    }

    private func makeBlock(workoutID: UUID, name: String?) -> Block {
        Block(
            id: UUID(),
            workoutID: workoutID,
            parentBlockID: nil,
            position: 0,
            name: name,
            timingMode: .straightSets,
            timingConfigJSON: "{}",
            rounds: nil,
            roundsRepSchemeJSON: nil,
            notes: nil
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
    private let primitiveWorkouts: [PrimitiveWorkout]
    private let userParameters: [String: UserParameter]
    private let userParametersError: Error?

    init(
        workouts: [Workout],
        blocks: [UUID: [Block]],
        items: [UUID: [WorkoutItem]],
        exercises: [Exercise],
        primitiveWorkouts: [PrimitiveWorkout] = [],
        userParameters: [String: UserParameter] = [:],
        userParametersError: Error? = nil
    ) {
        self.workouts = workouts
        self.blocksByWorkout = blocks
        self.itemsByBlock = items
        self.exercises = exercises
        self.primitiveWorkouts = primitiveWorkouts
        self.userParameters = userParameters
        self.userParametersError = userParametersError
    }

    func save(_ dataset: PulledDataset) async throws {}

    func loadWorkouts(status: WorkoutStatus?, since: Date?) async throws -> [Workout] {
        guard let status else { return workouts }
        return workouts.filter { $0.status == status }
    }

    func loadPrimitiveWorkouts() async throws -> [PrimitiveWorkout] { primitiveWorkouts }

    func loadBlocks(workoutID: WorkoutID) async throws -> [Block] {
        blocksByWorkout[workoutID] ?? []
    }

    func loadItems(blockID: BlockID) async throws -> [WorkoutItem] {
        itemsByBlock[blockID] ?? []
    }

    func loadItems(
        workoutIDs: [WorkoutID]
    ) async throws -> [WorkoutID: [WorkoutItem]] {
        guard !workoutIDs.isEmpty else { return [:] }
        let wanted = Set(workoutIDs)
        var out: [WorkoutID: [WorkoutItem]] = [:]
        for (workoutID, blocks) in blocksByWorkout where wanted.contains(workoutID) {
            var items: [WorkoutItem] = []
            for block in blocks.sorted(by: { $0.position < $1.position }) {
                items.append(contentsOf: itemsByBlock[block.id] ?? [])
            }
            if !items.isEmpty { out[workoutID] = items }
        }
        return out
    }

    func loadAlternatives(workoutItemID: WorkoutItemID) async throws -> [ExerciseAlternative] {
        []
    }

    func loadExercises() async throws -> [Exercise] {
        exercises
    }

    func loadUserParametersLatest() async throws -> [String: UserParameter] {
        if let userParametersError {
            throw userParametersError
        }
        return userParameters
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

    func loadPrimitiveSetLogs(workoutID: WorkoutID) async throws -> [PrimitiveSetLog] { [] }

    func loadSetLogs(exerciseID: ExerciseID, limit: Int) async throws -> [SetLog] {
        []
    }

    func loadOrphanedSetLogs() async throws -> [SetLog] { [] }

    func saveSetLogs(_ setLogs: [SetLog], workoutID: WorkoutID) async throws {}

    func savePrimitiveSetLogs(_ setLogs: [PrimitiveSetLog], workoutID: WorkoutID) async throws {}

    func resetWorkout(workoutID: WorkoutID) async throws {}

    func saveWorkout(_ workout: Workout) async throws {}

    func saveUserParameter(_ param: UserParameter) async throws {}

    func clear() async throws {}
}

private enum TestError: Error, Equatable {
    case userParameters
}
