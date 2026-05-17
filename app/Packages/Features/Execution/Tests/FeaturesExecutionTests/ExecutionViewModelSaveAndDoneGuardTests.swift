// ExecutionViewModelSaveAndDoneGuardTests.swift
//
// Regression test for the re-entrancy guard on `saveAndDone`.
//
// Bug: a fast double-tap on the Complete screen's "save & done" button,
// or a SwiftUI re-render that fired the tap action twice before the
// reducer's `.save` collapsed the screen, invoked `saveAndDone` more
// than once. Each invocation enqueued a terminal completion record AND
// a bodyweight `UserParameter`. Since `user_parameters` is append-only
// on the server, the duplicate bodyweight would live forever.
//
// The guard in `ExecutionViewModel+SaveAndDone.swift` drops the second
// (and any further) call until the first fully commits. These tests
// lock that behavior by counting hook invocations.

import XCTest
import CoreDomain
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class ExecutionViewModelSaveAndDoneGuardTests: XCTestCase {

    func testSaveAndDoneRejectsReentrantCall() async throws {
        // Fire `saveAndDone` twice back-to-back. The second call must
        // be dropped by the re-entrancy guard so only ONE completion record
        // and ONE user_parameter row land in the enqueuer recorders.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_042))
        let (ctx, _) = GuardTestFixtures.context(sets: 1, reps: 5, loadKg: 100)
        let recorder = EnqueueGuardRecorder()
        let hooks = ExecutionPushHooks(
            onWorkoutCompleted: { [recorder] record in
                await recorder.appendCompletion(record)
            },
            onUserParameterChanged: { [recorder] param in
                await recorder.appendUserParameter(param)
            }
        )
        let vm = ExecutionViewModel(context: ctx, clock: fixed, push: hooks)
        vm.start()
        vm.startCurrentSet()
        vm.complete()

        XCTAssertFalse(vm.saveAndDoneInFlight, "guard starts clear")

        // Simulate the double-tap: two calls back-to-back on the same
        // run-loop turn, before any awaits have landed the first call's
        // side effects.
        vm.saveAndDone(bodyweightKg: 82.5)
        vm.saveAndDone(bodyweightKg: 82.5)

        try await Task.sleep(nanoseconds: 50_000_000)

        let completions = await recorder.completions
        XCTAssertEqual(
            completions.count, 1,
            "re-entrant saveAndDone must be dropped: expected 1 completion, got \(completions.count)"
        )

        let params = await recorder.userParameters
        XCTAssertEqual(
            params.count, 1,
            "re-entrant saveAndDone must be dropped: expected 1 user_parameter, got \(params.count)"
        )

        vm.releaseSaveAndDoneGuardForTests()
    }

    func testSaveAndDoneFlagIsSetDuringCall() async throws {
        // After the first `saveAndDone`, the flag stays set — by the
        // time the call returns, the reducer's `.save` has flipped the
        // route to `.today` and the Complete screen is unmounted, so
        // the view model is effectively single-use for this session.
        // The flag being set is what the view binds to `.disabled(...)`.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_042))
        let (ctx, _) = GuardTestFixtures.context(sets: 1, reps: 5, loadKg: 100)
        let vm = ExecutionViewModel(context: ctx, clock: fixed, push: .none)
        vm.start()
        vm.startCurrentSet()
        vm.complete()

        XCTAssertFalse(vm.saveAndDoneInFlight)
        vm.saveAndDone()
        XCTAssertTrue(
            vm.saveAndDoneInFlight,
            "flag should remain set after saveAndDone so a late double-tap still sees the guard"
        )

        vm.releaseSaveAndDoneGuardForTests()
    }

    func testDeterministicUserParameterIDIsStableForSameInputs() async throws {
        // The deterministic id is what makes the server-side upsert safe.
        // Two calls with the same (userID, key, timestamp) must produce
        // the same UUID; two calls that differ on any field must not.
        let userA = UUID()
        let userB = UUID()
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_000_001)

        let a1 = ExecutionViewModel.userParameterID(
            userID: userA, key: "bodyweight_kg", observedAt: t1
        )
        let a1Again = ExecutionViewModel.userParameterID(
            userID: userA, key: "bodyweight_kg", observedAt: t1
        )
        XCTAssertEqual(a1, a1Again, "same inputs → same id")

        let a2 = ExecutionViewModel.userParameterID(
            userID: userA, key: "bodyweight_kg", observedAt: t2
        )
        XCTAssertNotEqual(a1, a2, "different timestamp → different id")

        let b1 = ExecutionViewModel.userParameterID(
            userID: userB, key: "bodyweight_kg", observedAt: t1
        )
        XCTAssertNotEqual(a1, b1, "different user → different id")

        let aOther = ExecutionViewModel.userParameterID(
            userID: userA, key: "1rm_back_squat_kg", observedAt: t1
        )
        XCTAssertNotEqual(a1, aOther, "different key → different id")
    }
}

private enum GuardTestFixtures {

    /// Builds a single-block, single-item straight-sets workout context.
    /// Duplicated from `ExecutionViewModelPushTests` so the guard tests
    /// stay independent of that file's internal helpers.
    static func context(
        sets: Int,
        reps: Int,
        loadKg: Double
    ) -> (WorkoutContext, UUID) {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()

        let workout = Workout(
            id: workoutID, userID: userID, name: "Guard Test",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":60,"rest_between_exercises_sec":60}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: #"{"sets":\#(sets),"reps":\#(reps),"load_kg":\#(loadKg)}"#
        )
        let ctx = WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Bench")]
        )
        return (ctx, itemID)
    }
}

/// Tiny recorder. Parallel actor to the one in `ExecutionViewModelPushTests`
/// but renamed so it can sit in its own file.
actor EnqueueGuardRecorder {
    private(set) var completions: [WorkoutCompletionRecord] = []
    private(set) var userParameters: [UserParameter] = []

    func appendCompletion(_ record: WorkoutCompletionRecord) {
        completions.append(record)
    }

    func appendUserParameter(_ param: UserParameter) {
        userParameters.append(param)
    }
}
