// ExecutionViewModelSwapTests.swift
//
// Covers the exercise-swap intent on ExecutionViewModel — the entry point
// for bug-008 (UI / VM wiring) and bug-009 (parameter_overrides_json
// application).
//
// Contract under test:
//   1. `swap(itemID:, alternativeID:)` dispatches `.swap` through the
//      reducer, setting `performedExerciseID` on the target item.
//   2. When the alternative carries `parameter_overrides_json`, reps /
//      load_kg overrides land on the remaining non-done SetPlan rows;
//      `target_rir` lands on `ItemLog.overrides` for StraightSetsDriver
//      to read on the next log.
//   3. Already-logged (done) sets are preserved bit-for-bit — neither
//      the override nor the swap itself touches historical rows.
//   4. A swap with no override behaves like a pure exercise substitution.
//   5. Telemetry fires an `execution.exercise_swap` event with the
//      from/to exerciseIDs and the `had_overrides` flag.
//   6. Target-rir override shadows the prescription's authored target
//      so a subsequent log triggers autoreg against the swapped stimulus.

import XCTest
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import CoreTelemetry
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class ExecutionViewModelSwapTests: XCTestCase {

    // MARK: - Pure swap (no overrides)

    func testSwapWithNoOverridesBehavesLikePureSwap() {
        let fixture = makeContext()
        let vm = ExecutionViewModel(context: fixture.context)
        vm.start()

        vm.swap(itemID: fixture.itemID, alternativeID: fixture.altID)

        let itemLog = vm.state.items.first(where: { $0.itemID == fixture.itemID })
        XCTAssertEqual(itemLog?.performedExerciseID, fixture.altExerciseID)
        XCTAssertNil(itemLog?.overrides, "no overrides authored → field stays nil")
        // Sets unchanged (loadKg=100, reps=5).
        XCTAssertTrue(itemLog?.sets.allSatisfy { $0.loadKg == 100 && $0.reps == 5 } ?? false)
    }

    // MARK: - Reps / load overrides

    func testSwapAppliesLoadOverrideToRemainingSets() {
        let fixture = makeContext(overridesJSON: #"{"load_kg":72.5}"#)
        let vm = ExecutionViewModel(context: fixture.context)
        vm.start()

        vm.swap(itemID: fixture.itemID, alternativeID: fixture.altID)

        let itemLog = vm.state.items.first(where: { $0.itemID == fixture.itemID })
        XCTAssertNotNil(itemLog?.overrides)
        XCTAssertEqual(itemLog?.overrides?.loadKg, 72.5)
        XCTAssertTrue(
            itemLog?.sets.allSatisfy { $0.loadKg == 72.5 } ?? false,
            "every non-done SetPlan row should carry the override load"
        )
        XCTAssertTrue(
            itemLog?.sets.allSatisfy { $0.reps == 5 } ?? false,
            "reps unchanged when only load was overridden"
        )
    }

    func testSwapAppliesRepsOverrideToRemainingSets() {
        let fixture = makeContext(overridesJSON: #"{"reps":8}"#)
        let vm = ExecutionViewModel(context: fixture.context)
        vm.start()

        vm.swap(itemID: fixture.itemID, alternativeID: fixture.altID)

        let itemLog = vm.state.items.first(where: { $0.itemID == fixture.itemID })
        XCTAssertEqual(itemLog?.overrides?.reps, 8)
        XCTAssertTrue(itemLog?.sets.allSatisfy { $0.reps == 8 } ?? false)
        XCTAssertTrue(
            itemLog?.sets.allSatisfy { $0.loadKg == 100 } ?? false,
            "load unchanged when only reps was overridden"
        )
    }

    // MARK: - Logged sets preserved

    func testSwapPreservesAlreadyDoneSets() {
        let fixture = makeContext(overridesJSON: #"{"load_kg":70,"reps":8}"#)
        let vm = ExecutionViewModel(context: fixture.context)
        vm.start()
        // Log set 1 at the original prescription values.
        vm.logSet(reps: 5, rir: 2)

        vm.swap(itemID: fixture.itemID, alternativeID: fixture.altID)

        let itemLog = vm.state.items.first(where: { $0.itemID == fixture.itemID })
        let setOne = itemLog?.sets.first(where: { $0.setIndex == 1 })
        XCTAssertEqual(setOne?.done, true, "logged set stays logged post-swap")
        XCTAssertEqual(setOne?.reps, 5, "logged reps preserved (pre-swap observation)")
        XCTAssertEqual(setOne?.loadKg, 100, "logged load preserved (pre-swap prescription)")

        // Remaining (pending) sets should carry the override.
        let remaining = itemLog?.sets.filter { !$0.done } ?? []
        XCTAssertFalse(remaining.isEmpty)
        XCTAssertTrue(remaining.allSatisfy { $0.loadKg == 70 && $0.reps == 8 })
    }

    // MARK: - target_rir override shadows prescription

    func testSwapTargetRirOverrideShadowsPrescription() {
        // Prescription target_rir=2; override target_rir=4 → an observed
        // RIR of 4 on the prescribed reps would NOT overshoot (4 vs 4)
        // whereas under the original target it WOULD (4 vs 2 + default 2
        // threshold = 4, triggering overshoot). We choose numbers that
        // discriminate.
        // Original: target=2, overshootAt default=2 → overshoot fires at RIR>=4.
        // Override: target=4, overshootAt default=2 → overshoot fires at RIR>=6.
        // So logging RIR=4 under override → no proposal.
        let fixture = makeContext(
            targetRir: 2,
            overridesJSON: #"{"target_rir":4}"#
        )
        let vm = ExecutionViewModel(context: fixture.context)
        vm.start()

        vm.swap(itemID: fixture.itemID, alternativeID: fixture.altID)

        // Log set 1 at RIR 4 — shouldn't trigger overshoot under the
        // override because the override bumped target_rir to 4.
        vm.logSet(reps: 5, rir: 4)
        XCTAssertNil(
            vm.currentProposal,
            "target_rir override should shadow prescription; RIR 4 no longer overshoots target 4"
        )
    }

    func testSwapWithoutTargetRirOverrideRetainsPrescriptionBehavior() {
        // Sanity guard on the shadow-path: without the override, the
        // same RIR=4 SHOULD fire overshoot under target_rir=2.
        let fixture = makeContext(targetRir: 2)
        let vm = ExecutionViewModel(context: fixture.context)
        vm.start()
        vm.swap(itemID: fixture.itemID, alternativeID: fixture.altID)
        vm.logSet(reps: 5, rir: 4)
        XCTAssertNotNil(vm.currentProposal)
        XCTAssertEqual(vm.currentProposal?.direction, .up)
    }

    // MARK: - Telemetry

    func testSwapEmitsTelemetry() {
        let fixture = makeContext(overridesJSON: #"{"load_kg":72.5}"#)
        let recorder = SwapTelemetryRecorder()
        let vm = ExecutionViewModel(context: fixture.context, telemetry: recorder)
        vm.start()

        vm.swap(itemID: fixture.itemID, alternativeID: fixture.altID)

        let swapEvents = recorder.events.filter { $0.name == "execution.exercise_swap" }
        XCTAssertEqual(swapEvents.count, 1)
        let event = try? XCTUnwrap(swapEvents.first)
        XCTAssertEqual(event?.workoutID, fixture.context.workout.id)
        let data = event?.dataJSON ?? ""
        XCTAssertTrue(data.contains(fixture.originalExerciseID.uuidString), "from id in payload")
        XCTAssertTrue(data.contains(fixture.altExerciseID.uuidString), "to id in payload")
        XCTAssertTrue(data.contains("\"had_overrides\":true"))
    }

    func testSwapWithoutOverridesReportsHadOverridesFalse() {
        let fixture = makeContext()
        let recorder = SwapTelemetryRecorder()
        let vm = ExecutionViewModel(context: fixture.context, telemetry: recorder)
        vm.start()
        vm.swap(itemID: fixture.itemID, alternativeID: fixture.altID)
        let swapEvent = recorder.events.first(where: { $0.name == "execution.exercise_swap" })
        XCTAssertEqual(swapEvent?.dataJSON?.contains("\"had_overrides\":false"), true)
    }

    // MARK: - Integration

    func testSwapIntegrationLogSetOneSwapThenSetTwoShowsOverrideLoad() {
        let fixture = makeContext(
            sets: 3,
            reps: 5,
            loadKg: 100,
            overridesJSON: #"{"load_kg":80}"#
        )
        let vm = ExecutionViewModel(context: fixture.context)
        vm.start()

        vm.logSet(reps: 5, rir: 2)
        // Pre-swap: set 2 still at 100 kg in the driver's active content
        // (we're on rest now; advance to see set 2 active view).
        vm.advance()
        XCTAssertEqual(vm.activeContent?.loadKg, 100, "pre-swap set 2 load")

        vm.swap(itemID: fixture.itemID, alternativeID: fixture.altID)
        XCTAssertEqual(vm.activeContent?.loadKg, 80, "post-swap set 2 picks up override")
    }

    // MARK: - Unknown alternative

    func testSwapWithUnknownAlternativeIsNoOp() {
        let fixture = makeContext()
        let vm = ExecutionViewModel(context: fixture.context)
        vm.start()
        let before = vm.state
        vm.swap(itemID: fixture.itemID, alternativeID: UUID())
        XCTAssertEqual(vm.state, before, "unknown alternative → silent no-op")
    }
}

// MARK: - Helpers

private struct SwapFixture {
    let context: WorkoutContext
    let itemID: UUID
    let originalExerciseID: UUID
    let altExerciseID: UUID
    let altID: UUID
}

@MainActor
extension ExecutionViewModelSwapTests {
    /// Build a single-block, single-item straight-sets context with one
    /// authored alternative. `overridesJSON` is the raw
    /// `parameter_overrides_json` string attached to the alternative —
    /// pass `nil` for a pure-swap fixture.
    fileprivate func makeContext(
        sets: Int = 4,
        reps: Int = 5,
        loadKg: Double = 100,
        targetRir: Int = 2,
        overridesJSON: String? = nil
    ) -> SwapFixture {
        SwapFixtureBuilder.build(
            sets: sets,
            reps: reps,
            loadKg: loadKg,
            targetRir: targetRir,
            overridesJSON: overridesJSON
        )
    }
}

private enum SwapFixtureBuilder {
    struct IDs {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let altExerciseID = UUID()
        let itemID = UUID()
        let altID = UUID()
    }

    static func build(
        sets: Int,
        reps: Int,
        loadKg: Double,
        targetRir: Int,
        overridesJSON: String?
    ) -> SwapFixture {
        let ids = IDs()
        let prescription = #"{"sets":\#(sets),"reps":\#(reps),"load_kg":\#(loadKg),"target_rir":\#(targetRir),"autoreg":{}}"#
        let ctx = context(ids: ids, prescription: prescription, overridesJSON: overridesJSON)
        return SwapFixture(
            context: ctx,
            itemID: ids.itemID,
            originalExerciseID: ids.exerciseID,
            altExerciseID: ids.altExerciseID,
            altID: ids.altID
        )
    }

    private static func context(
        ids: IDs,
        prescription: String,
        overridesJSON: String?
    ) -> WorkoutContext {
        let now = Date()
        let workout = Workout(
            id: ids.workoutID, userID: ids.userID, name: "Swap Test",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: ids.blockID, workoutID: ids.workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":60,"rest_between_exercises_sec":60}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: ids.itemID, blockID: ids.blockID, position: 0,
            exerciseID: ids.exerciseID, prescriptionJSON: prescription
        )
        let alternative = ExerciseAlternative(
            id: ids.altID, workoutItemID: ids.itemID, exerciseID: ids.altExerciseID,
            reason: "dumbbell variant", parameterOverridesJSON: overridesJSON
        )
        return WorkoutContext(
            workout: workout, blocks: [block], itemsByBlock: [[item]],
            exercises: [
                ids.exerciseID: Exercise(id: ids.exerciseID, name: "Bench Press"),
                ids.altExerciseID: Exercise(id: ids.altExerciseID, name: "Dumbbell Bench"),
            ],
            alternativesByItem: [ids.itemID: [alternative]]
        )
    }
}

/// Minimal in-memory telemetry emitter for the swap tests. Captures every
/// emitted Event so assertions can inspect count + payload.
private final class SwapTelemetryRecorder: TelemetryEmitter, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Event] = []
    var events: [Event] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
    func emit(_ event: Event) {
        lock.lock(); defer { lock.unlock() }
        storage.append(event)
    }
}
