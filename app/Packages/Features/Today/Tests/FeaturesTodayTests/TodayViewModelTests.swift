// TodayViewModelTests.swift
//
// Given a constructed `TodayContext`, the view model produces the right
// display strings in the right order. No SwiftUI is exercised here —
// rendering is verified implicitly via previews.

import XCTest
import CoreDomain
import CoreSession
import Persistence
import WorkoutCoreFoundation
@testable import FeaturesToday

@MainActor
final class TodayViewModelTests: XCTestCase {

    func testDerivesSummariesInBlockAndPositionOrder() {
        let userID = UUID()
        let workoutID = UUID()
        let blockA = UUID()
        let blockB = UUID()
        let ex1 = UUID()
        let ex2 = UUID()
        let ex3 = UUID()
        let now = Date()

        let workout = Workout(
            id: workoutID, userID: userID, name: "Push A",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )

        // Two blocks, reversed on input, with items also reversed.
        // Expect final order: block A pos 0 → block A pos 1 → block B pos 0.
        let blocks = [
            Block(id: blockB, workoutID: workoutID, parentBlockID: nil,
                  position: 1, name: nil, timingMode: .straightSets,
                  timingConfigJSON: "{}", rounds: nil,
                  roundsRepSchemeJSON: nil, notes: nil),
            Block(id: blockA, workoutID: workoutID, parentBlockID: nil,
                  position: 0, name: nil, timingMode: .straightSets,
                  timingConfigJSON: "{}", rounds: nil,
                  roundsRepSchemeJSON: nil, notes: nil),
        ]

        let items = [
            WorkoutItem(id: UUID(), blockID: blockB, position: 0,
                        exerciseID: ex3,
                        prescriptionJSON: #"{"sets":3,"reps":10}"#),
            WorkoutItem(id: UUID(), blockID: blockA, position: 1,
                        exerciseID: ex2,
                        prescriptionJSON: #"{"sets":3,"reps":8,"load_kg":80}"#),
            WorkoutItem(id: UUID(), blockID: blockA, position: 0,
                        exerciseID: ex1,
                        prescriptionJSON: #"{"sets":4,"reps":5,"load_kg":102.5}"#),
        ]

        let exercises: [UUID: Exercise] = [
            ex1: Exercise(id: ex1, name: "Bench"),
            ex2: Exercise(id: ex2, name: "Row"),
            ex3: Exercise(id: ex3, name: "Dips"),
        ]

        let context = TodayContext(
            workout: workout,
            blocks: blocks,
            items: items,
            exercises: exercises,
            lastPerformed: [ex1: "5×5 @ 100 kg · RIR 2"],
            lastSessionSummary: "FRI · Push A · RIR 1.6 avg",
            programTags: ["week 3", "push day"]
        )

        let vm = TodayViewModel(context: context)

        XCTAssertEqual(vm.programName, "Push A")
        XCTAssertEqual(vm.programTags, ["week 3", "push day"])
        XCTAssertEqual(vm.lastSessionSummary, "FRI · Push A · RIR 1.6 avg")

        XCTAssertEqual(vm.exercises.count, 3)
        XCTAssertEqual(vm.exercises[0].name, "Bench")
        // R2.10: JSON fixtures in this test omit `weight_unit` → pound default.
        XCTAssertEqual(vm.exercises[0].prescriptionLine, "4 \u{00D7} 5 @ 102.5 lb")
        XCTAssertEqual(vm.exercises[0].lastTime, "5×5 @ 100 kg · RIR 2")

        XCTAssertEqual(vm.exercises[1].name, "Row")
        XCTAssertEqual(vm.exercises[1].prescriptionLine, "3 \u{00D7} 8 @ 80 lb")
        XCTAssertNil(vm.exercises[1].lastTime)

        XCTAssertEqual(vm.exercises[2].name, "Dips")
        // `{sets, reps}` with no load_kg discriminates as .bodyweight per
        // PrescriptionParser step 8 — renders as "3 × 10 BW".
        XCTAssertEqual(vm.exercises[2].prescriptionLine, "3 \u{00D7} 10 BW")
    }

    func testUnknownExerciseDoesNotCrash() {
        let workoutID = UUID()
        let blockID = UUID()
        let orphanExerciseID = UUID()
        let now = Date()

        let ctx = TodayContext(
            workout: Workout(
                id: workoutID, userID: UUID(), name: "X",
                scheduledDate: now, status: .planned, source: .claude,
                notes: nil, createdAt: now, updatedAt: now,
                completedAt: nil, tagsJSON: nil
            ),
            blocks: [Block(
                id: blockID, workoutID: workoutID, parentBlockID: nil,
                position: 0, name: nil, timingMode: .straightSets,
                timingConfigJSON: "{}", rounds: nil,
                roundsRepSchemeJSON: nil, notes: nil
            )],
            items: [WorkoutItem(
                id: UUID(), blockID: blockID, position: 0,
                exerciseID: orphanExerciseID,
                prescriptionJSON: #"{"sets":3,"reps":5,"load_kg":60}"#
            )],
            exercises: [:], // deliberately empty — item's exerciseID is orphan
            lastPerformed: [:]
        )

        let vm = TodayViewModel(context: ctx)
        XCTAssertEqual(vm.exercises.count, 1)
        XCTAssertEqual(vm.exercises[0].name, "(unknown exercise)")
        XCTAssertEqual(vm.exercises[0].prescriptionLine, "3 \u{00D7} 5 @ 60 lb")
    }

    func testStartDispatchesMutation() {
        final class CaptureBox: @unchecked Sendable {
            var captured: [SessionMutation] = []
        }
        let box = CaptureBox()

        let workoutID = UUID()
        let ctx = TodayContext(
            workout: Workout(
                id: workoutID, userID: UUID(), name: "X",
                scheduledDate: Date(), status: .planned, source: .claude,
                notes: nil, createdAt: Date(), updatedAt: Date(),
                completedAt: nil, tagsJSON: nil
            ),
            blocks: [],
            items: [],
            exercises: [:],
            lastPerformed: [:],
            sessionStateBinding: { m in box.captured.append(m) }
        )
        let vm = TodayViewModel(context: ctx)
        vm.start()
        XCTAssertEqual(box.captured, [.start])
    }

    // MARK: - Reload (bug-036)

    /// Seed two planned workouts, complete the first via a cache status
    /// flip, then call `reload`. The VM must advance to the second
    /// workout — previously the completed workout stayed on screen
    /// until relaunch.
    func testTodayViewModelReloadPicksNextPlannedAfterCompletion() async throws {
        let userID = UUID()
        let workout1ID = UUID()
        let workout2ID = UUID()
        let blockA = UUID()
        let blockB = UUID()
        let benchID = UUID()
        let squatID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Schedule workout 2 further in the past — both are past-or-today
        // candidates and `TodayLoader.pickClosest` picks the nearer one.
        // After workout 1 flips to `.completed`, the loader sees only
        // workout 2 as planned.
        let workout1 = Workout(
            id: workout1ID, userID: userID, name: "Push A",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let workout2 = Workout(
            id: workout2ID, userID: userID, name: "Pull A",
            scheduledDate: now.addingTimeInterval(-86_400),
            status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block1 = Block(
            id: blockA, workoutID: workout1ID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: "{}", rounds: nil,
            roundsRepSchemeJSON: nil, notes: nil
        )
        let block2 = Block(
            id: blockB, workoutID: workout2ID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: "{}", rounds: nil,
            roundsRepSchemeJSON: nil, notes: nil
        )
        let item1 = WorkoutItem(
            id: UUID(), blockID: blockA, position: 0,
            exerciseID: benchID,
            prescriptionJSON: #"{"sets":4,"reps":5,"load_kg":102.5}"#
        )
        let item2 = WorkoutItem(
            id: UUID(), blockID: blockB, position: 0,
            exerciseID: squatID,
            prescriptionJSON: #"{"sets":3,"reps":8,"load_kg":140}"#
        )

        let cache = MutableFakeCache(
            workouts: [workout1, workout2],
            blocks: [workout1ID: [block1], workout2ID: [block2]],
            items: [blockA: [item1], blockB: [item2]],
            exercises: [
                Exercise(id: benchID, name: "Bench"),
                Exercise(id: squatID, name: "Squat"),
            ]
        )
        let loader = TodayLoader(cache: cache, clock: { now })

        // Initial load → workout 1 (today, closer than workout 2).
        let firstCtx = try await loader.load()
        let ctx = try XCTUnwrap(firstCtx)
        let vm = TodayViewModel(context: ctx)
        XCTAssertEqual(vm.workoutID, workout1ID)
        XCTAssertEqual(vm.programName, "Push A")

        // Simulate save-and-done: flip workout 1 to `.completed` in the
        // cache. Workout 2 remains `.planned`.
        cache.markCompleted(workoutID: workout1ID)

        // Reload → VM must advance to workout 2.
        await vm.reload(using: loader)
        XCTAssertFalse(vm.isEmpty)
        XCTAssertEqual(vm.workoutID, workout2ID)
        XCTAssertEqual(vm.programName, "Pull A")
        XCTAssertEqual(vm.exercises.count, 1)
        XCTAssertEqual(vm.exercises.first?.name, "Squat")
    }

    /// qa-008 regression: the VM must expose `showsStartButton` that
    /// tracks `!isEmpty`. The view uses this to gate the pinned CTA —
    /// previously, the start button rendered even when `isEmpty == true`,
    /// producing a black screen with a disconnected "start workout"
    /// button after the last planned workout was completed.
    func testTodayViewShowsStartButtonWhenContextPresent() {
        let workoutID = UUID()
        let ctx = TodayContext(
            workout: Workout(
                id: workoutID, userID: UUID(), name: "Push A",
                scheduledDate: Date(), status: .planned, source: .claude,
                notes: nil, createdAt: Date(), updatedAt: Date(),
                completedAt: nil, tagsJSON: nil
            ),
            blocks: [],
            items: [],
            exercises: [:],
            lastPerformed: [:]
        )
        let vm = TodayViewModel(context: ctx)
        XCTAssertFalse(vm.isEmpty)
        XCTAssertTrue(vm.showsStartButton)
    }

    /// qa-008 regression: `showsStartButton` is `false` when the VM is
    /// in its empty-shaped state (S11 — reload returned `nil`). The
    /// view must hide the pinned "start workout" button in this case.
    func testTodayViewHidesStartButtonWhenEmpty() {
        let workoutID = UUID()
        let ctx = TodayContext(
            workout: Workout(
                id: workoutID, userID: UUID(), name: "Push A",
                scheduledDate: Date(), status: .planned, source: .claude,
                notes: nil, createdAt: Date(), updatedAt: Date(),
                completedAt: nil, tagsJSON: nil
            ),
            blocks: [],
            items: [],
            exercises: [:],
            lastPerformed: [:]
        )
        let vm = TodayViewModel(context: ctx)
        // Flip to empty-shaped state — models reload-to-empty (S11).
        vm.apply(nil)
        XCTAssertTrue(vm.isEmpty)
        XCTAssertFalse(vm.showsStartButton)
    }

    /// Seed a single planned workout, complete it, and reload. The
    /// loader returns nil; the VM must flip to empty-shaped so the UI
    /// renders the "nothing scheduled" glance.
    func testTodayViewModelReloadToEmptyWhenNoPlannedWorkouts() async throws {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let benchID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = Workout(
            id: workoutID, userID: userID, name: "Only",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: "{}", rounds: nil,
            roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: UUID(), blockID: blockID, position: 0,
            exerciseID: benchID,
            prescriptionJSON: #"{"sets":4,"reps":5,"load_kg":100}"#
        )

        let cache = MutableFakeCache(
            workouts: [workout],
            blocks: [workoutID: [block]],
            items: [blockID: [item]],
            exercises: [Exercise(id: benchID, name: "Bench")]
        )
        let loader = TodayLoader(cache: cache, clock: { now })

        let firstCtx = try await loader.load()
        let ctx = try XCTUnwrap(firstCtx)
        let vm = TodayViewModel(context: ctx)
        XCTAssertFalse(vm.isEmpty)
        XCTAssertEqual(vm.workoutID, workoutID)

        cache.markCompleted(workoutID: workoutID)

        await vm.reload(using: loader)
        XCTAssertTrue(vm.isEmpty)
        XCTAssertNil(vm.workoutID)
        XCTAssertEqual(vm.exercises, [])
        XCTAssertEqual(vm.programName, "")
        XCTAssertNil(vm.lastSessionSummary)
        XCTAssertEqual(vm.programTags, [])
        // qa-008: the pinned "start workout" CTA must be hidden in
        // this state — rendering it produces an orphaned button.
        XCTAssertFalse(vm.showsStartButton)
    }
}

// MARK: - Test cache

/// Minimal mutable `WorkoutCache` stand-in used by the reload tests.
/// `markCompleted(workoutID:)` flips the in-memory workout's status so
/// the next `TodayLoader.load()` skips it — models what the
/// `ExecutionViewModel.saveAndDone` → `WorkoutCache.saveWorkout` write
/// does in production without requiring a full in-memory SwiftData stack
/// here (FeaturesToday's test target deliberately stays off SwiftData —
/// see `Package.swift` test target note).
private final class MutableFakeCache: WorkoutCache, @unchecked Sendable {
    private let lock = NSLock()
    private var workouts: [Workout]
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

    func markCompleted(workoutID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        workouts = workouts.map { workout in
            guard workout.id == workoutID else { return workout }
            return Workout(
                id: workout.id,
                userID: workout.userID,
                name: workout.name,
                scheduledDate: workout.scheduledDate,
                status: .completed,
                source: workout.source,
                notes: workout.notes,
                createdAt: workout.createdAt,
                updatedAt: workout.updatedAt,
                completedAt: Date(),
                tagsJSON: workout.tagsJSON
            )
        }
    }

    func save(_ dataset: PulledDataset) async throws {}

    func loadWorkouts(status: WorkoutStatus?, since: Date?) async throws -> [Workout] {
        lock.lock()
        defer { lock.unlock() }
        guard let status else { return workouts }
        return workouts.filter { $0.status == status }
    }

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

    func saveWorkout(_ workout: Workout) async throws {
        lock.lock()
        defer { lock.unlock() }
        if let idx = workouts.firstIndex(where: { $0.id == workout.id }) {
            workouts[idx] = workout
        } else {
            workouts.append(workout)
        }
    }

    func saveUserParameter(_ param: UserParameter) async throws {}

    func clear() async throws {}
}
