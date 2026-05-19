// ExecutionViewModelTests.swift
//
// XCTest coverage for the Execution feature's core behaviors:
//   - StraightSetsDriver: log → correct SessionMutations
//   - ExecutionViewModel: log → rest transition, autoreg proposal path
//   - Autoreg accept vs undo + held flag
//   - Route transitions across sets / items / blocks / complete
//   - SessionStateCodable round-trip (persistence)
//   - FixedClock + restEndsAt math
//
// No SwiftUI rendering — previews cover visual checks, xcodebuild
// covers compile.

import XCTest
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import Persistence
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class ExecutionViewModelTests: XCTestCase {

    // MARK: - Fixtures

    private func makeContext(
        sets: Int = 4,
        reps: Int = 5,
        loadKg: Double = 100,
        targetRir: Int = 2,
        restSec: Int = 180,
        includePrimitivePlan: Bool = false
    ) -> (WorkoutContext, UUID) {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()

        let workout = Workout(
            id: workoutID, userID: userID, name: "Test",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":\#(restSec),"rest_between_exercises_sec":\#(restSec)}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: #"{"sets":\#(sets),"reps":\#(reps),"load_kg":\#(loadKg),"target_rir":\#(targetRir),"autoreg":{}}"#
        )
        var primitiveWorkout: PrimitiveWorkout?
        var primitivePlan: ExecutionPlan?
        if includePrimitivePlan {
            let primitive = PrimitiveWorkout(
                id: workoutID,
                name: workout.name,
                blocks: [
                    PrimitiveBlock(id: blockID, sets: [
                        PrimitiveSet(
                            id: UUID(),
                            timing: PrimitiveTiming(mode: .setBounded),
                            traversal: .sequential,
                            repeatCount: sets,
                            slots: [
                                PrimitiveSlot(
                                    id: itemID,
                                    exerciseID: exerciseID,
                                    workTargets: [
                                        PrimitiveWorkTarget(
                                            metric: .reps,
                                            valueForm: .single,
                                            value: Double(reps),
                                            role: .completion
                                        ),
                                    ],
                                    load: PrimitiveLoad(
                                        value: loadKg,
                                        unit: .lb,
                                        unitType: .absolute
                                    )
                                ),
                            ]
                        ),
                    ]),
                ]
            )
            primitiveWorkout = primitive
            primitivePlan = try! ExecutionPlan.validated(workout: primitive)
        }

        let ctx = WorkoutContext(
            workout: workout,
            primitiveWorkout: primitiveWorkout,
            primitiveExecutionPlan: primitivePlan,
            blocks: [block],
            itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Bench")],
            lastPerformed: [:]
        )
        return (ctx, itemID)
    }

    private func make2BlockContext(restSec: Int = 60) -> (WorkoutContext, UUID, UUID) {
        let userID = UUID()
        let workoutID = UUID()
        let now = Date()
        let b1 = UUID()
        let b2 = UUID()
        let e1 = UUID()
        let e2 = UUID()
        let item1 = UUID()
        let item2 = UUID()

        let workout = Workout(
            id: workoutID, userID: userID, name: "2B",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        func block(_ id: UUID, pos: Int) -> Block {
            Block(id: id, workoutID: workoutID, parentBlockID: nil,
                  position: pos, name: nil, timingMode: .straightSets,
                  timingConfigJSON: #"{"rest_between_sets_sec":\#(restSec),"rest_between_exercises_sec":\#(restSec)}"#,
                  rounds: nil, roundsRepSchemeJSON: nil, notes: nil)
        }

        let ctx = WorkoutContext(
            workout: workout,
            blocks: [block(b1, pos: 0), block(b2, pos: 1)],
            itemsByBlock: [
                [WorkoutItem(id: item1, blockID: b1, position: 0,
                             exerciseID: e1,
                             prescriptionJSON: #"{"sets":2,"reps":5,"load_kg":100}"#)],
                [WorkoutItem(id: item2, blockID: b2, position: 0,
                             exerciseID: e2,
                             prescriptionJSON: #"{"sets":2,"reps":8,"load_kg":60}"#)]
            ],
            exercises: [
                e1: Exercise(id: e1, name: "A"),
                e2: Exercise(id: e2, name: "B"),
            ],
            lastPerformed: [:]
        )
        return (ctx, item1, item2)
    }

    // MARK: - Driver tests

    func testStraightSetsDriverProducesProposalOnOvershoot() {
        let (ctx, itemID) = makeContext(targetRir: 2)
        let vm = ExecutionViewModel(context: ctx)
        vm.start()
        vm.startCurrentSet()

        // Log set 1 with RIR 4 → overshoot by +2 → proposal.
        vm.logSet(reps: 5, rir: 4)
        XCTAssertNotNil(vm.currentProposal)
        XCTAssertEqual(vm.currentProposal?.direction, .up)
        XCTAssertEqual(vm.currentProposalItemID, itemID)
    }

    func testStraightSetsDriverProducesDownProposalOnUndershoot() {
        let (ctx, _) = makeContext(reps: 8, targetRir: 2)
        let vm = ExecutionViewModel(context: ctx)
        vm.start()
        vm.startCurrentSet()

        // Logged 6 vs prescribed 8 → missed 2 → undershoot.
        vm.logSet(reps: 6, rir: 1)
        XCTAssertEqual(vm.currentProposal?.direction, .down)
    }

    func testNoProposalOnLastSet() {
        let (ctx, _) = makeContext(sets: 1)
        let vm = ExecutionViewModel(context: ctx)
        vm.start()

        vm.startCurrentSet()

        vm.logSet(reps: 5, rir: 4)
        XCTAssertNil(vm.currentProposal)
    }

    // MARK: - Autoreg + held

    func testUndoAutoregSetsHeldAndClearsProposal() {
        let (ctx, itemID) = makeContext(targetRir: 2)
        let vm = ExecutionViewModel(context: ctx)
        vm.start()

        vm.startCurrentSet()

        vm.logSet(reps: 5, rir: 4)
        XCTAssertNotNil(vm.currentProposal)

        vm.undoAutoreg()
        XCTAssertNil(vm.currentProposal)

        let itemLog = vm.state.items.first(where: { $0.itemID == itemID })
        XCTAssertEqual(itemLog?.autoregHeld, true)

        // Advance to set 2, log again → no new proposal because held.
        vm.advance()
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 4)
        XCTAssertNil(vm.currentProposal)
    }

    func testAcceptAutoregLeavesAppliedLoadAndClearsProposal() {
        let (ctx, itemID) = makeContext(targetRir: 2, restSec: 60)
        let vm = ExecutionViewModel(context: ctx)
        vm.start()

        vm.startCurrentSet()

        vm.logSet(reps: 5, rir: 4)
        let proposalLoad = vm.currentProposal?.newLoadKg
        XCTAssertNotNil(proposalLoad)

        vm.acceptAutoreg()
        XCTAssertNil(vm.currentProposal)

        // Remaining (non-done) sets should reflect the proposal load.
        let itemLog = vm.state.items.first(where: { $0.itemID == itemID })
        let remaining = itemLog?.sets.filter { !$0.done } ?? []
        XCTAssertFalse(remaining.isEmpty)
        XCTAssertTrue(remaining.allSatisfy { $0.loadKg == proposalLoad })
    }

    // MARK: - Route transitions

    func testFullLoopAcrossBlocksReachesComplete() {
        let (ctx, _, _) = make2BlockContext(restSec: 60)
        let vm = ExecutionViewModel(context: ctx)

        // Start — Today → Active
        vm.start()
        XCTAssertEqual(vm.state.route, .active)

        // Block 0 item 0: 2 sets
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 1)
        XCTAssertEqual(vm.state.route, .rest)
        vm.advance()
        vm.startCurrentSet()
        XCTAssertEqual(vm.state.route, .active)

        vm.logSet(reps: 5, rir: 1)
        XCTAssertEqual(vm.state.route, .rest)
        vm.advance()

        // Should transition before block 1 item 0 set 1 now.
        XCTAssertEqual(vm.state.route, .transition)
        vm.beginBlockTransition()
        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(vm.state.cursor.blockIndex, 1)
        XCTAssertEqual(vm.state.cursor.itemIndex, 0)
        XCTAssertEqual(vm.state.cursor.setIndex, 1)

        // Finish block 1.
        vm.logSet(reps: 8, rir: 1)
        vm.advance()
        vm.startCurrentSet()
        vm.logSet(reps: 8, rir: 1)
        vm.advance()

        vm.startCurrentSet()

        XCTAssertEqual(vm.state.route, .complete)
    }

    // MARK: - Rest-block (standalone rest between work blocks)

    /// Build a 3-block context: work (straight_sets, 1 item, 2 sets) →
    /// rest (`duration_sec: 5`, zero items) → work (straight_sets, 1 item,
    /// 2 sets). Mirrors the real-world AMRAP → rest → EMOM shape. Returns
    /// `(context, itemA, itemC)`.
    private func makeWorkRestWorkContext(
        restSec: Int = 60,
        restBlockDurationSec: Int = 5
    ) -> (WorkoutContext, UUID, UUID) {
        let userID = UUID()
        let workoutID = UUID()
        let now = Date()
        let bWorkA = UUID()
        let bRest = UUID()
        let bWorkC = UUID()
        let exA = UUID()
        let exC = UUID()
        let itemA = UUID()
        let itemC = UUID()

        let workout = Workout(
            id: workoutID, userID: userID, name: "WRW",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let workConfig = #"{"rest_between_sets_sec":\#(restSec),"rest_between_exercises_sec":\#(restSec)}"#
        let restConfig = #"{"duration_sec":\#(restBlockDurationSec)}"#

        let workBlockA = Block(
            id: bWorkA, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: workConfig,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let restBlock = Block(
            id: bRest, workoutID: workoutID, parentBlockID: nil,
            position: 1, name: nil, timingMode: .rest,
            timingConfigJSON: restConfig,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let workBlockC = Block(
            id: bWorkC, workoutID: workoutID, parentBlockID: nil,
            position: 2, name: nil, timingMode: .straightSets,
            timingConfigJSON: workConfig,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )

        let ctx = WorkoutContext(
            workout: workout,
            blocks: [workBlockA, restBlock, workBlockC],
            itemsByBlock: [
                [WorkoutItem(id: itemA, blockID: bWorkA, position: 0,
                             exerciseID: exA,
                             prescriptionJSON: #"{"sets":2,"reps":5,"load_kg":100}"#)],
                [],   // the rest block — no items
                [WorkoutItem(id: itemC, blockID: bWorkC, position: 0,
                             exerciseID: exC,
                             prescriptionJSON: #"{"sets":2,"reps":8,"load_kg":60}"#)],
            ],
            exercises: [
                exA: Exercise(id: exA, name: "A"),
                exC: Exercise(id: exC, name: "C"),
            ],
            lastPerformed: [:]
        )
        return (ctx, itemA, itemC)
    }

    func testRestBlockEnterAndAdvance() {
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 2_000_000))
        let (ctx, _, _) = makeWorkRestWorkContext(restSec: 60, restBlockDurationSec: 5)
        let vm = ExecutionViewModel(context: ctx, clock: fixed)

        // Seeder produces zero-item row for the rest block.
        XCTAssertEqual(vm.state.structure.itemsPerBlock, [1, 0, 1])

        // Start block 0.
        vm.start()
        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(vm.state.cursor.blockIndex, 0)

        // Log both sets of block 0.
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 2)
        XCTAssertEqual(vm.state.route, .rest)
        vm.advance()
        vm.startCurrentSet()
        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(vm.state.cursor.setIndex, 2)

        vm.logSet(reps: 5, rir: 2)
        XCTAssertEqual(vm.state.route, .rest)
        // Last set of block 0 → rest is the between-sets rest; advancing
        // again should land us in the rest BLOCK (block 1).
        vm.advance()

        // Should have entered block 1's rest directly.
        XCTAssertEqual(vm.state.route, .rest)
        XCTAssertEqual(vm.state.cursor.blockIndex, 1)
        XCTAssertEqual(vm.state.cursor.itemIndex, 0)
        XCTAssertEqual(vm.state.cursor.setIndex, 1)

        // restEndsAt should reflect the rest-block driver's duration
        // (5 seconds) against the fixed clock.
        XCTAssertEqual(
            vm.state.restEndsAt?.timeIntervalSince1970,
            fixed.now.timeIntervalSince1970 + 5
        )

        // Advance from the rest block → should land on block 2 set 1
        // active screen (NOT on another rest).
        vm.advance()
        vm.startCurrentSet()
        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(vm.state.cursor.blockIndex, 2)
        XCTAssertEqual(vm.state.cursor.itemIndex, 0)
        XCTAssertEqual(vm.state.cursor.setIndex, 1)
    }

    func testRestBlockAtStartPositionEntersRestOnStart() {
        // Unusual but valid: a rest block authored at position 0. `start()`
        // should go Today → rest directly, not Today → active.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 3_000_000))
        let userID = UUID()
        let workoutID = UUID()
        let now = Date()
        let bRest = UUID()
        let bWork = UUID()
        let exW = UUID()
        let itemW = UUID()

        let workout = Workout(
            id: workoutID, userID: userID, name: "R→W",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let restBlock = Block(
            id: bRest, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .rest,
            timingConfigJSON: #"{"duration_sec":10}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let workBlock = Block(
            id: bWork, workoutID: workoutID, parentBlockID: nil,
            position: 1, name: nil, timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":60,"rest_between_exercises_sec":60}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let ctx = WorkoutContext(
            workout: workout,
            blocks: [restBlock, workBlock],
            itemsByBlock: [
                [],
                [WorkoutItem(id: itemW, blockID: bWork, position: 0,
                             exerciseID: exW,
                             prescriptionJSON: #"{"sets":1,"reps":5,"load_kg":50}"#)],
            ],
            exercises: [exW: Exercise(id: exW, name: "W")]
        )
        let vm = ExecutionViewModel(context: ctx, clock: fixed)
        vm.start()

        XCTAssertEqual(vm.state.route, .rest)
        XCTAssertEqual(vm.state.cursor.blockIndex, 0)
        XCTAssertEqual(
            vm.state.restEndsAt?.timeIntervalSince1970,
            fixed.now.timeIntervalSince1970 + 10
        )

        vm.advance()
        vm.startCurrentSet()
        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(vm.state.cursor.blockIndex, 1)
    }

    /// Bug-034 regression: a workout whose block[0] is a zero-item rest
    /// block must NOT leave the user on the Active screen. `start()` must
    /// enter `.rest` directly, populate `restEndsAt`, and not route
    /// through `.active`. Companion to
    /// `testRestBlockAtStartPositionEntersRestOnStart`; this test pins
    /// the invariants the bug report named (route != .active,
    /// restEndsAt populated, block[1] is straight_sets — the common
    /// "warmup pause then press" authoring shape).
    func testStartOnZeroItemFirstBlockEntersRest() {
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 4_000_000))
        let userID = UUID()
        let workoutID = UUID()
        let now = Date()
        let bRest = UUID()
        let bWork = UUID()
        let exW = UUID()
        let itemW = UUID()

        let workout = Workout(
            id: workoutID, userID: userID, name: "Rest-first",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let restBlock = Block(
            id: bRest, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .rest,
            timingConfigJSON: #"{"duration_sec":45}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let workBlock = Block(
            id: bWork, workoutID: workoutID, parentBlockID: nil,
            position: 1, name: nil, timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":60,"rest_between_exercises_sec":60}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let ctx = WorkoutContext(
            workout: workout,
            blocks: [restBlock, workBlock],
            itemsByBlock: [
                [],
                [WorkoutItem(id: itemW, blockID: bWork, position: 0,
                             exerciseID: exW,
                             prescriptionJSON: #"{"sets":3,"reps":5,"load_kg":100}"#)],
            ],
            exercises: [exW: Exercise(id: exW, name: "Bench")]
        )

        // Seeder expresses the shape: block 0 has zero items, block 1
        // has one. Without this precondition the bug couldn't reproduce.
        let vm = ExecutionViewModel(context: ctx, clock: fixed)
        XCTAssertEqual(vm.state.structure.itemsPerBlock, [0, 1])

        vm.start()

        // Route goes straight to .rest — not .active. The pre-fix
        // behavior was `.active` with no items, producing a dead render.
        XCTAssertEqual(vm.state.route, .rest)
        XCTAssertNotEqual(vm.state.route, .active)
        // Cursor lands on the zero-item sentinel (0, 0, 1).
        XCTAssertEqual(vm.state.cursor.blockIndex, 0)
        XCTAssertEqual(vm.state.cursor.itemIndex, 0)
        XCTAssertEqual(vm.state.cursor.setIndex, 1)
        // restEndsAt reflects the block's `duration_sec`.
        XCTAssertEqual(
            vm.state.restEndsAt?.timeIntervalSince1970,
            fixed.now.timeIntervalSince1970 + 45
        )
    }

    // MARK: - Persistence round-trip

    func testSessionStateCodableRoundTrip() throws {
        let (ctx, _) = makeContext(sets: 2)
        let vm = ExecutionViewModel(context: ctx)
        vm.start()
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 2)
        // Mid-rest state — ensure restEndsAt and route survive.

        let encoded = try JSONEncoder().encode(SessionStateCodable(state: vm.state))
        let decoded = try JSONDecoder().decode(SessionStateCodable.self, from: encoded)

        XCTAssertEqual(decoded.state.route, vm.state.route)
        XCTAssertEqual(decoded.state.cursor.setIndex, vm.state.cursor.setIndex)
        XCTAssertEqual(decoded.state.items.count, vm.state.items.count)
        XCTAssertEqual(decoded.state.structure.itemsPerBlock, vm.state.structure.itemsPerBlock)
        XCTAssertNotNil(decoded.state.restEndsAt)
    }

    func testRestoreIfPossiblePullsSavedState() async throws {
        let store = InMemorySessionStore()
        let (ctx, _) = makeContext()
        let vm1 = ExecutionViewModel(context: ctx, sessionStore: store)
        vm1.start()
        vm1.startCurrentSet()
        vm1.logSet(reps: 5, rir: 2)

        // Wait for fire-and-forget save to land.
        try await Task.sleep(nanoseconds: 100_000_000)

        let vm2 = ExecutionViewModel(context: ctx, sessionStore: store)
        await vm2.restoreIfPossible()

        XCTAssertEqual(vm2.state.route, .rest)
        // One set logged.
        let doneCount = vm2.state.items.first?.sets.filter(\.done).count ?? 0
        XCTAssertEqual(doneCount, 1)
    }

    // MARK: - Local completion writer (History-tab backfill)

    func testSaveAndDoneInvokesLocalCompletionWriterOnce() async throws {
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_000))
        let (ctx, itemID) = makeContext(sets: 2, restSec: 60, includePrimitivePlan: true)
        let recorder = CompletionRecorder()
        let vm = ExecutionViewModel(
            context: ctx,
            clock: fixed,
            localCompletionWriter: { [recorder] record in
                await recorder.record(record)
            }
        )
        vm.start()
        // Log both sets so the writer sees primitive result rows in the expected shape.
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 2)
        vm.advance()
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 1)
        vm.advance()
        vm.startCurrentSet()
        XCTAssertEqual(vm.state.route, .complete)

        vm.saveAndDone()
        // Fire-and-forget: give the detached Task a moment to land.
        try await Task.sleep(nanoseconds: 50_000_000)

        let calls = await recorder.calls
        XCTAssertEqual(calls.count, 1)
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(call.workout.id, ctx.workout.id)
        XCTAssertEqual(call.workout.status, .completed)
        XCTAssertEqual(call.workout.completedAt, fixed.now)
        XCTAssertEqual(call.workout.updatedAt, fixed.now)
        let logs = call.record.primitiveSetLogs
        XCTAssertEqual(logs.count, 2)
        XCTAssertTrue(logs.allSatisfy { $0.slotID == itemID })
        XCTAssertEqual(Set(logs.map(\.setRepeatIndex)), [0, 1])
        XCTAssertTrue(logs.allSatisfy { $0.reps == 5 })
        // With `FixedClock`, `clock.now` never advances between log
        // events, so every set's `completedAt` matches the fixed stamp
        // (same clock value at every `.logSet`). The "sets can carry
        // distinct stamps" coverage lives in
        // `testCompletionWriteStampsPerSetTimestamps`, which drives a
        // mutable clock across logSet calls.
        XCTAssertTrue(logs.allSatisfy { $0.completedAt == fixed.now })
    }

    func testSaveAndDonePrimitiveCompletionUsesStablePrimitiveLogIDs() async throws {
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_050))
        let (ctx, _) = makeContext(sets: 2, restSec: 60, includePrimitivePlan: true)
        let recorder = CompletionRecorder()
        let vm = ExecutionViewModel(
            context: ctx,
            clock: fixed,
            localCompletionWriter: { [recorder] record in
                await recorder.record(record)
            }
        )
        vm.start()
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 2)
        vm.advance()
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 1)
        vm.advance()

        vm.startCurrentSet()

        vm.saveAndDone()
        try await Task.sleep(nanoseconds: 50_000_000)

        let calls = await recorder.calls
        let call = try XCTUnwrap(calls.first)
        let logs = call.record.primitiveSetLogs.sorted(by: { $0.setRepeatIndex < $1.setRepeatIndex })
        XCTAssertEqual(logs.count, 2)
        XCTAssertNotEqual(logs[0].id, logs[1].id)
        XCTAssertEqual(logs.map(\.id), vm.primitiveSetLogs.sorted(by: { $0.setRepeatIndex < $1.setRepeatIndex }).map(\.id))
    }

    func testSaveAndDonePrimitiveCompletionOmitsSkippedSlotRows() async throws {
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_075))
        let (ctx, _) = makeContext(sets: 1, restSec: 0, includePrimitivePlan: true)
        let recorder = CompletionRecorder()
        let vm = ExecutionViewModel(
            context: ctx,
            clock: fixed,
            localCompletionWriter: { [recorder] record in
                await recorder.record(record)
            }
        )
        vm.start()
        vm.startCurrentSet()
        vm.skipCurrentSet()
        XCTAssertEqual(vm.state.route, .complete)

        vm.saveAndDone()
        try await Task.sleep(nanoseconds: 50_000_000)

        let calls = await recorder.calls
        let call = try XCTUnwrap(calls.first)
        XCTAssertTrue(call.record.primitiveSetLogs.isEmpty)
    }

    func testCompletionWriteStampsPerSetTimestamps() async throws {
        // Regression: prior to the reducer-side `completedAt` stamp,
        // `writeCompletionToLocalCache` stamped every SetLog with the
        // single `clock.now` captured at `saveAndDone` entry — so all
        // sets appeared to finish on the same instant and rest-time
        // analysis was impossible. Post-fix: each SetPlan carries its
        // own `completedAt` (stamped by the reducer's `.logSet` handler).
        //
        // `startedAt` semantics (R2.5 v2 — Codex review fix): the anchor
        // is "when the previous rest ended" (or session-start for set 1),
        // NOT "previous set's completedAt". Chaining via completedAt
        // would FOLD rest time INTO set duration — a 10s bench press
        // with a 90s rest would show as a 100s set. The reducer reads
        // `state.workStartedAt` at log time (stamped by the VM on
        // `.start` and every `.advanceFromRest`) and writes it onto the
        // SetPlan.
        //
        // Drive three sets across three distinct clock values (T, T+30s,
        // T+90s) with `.advance()` between them. Each advance() stamps
        // `workStartedAt = clock.now`, so set N's startedAt == the advance
        // time that preceded its log.
        let t0 = Date(timeIntervalSince1970: 1_700_000_300)
        let clock = MutableClock(now: t0)
        let (ctx, _) = makeContext(sets: 3, restSec: 60, includePrimitivePlan: true)
        let recorder = CompletionRecorder()
        let vm = ExecutionViewModel(
            context: ctx,
            clock: clock,
            localCompletionWriter: { [recorder] record in
                await recorder.record(record)
            }
        )
        // `start()` stamps workStartedAt = t0. Set 1 logs at t0 → its
        // startedAt == t0 (session-start anchor, zero-duration set).
        vm.start()
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 2)
        // advance() at T stamps workStartedAt = T. But next log moves
        // clock forward, so we'll bump the clock FIRST, then advance
        // at the desired rest-ended instant, then log.
        //
        // Timeline (post-fix):
        //   set 1: startedAt = T     (from start), completedAt = T
        //   advance at T+20s         → workStartedAt = T+20s
        //   set 2: startedAt = T+20s, completedAt = T+30s   (10s working)
        //   advance at T+80s         → workStartedAt = T+80s
        //   set 3: startedAt = T+80s, completedAt = T+90s   (10s working)
        clock.now = t0.addingTimeInterval(20)
        vm.advance()
        vm.startCurrentSet()
        clock.now = t0.addingTimeInterval(30)
        vm.logSet(reps: 5, rir: 2)
        clock.now = t0.addingTimeInterval(80)
        vm.advance()
        vm.startCurrentSet()
        clock.now = t0.addingTimeInterval(90)
        vm.logSet(reps: 5, rir: 1)
        vm.advance()
        vm.startCurrentSet()
        XCTAssertEqual(vm.state.route, .complete)

        // `saveAndDone` runs at T + 120s — the completion writer's own
        // workout `completedAt` picks this up, but per-set timestamps
        // must stay on the log moments, not this final instant.
        clock.now = t0.addingTimeInterval(120)
        vm.saveAndDone()
        try await Task.sleep(nanoseconds: 50_000_000)

        let calls = await recorder.calls
        XCTAssertEqual(calls.count, 1)
        let call = try XCTUnwrap(calls.first)
        let sorted = call.record.primitiveSetLogs.sorted(by: { $0.setRepeatIndex < $1.setRepeatIndex })
        XCTAssertEqual(sorted.count, 3)
        XCTAssertEqual(sorted[0].completedAt, t0)
        XCTAssertEqual(sorted[1].completedAt, t0.addingTimeInterval(30))
        XCTAssertEqual(sorted[2].completedAt, t0.addingTimeInterval(90))
        // Distinct per-set stamps — catches a regression where all sets
        // collapse onto `clock.now` at `saveAndDone`.
        let stamps = Set(sorted.map(\.completedAt))
        XCTAssertEqual(stamps.count, 3, "every set carries its own completedAt")
        // Workout-level completedAt reflects `saveAndDone` entry, not
        // any individual set's log moment.
        XCTAssertEqual(call.workout.completedAt, t0.addingTimeInterval(120))
    }

    func testSetLogStartedAtIsRestEndedAtNotPriorLoggedAt() async throws {
        // Codex R2.5 review fix: set N's startedAt must reflect "when
        // rest ended / work began", NOT "set N-1's completedAt".
        // Chaining via completedAt folds rest time into set duration.
        //
        // Scenario: log set 1 at T+10, advance (rest-ended) at T+100,
        // log set 2 at T+110. Set 2's startedAt must be T+100
        // (rest-ended), NOT T+10 (set 1 completedAt). Set 2's working
        // duration = 10s, not 100s.
        let t0 = Date(timeIntervalSince1970: 1_700_000_400)
        let clock = MutableClock(now: t0)
        let (ctx, _) = makeContext(sets: 2, restSec: 60)
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        // Set Start stamps workStartedAt = t0. Advance clock, then log
        // set 1 at t0+10. Set 1's startedAt = t0, completedAt = t0+10.
        vm.start()
        vm.startCurrentSet()
        clock.now = t0.addingTimeInterval(10)
        vm.logSet(reps: 5, rir: 2)
        // Rest ends at t0+100; advance stamps workStartedAt = t0+100.
        clock.now = t0.addingTimeInterval(100)
        vm.advance()
        vm.startCurrentSet()
        // Set 2 logs at t0+110. Set 2's startedAt should be t0+100
        // (NOT t0+10, set 1's completedAt).
        clock.now = t0.addingTimeInterval(110)
        vm.logSet(reps: 5, rir: 1)
        vm.advance()
        vm.startCurrentSet()
        XCTAssertEqual(vm.state.route, .complete)

        let sorted = try XCTUnwrap(vm.state.items.first?.sets.sorted(by: { $0.setIndex < $1.setIndex }))
        XCTAssertEqual(sorted.count, 2)

        // Set 2's startedAt is the rest-ended stamp, not the prior
        // completedAt. This is the whole point of the fix.
        XCTAssertEqual(
            sorted[1].startedAt, t0.addingTimeInterval(100),
            "set 2 startedAt must equal rest-ended time (t0+100), NOT set 1 completedAt (t0+10)"
        )
        XCTAssertNotEqual(
            sorted[1].startedAt, t0.addingTimeInterval(10),
            "set 2 startedAt must NOT equal set 1 completedAt — that folds rest into set duration"
        )
        // Working duration = completedAt - startedAt.
        let set2CompletedAt = try XCTUnwrap(sorted[1].completedAt)
        let set2Working = set2CompletedAt.timeIntervalSince(sorted[1].startedAt!)
        XCTAssertEqual(set2Working, 10, "set 2 working time = 10s, not 100s")
    }

    func testFirstSetHasSessionStartStartedAt() async throws {
        // Codex R2.5 review fix: the FIRST set of a workout uses the
        // session-start instant as its startedAt anchor — stamped by
        // `start()` via `state.workStartedAt = clock.now`. Prior
        // behavior left set 1 with `startedAt = nil` (derived from the
        // missing "previous set" in the chain).
        let t0 = Date(timeIntervalSince1970: 1_700_000_500)
        let clock = MutableClock(now: t0)
        let (ctx, _) = makeContext(sets: 1, restSec: 60)
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        // Set Start stamps workStartedAt = t0. User logs at t0+15.
        vm.start()
        vm.startCurrentSet()
        clock.now = t0.addingTimeInterval(15)
        vm.logSet(reps: 5, rir: 2)
        vm.advance()
        vm.startCurrentSet()
        XCTAssertEqual(vm.state.route, .complete)

        let set1 = try XCTUnwrap(vm.state.items.first?.sets.first)
        // First set's startedAt = session-start (NOT nil, NOT the log
        // moment). Work window = completedAt - startedAt = 15s.
        XCTAssertEqual(set1.startedAt, t0, "first set carries session-start as startedAt")
        XCTAssertEqual(set1.completedAt, t0.addingTimeInterval(15))
        XCTAssertEqual(
            try XCTUnwrap(set1.completedAt).timeIntervalSince(set1.startedAt!), 15,
            "first set's working time = 15s (log moment minus session start)"
        )
    }

    func testSaveAndDoneWritesNoteToCompletedWorkout() async throws {
        // Bug-012: workout-level note captured on the Complete screen
        // must land on `Workout.notes` in the local-cache write. The
        // note is trimmed and empty-collapsed; "felt strong" passes
        // through verbatim.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_100))
        let (ctx, _) = makeContext(sets: 1, restSec: 60)
        let recorder = CompletionRecorder()
        let vm = ExecutionViewModel(
            context: ctx,
            clock: fixed,
            localCompletionWriter: { [recorder] record in
                await recorder.record(record)
            }
        )
        vm.start()
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 2)
        vm.advance()
        vm.startCurrentSet()
        XCTAssertEqual(vm.state.route, .complete)

        vm.saveAndDone(note: "felt strong", bodyweightKg: nil)
        try await Task.sleep(nanoseconds: 50_000_000)

        let calls = await recorder.calls
        XCTAssertEqual(calls.count, 1)
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(call.workout.notes, "felt strong")
        XCTAssertEqual(call.workout.status, .completed)
    }

    func testSaveAndDoneEmptyNoteCollapsesToNil() async throws {
        // Empty / whitespace-only notes must NOT overwrite the template
        // `notes` on the Workout row. `nil` + "   " + "" all collapse
        // via `ExecutionViewModel.normalizeNote` — we assert the final
        // `notes` equals the base workout's notes (nil in the fixture).
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_101))
        let (ctx, _) = makeContext(sets: 1, restSec: 60)
        let recorder = CompletionRecorder()
        let vm = ExecutionViewModel(
            context: ctx,
            clock: fixed,
            localCompletionWriter: { [recorder] record in
                await recorder.record(record)
            }
        )
        vm.start()
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 2)

        vm.saveAndDone(note: "   ")
        try await Task.sleep(nanoseconds: 50_000_000)

        let calls = await recorder.calls
        let call = try XCTUnwrap(calls.first)
        XCTAssertNil(call.workout.notes)
    }

    func testSaveAndDoneEnqueuesBodyweightUserParameter() async throws {
        // Bug-011: when the user enters a body weight on the Complete
        // screen, `saveAndDone(bodyweightKg:)` fires the
        // `onUserParameterChanged` hook exactly once with a
        // `UserParameter` carrying `key == "bodyweight_kg"` and a
        // `value` that round-trips through `String(Double)` (so "82.5"
        // stays "82.5").
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_200))
        let (ctx, _) = makeContext(sets: 1, restSec: 60)
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onUserParameterChanged: { [recorder] param in
                await recorder.appendUserParameter(param)
            }
        )
        let vm = ExecutionViewModel(
            context: ctx,
            clock: fixed,
            push: hooks
        )
        vm.start()
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 2)

        vm.saveAndDone(bodyweightKg: 82.5)
        try await Task.sleep(nanoseconds: 50_000_000)

        let params = await recorder.userParameters
        XCTAssertEqual(params.count, 1)
        let param = try XCTUnwrap(params.first)
        XCTAssertEqual(param.key, "bodyweight_kg")
        XCTAssertEqual(param.value, "82.5")
        XCTAssertEqual(param.source, .appLog)
        XCTAssertEqual(param.updatedAt, fixed.now)
        XCTAssertEqual(param.userID, ctx.workout.userID)
    }

    func testSaveAndDoneNilBodyweightDoesNotFire() async throws {
        // Bug-011 regression: saveAndDone without a bodyweight must NOT
        // enqueue a user_parameter row. A bare call (no arguments) is
        // the existing call-site pattern — don't regress.
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_201))
        let (ctx, _) = makeContext(sets: 1, restSec: 60)
        let recorder = EnqueueRecorder()
        let hooks = ExecutionPushHooks(
            onUserParameterChanged: { [recorder] param in
                await recorder.appendUserParameter(param)
            }
        )
        let vm = ExecutionViewModel(
            context: ctx,
            clock: fixed,
            push: hooks
        )
        vm.start()
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 2)

        vm.saveAndDone()
        try await Task.sleep(nanoseconds: 50_000_000)

        let params = await recorder.userParameters
        XCTAssertEqual(params.count, 0, "nil bodyweight must not enqueue a user_parameter row")
    }

    func testSaveAndDoneNoOpWhenWriterIsNil() async throws {
        // Regression: the default path (no writer) must not crash and must
        // still clear the session state — matches the nil-enqueuer test on
        // the push side.
        let (ctx, _) = makeContext(sets: 1, restSec: 60)
        let vm = ExecutionViewModel(context: ctx)
        vm.start()
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 2)
        vm.saveAndDone()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(vm.state.route, .today)
    }

    // MARK: - qa-030: bodyweight field starts empty

    /// qa-030 root-cause regression: the Complete screen's bodyweight
    /// field must start truly empty. The QA report described users seeing
    /// "82.5" on the field before typing; investigation traced that to
    /// the `prompt: Text("82.5")` placeholder, which SwiftUI renders
    /// grayed-out but visually reads as a prefilled value. Users walked
    /// away without typing, `parsedBodyweightKg` returned nil, and the
    /// `enqueueBodyweight` push never fired.
    ///
    /// The fix (a) removed the numeric prompt and (b) pinned the initial
    /// value via `CompleteView.initialBodyweightText`. This test locks
    /// that static so a future edit can't silently reintroduce a prefill
    /// (e.g. seeding from `user_parameters.bodyweight_kg` latest).
    func testCompleteViewBodyweightFieldStartsEmpty() {
        XCTAssertEqual(
            CompleteView.initialBodyweightText, "",
            "bodyweight text must start empty — any prefill breaks the qa-030 contract"
        )
        XCTAssertEqual(
            CompleteView.initialNoteText, "",
            "note text must start empty; a future seed would need an explicit contract change"
        )
    }

    // MARK: - qa-028: End button

    /// qa-028: the nav-bar End button on Active/Rest calls
    /// `viewModel.complete()` and flips the route to `.complete` WITHOUT
    /// requiring the user to log every remaining set. This pins the
    /// contract for the End affordance — the view layer's alert confirms
    /// before firing, and this test covers the underlying VM entry point
    /// the confirm button calls.
    func testEndButtonCallsCompleteAndFlipsToCompleteRoute() {
        // 4 prescribed sets — only the first is logged. End mid-workout
        // should still land on `.complete` without forcing the remaining
        // three logs.
        let (ctx, itemID) = makeContext(sets: 4, restSec: 60)
        let vm = ExecutionViewModel(context: ctx)
        vm.start()
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 2)
        // Advance out of rest into set 2's active screen so the "End from
        // any screen" contract is exercised — the docs call out End on
        // both Active and Rest.
        vm.advance()
        vm.startCurrentSet()
        XCTAssertEqual(
            vm.state.route, .active,
            "precondition: cursor should be on set 2's Active screen"
        )

        vm.complete()

        XCTAssertEqual(
            vm.state.route, .complete,
            "complete() must flip the route to .complete"
        )
        // The one logged set is preserved — End is destructive of
        // unlogged sets, not of the log so far.
        let itemLog = vm.state.items.first(where: { $0.itemID == itemID })
        let doneCount = itemLog?.sets.filter(\.done).count ?? 0
        XCTAssertEqual(doneCount, 1, "existing logged sets must survive End")
    }

    // MARK: - Time-capped + round-based integration

    /// Shared builder for a single-block workout in a given timing mode
    /// with an arbitrary timing_config and item list.
    private func makeSingleBlockContext(
        timingMode: TimingMode,
        timingConfigJSON: String,
        rounds: Int? = nil,
        roundsRepSchemeJSON: String? = nil,
        items: [(name: String, prescriptionJSON: String)]
    ) -> (WorkoutContext, [UUID]) {
        let workoutID = UUID()
        let userID = UUID()
        let blockID = UUID()
        let now = Date()
        var itemIDs: [UUID] = []
        var workoutItems: [WorkoutItem] = []
        var exercises: [UUID: Exercise] = [:]
        for (pos, spec) in items.enumerated() {
            let exID = UUID()
            let itemID = UUID()
            itemIDs.append(itemID)
            exercises[exID] = Exercise(id: exID, name: spec.name)
            workoutItems.append(WorkoutItem(
                id: itemID, blockID: blockID, position: pos,
                exerciseID: exID, prescriptionJSON: spec.prescriptionJSON
            ))
        }
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: timingMode,
            timingConfigJSON: timingConfigJSON,
            rounds: rounds, roundsRepSchemeJSON: roundsRepSchemeJSON, notes: nil
        )
        let workout = Workout(
            id: workoutID, userID: userID, name: "mode-test",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let ctx = WorkoutContext(
            workout: workout, blocks: [block],
            itemsByBlock: [workoutItems], exercises: exercises
        )
        return (ctx, itemIDs)
    }

    func testAMRAPBlockWaitsForResultCaptureAtTimeCap() {
        // Time cap 30s. After 2 logs the block cap elapses → tickBlockTimer
        // must leave the block active so the AMRAP result sheet can
        // capture the partial score.
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableClock(now: start)
        let (ctx, _) = makeSingleBlockContext(
            timingMode: .amrap,
            timingConfigJSON: #"{"time_cap_sec":30}"#,
            items: [
                (name: "Pull-ups", prescriptionJSON: #"{"reps":10}"#),
                (name: "Push-ups", prescriptionJSON: #"{"reps":15}"#),
            ]
        )
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()
        XCTAssertEqual(vm.state.route, .active)
        // blockEndsAt is now + 30
        XCTAssertEqual(vm.state.blockEndsAt?.timeIntervalSince1970, start.timeIntervalSince1970 + 30)

        // Log two sets — AMRAP rest = 0 so cursor auto-advances.
        vm.logSet(reps: 10, rir: nil)
        vm.logSet(reps: 15, rir: nil)
        XCTAssertNotEqual(vm.state.route, .complete)

        // Fast-forward past the time cap.
        clock.now = start.addingTimeInterval(35)
        vm.tickBlockTimer()
        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(vm.state.cursor.blockIndex, 0)
    }

    func testEMOMCursorRoundRobinsPerInterval() {
        // 2 items × 3 intervals. Seeded with round-robin advancement;
        // logSet → auto-advance (rest = 60s is NOT applied automatically
        // by logSet — EMOM's restDuration is interval_sec, so the VM
        // enters rest). We test the cursor walk via direct `advance()`.
        let start = Date(timeIntervalSince1970: 2_000_000)
        let clock = FixedClock(now: start)
        let (ctx, _) = makeSingleBlockContext(
            timingMode: .emom,
            timingConfigJSON: #"{"interval_sec":60,"total_minutes":3}"#,
            items: [
                (name: "Clean", prescriptionJSON: #"{"reps":5,"load_kg":60}"#),
                (name: "KB Swing", prescriptionJSON: #"{"reps":10,"load_kg":24}"#),
            ]
        )
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()

        // Initial cursor: item 0, interval 1.
        XCTAssertEqual(vm.state.cursor.itemIndex, 0)
        XCTAssertEqual(vm.state.cursor.setIndex, 1)

        // Log item 0 interval 1 → cursor lands on item 1 interval 1.
        vm.logSet(reps: 5, rir: nil)
        vm.advance()
        vm.startCurrentSet()
        XCTAssertEqual(vm.state.cursor.itemIndex, 1)
        XCTAssertEqual(vm.state.cursor.setIndex, 1)

        // Log item 1 interval 1 → cursor lands on item 0 interval 2.
        vm.logSet(reps: 10, rir: nil)
        vm.advance()
        vm.startCurrentSet()
        XCTAssertEqual(vm.state.cursor.itemIndex, 0)
        XCTAssertEqual(vm.state.cursor.setIndex, 2)

        // Log item 0 interval 2 → item 1 interval 2.
        vm.logSet(reps: 5, rir: nil)
        vm.advance()
        vm.startCurrentSet()
        XCTAssertEqual(vm.state.cursor.itemIndex, 1)
        XCTAssertEqual(vm.state.cursor.setIndex, 2)
    }

    func testCircuitRoundsWalkItemsThenRoundBumps() {
        // 3 items × 3 rounds. A 1-second between-exercises rest means
        // logSet enters .rest after each item (cursor unmoved); the test's
        // vm.advance() then walks the cursor. This mirrors the real flow
        // and keeps the cursor-path assertions unambiguous.
        let start = Date(timeIntervalSince1970: 3_000_000)
        let clock = FixedClock(now: start)
        let (ctx, _) = makeSingleBlockContext(
            timingMode: .circuit,
            timingConfigJSON: #"{"rest_between_exercises_sec":1,"rest_between_rounds_sec":30}"#,
            rounds: 3,
            items: [
                (name: "A", prescriptionJSON: #"{"reps":10}"#),
                (name: "B", prescriptionJSON: #"{"reps":12}"#),
                (name: "C", prescriptionJSON: #"{"reps":14}"#),
            ]
        )
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()
        // Structure should reflect round-based seeding.
        XCTAssertEqual(vm.state.structure.itemsPerBlock, [3])
        XCTAssertEqual(vm.state.structure.setsPerItem, [[3, 3, 3]])

        let expectedPath: [(item: Int, round: Int)] = [
            (0, 1), (1, 1), (2, 1),
            (0, 2), (1, 2), (2, 2),
            (0, 3), (1, 3), (2, 3),
        ]
        for (i, step) in expectedPath.enumerated() {
            XCTAssertEqual(vm.state.cursor.itemIndex, step.item, "step \(i) itemIndex")
            XCTAssertEqual(vm.state.cursor.setIndex, step.round, "step \(i) setIndex (round)")
            vm.logSet(reps: 10, rir: nil)
            if i + 1 < expectedPath.count {
                vm.advance()
            }
        }
        vm.advance()
        vm.startCurrentSet()
        XCTAssertEqual(vm.state.route, .complete)
    }

    func testSupersetBatchModeAdvancesWithoutLoggingUntilRoundRest() {
        let start = Date(timeIntervalSince1970: 4_000_000)
        let clock = MutableClock(now: start)
        let (ctx, itemIDs) = makeSingleBlockContext(
            timingMode: .superset,
            timingConfigJSON: #"{"rest_between_rounds_sec":20}"#,
            rounds: 2,
            items: [
                (name: "DB Press", prescriptionJSON: #"{"reps":10,"load_kg":30}"#),
                (name: "DB Row", prescriptionJSON: #"{"reps":12,"load_kg":35}"#),
            ]
        )
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()

        XCTAssertTrue(vm.isCurrentRoundRobinBatchMode)
        clock.now = start.addingTimeInterval(10)
        vm.advanceRoundRobinBatchStation()

        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(vm.state.cursor.itemIndex, 1)
        XCTAssertFalse(vm.state.items[0].sets[0].done)
        XCTAssertEqual(vm.state.items[0].sets[0].startedAt, start)
        XCTAssertNil(vm.state.items[0].sets[0].adjust)

        clock.now = start.addingTimeInterval(25)
        vm.advanceRoundRobinBatchStation()

        XCTAssertEqual(vm.state.route, .rest)
        XCTAssertTrue(vm.isRoundRobinBatchRoundRest)
        XCTAssertFalse(vm.isFinalRoundRobinBatchRoundRest)
        XCTAssertEqual(vm.roundRobinBatchRows().map(\.exerciseName), ["DB Press", "DB Row"])
        XCTAssertEqual(vm.roundRobinBatchRows().map(\.done), [false, false])

        vm.editRoundRobinBatchSet(
            itemID: itemIDs[0],
            setIndex: 1,
            loadKg: 32.5,
            reps: 9,
            rir: 2
        )
        XCTAssertEqual(vm.roundRobinBatchRows()[0].loadKg, 32.5)
        XCTAssertEqual(vm.roundRobinBatchRows()[0].reps, 9)
        XCTAssertEqual(vm.roundRobinBatchRows()[0].rir, 2)

        vm.advance()

        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(vm.state.cursor.itemIndex, 0)
        XCTAssertEqual(vm.state.cursor.setIndex, 2)
        XCTAssertTrue(vm.state.items[0].sets[0].done)
        XCTAssertTrue(vm.state.items[1].sets[0].done)
        XCTAssertEqual(vm.state.items[0].sets[0].loadKg, 32.5)
        XCTAssertEqual(vm.state.items[0].sets[0].reps, 9)
        XCTAssertEqual(vm.state.items[0].sets[0].rir, 2)
        XCTAssertEqual(vm.state.items[1].sets[0].reps, 12)
        XCTAssertEqual(vm.state.items[0].sets[0].startedAt, start)
        XCTAssertEqual(vm.state.items[1].sets[0].startedAt, start.addingTimeInterval(10))
    }

    func testSupersetBatchModeCommitsFinalRoundBeforeComplete() {
        let (ctx, _) = makeSingleBlockContext(
            timingMode: .superset,
            timingConfigJSON: #"{"rest_between_rounds_sec":20}"#,
            rounds: 1,
            items: [
                (name: "Curl", prescriptionJSON: #"{"reps":10,"load_kg":15}"#),
                (name: "Pressdown", prescriptionJSON: #"{"reps":15,"load_kg":25}"#),
            ]
        )
        let vm = ExecutionViewModel(context: ctx)
        vm.start()

        vm.advanceRoundRobinBatchStation()
        vm.advanceRoundRobinBatchStation()

        XCTAssertEqual(vm.state.route, .rest)
        XCTAssertTrue(vm.isRoundRobinBatchRoundRest)
        XCTAssertTrue(vm.isFinalRoundRobinBatchRoundRest)
        XCTAssertEqual(vm.roundRobinBatchRows().map(\.done), [false, false])

        vm.advance()

        XCTAssertEqual(vm.state.route, .complete)
        XCTAssertTrue(vm.state.items[0].sets[0].done)
        XCTAssertTrue(vm.state.items[1].sets[0].done)
    }

    func testCircuitDefaultsToStationLoggingMode() {
        let (ctx, _) = makeSingleBlockContext(
            timingMode: .circuit,
            timingConfigJSON: #"{"rest_between_exercises_sec":1,"rest_between_rounds_sec":30}"#,
            rounds: 2,
            items: [
                (name: "A", prescriptionJSON: #"{"reps":10}"#),
                (name: "B", prescriptionJSON: #"{"reps":12}"#),
            ]
        )
        let vm = ExecutionViewModel(context: ctx)
        vm.start()

        XCTAssertFalse(vm.isCurrentRoundRobinBatchMode)
    }

    func testForTimeRoundSchemeRendersEachRoundReps() {
        // Fran-like: 3 rounds × 2 items, scheme [21, 15, 9]. After the
        // cursor lands on each round, the driver's activeContent should
        // report the scheme's reps for that round.
        let (ctx, _) = makeSingleBlockContext(
            timingMode: .forTime,
            timingConfigJSON: #"{"time_cap_sec":600}"#,
            rounds: 3,
            roundsRepSchemeJSON: "[21,15,9]",
            items: [
                (name: "Thruster", prescriptionJSON: #"{"load_kg":43}"#),
                (name: "Pull-up", prescriptionJSON: "{}"),
            ]
        )
        let vm = ExecutionViewModel(context: ctx)
        vm.start()

        // Round 1, item 0 (Thruster) → 21 reps.
        XCTAssertEqual(vm.activeContent?.repsDisplay, "21")
        vm.logSet(reps: 21, rir: nil)
        // item 1 still round 1 → 21 reps.
        XCTAssertEqual(vm.activeContent?.repsDisplay, "21")
        vm.logSet(reps: 21, rir: nil)
        // item 0 round 2 → 15 reps.
        XCTAssertEqual(vm.activeContent?.repsDisplay, "15")
        vm.logSet(reps: 15, rir: nil)
        XCTAssertEqual(vm.activeContent?.repsDisplay, "15")
        vm.logSet(reps: 15, rir: nil)
        // item 0 round 3 → 9 reps.
        XCTAssertEqual(vm.activeContent?.repsDisplay, "9")
    }

    func testContinuousSingleItemCompletesAfterLog() {
        // Continuous block: one log → route becomes .complete.
        let (ctx, _) = makeSingleBlockContext(
            timingMode: .continuous,
            timingConfigJSON: #"{"target_duration_sec":600,"target_hr_zone":2}"#,
            items: [
                (name: "Run", prescriptionJSON: "{}"),
            ]
        )
        let vm = ExecutionViewModel(context: ctx)
        vm.start()
        // Seeded with 1 row, set-major advancement — logging the single
        // set with zero rest auto-advances past the end → .complete.
        vm.logSet(reps: 0, rir: nil)
        XCTAssertEqual(vm.state.route, .complete)
    }

    // MARK: - Clock injection

    func testFixedClockDrivesRestEndsAt() {
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_000_000))
        let (ctx, _) = makeContext(restSec: 180)
        let vm = ExecutionViewModel(context: ctx, clock: fixed)
        vm.start()
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 1)

        XCTAssertEqual(
            vm.state.restEndsAt?.timeIntervalSince1970,
            1_000_000 + 180
        )
    }

    func testExtendRestAddsRecoveryTimeToRestEndsAt() {
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_000_000))
        let (ctx, _) = makeContext(restSec: 180)
        let vm = ExecutionViewModel(context: ctx, clock: fixed)
        vm.start()
        vm.startCurrentSet()
        vm.logSet(reps: 5, rir: 1)

        vm.extendRest(by: 30)

        XCTAssertEqual(
            vm.state.restEndsAt?.timeIntervalSince1970,
            1_000_000 + 210
        )
    }

    func testLogSetWithEditedLoadWritesActualLoadBeforeLogging() {
        let fixed = FixedClock(now: Date(timeIntervalSince1970: 1_000_000))
        let (ctx, itemID) = makeContext(restSec: 180)
        let vm = ExecutionViewModel(context: ctx, clock: fixed)
        vm.start()

        vm.startCurrentSet()

        vm.logSet(loadKg: 92.5, reps: 5, rir: 1)

        let logged = vm.state.items
            .first(where: { $0.itemID == itemID })?
            .sets.first(where: { $0.setIndex == 1 })
        XCTAssertEqual(logged?.loadKg, 92.5)
        XCTAssertEqual(logged?.reps, 5)
        XCTAssertEqual(logged?.rir, 1)
        XCTAssertEqual(logged?.done, true)
    }

    // MARK: - bug-038

    /// Regression for bug-038 — Tabata rest timer showed 0:00 on entry to
    /// rest instead of ticking from 10s. Pins the invariant that a manual
    /// `logSet` on a Tabata block sets `restEndsAt = now + 10` (the
    /// hardcoded rest constant) and leaves the session on `.rest` with a
    /// live countdown. Also asserts the restDurationSeconds the VM exposes
    /// to the Rest screen's ring total is 10s so the ring's elapsed/total
    /// math lands on 0/10 at entry.
    func testTabataLogSetEntersRestWithTenSecondsRemaining() {
        let start = Date(timeIntervalSince1970: 5_000_000)
        let clock = MutableClock(now: start)
        let (ctx, _) = makeSingleBlockContext(
            timingMode: .tabata,
            timingConfigJSON: "{}",
            items: [
                (name: "Air Squats", prescriptionJSON: #"{"reps":20}"#),
            ]
        )
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()
        XCTAssertEqual(vm.state.route, .active)

        vm.logSet(reps: 18, rir: nil)

        XCTAssertEqual(vm.state.route, .rest)
        XCTAssertEqual(
            vm.state.restEndsAt?.timeIntervalSince1970,
            start.timeIntervalSince1970 + TabataDriver.restSec
        )
        XCTAssertEqual(vm.restDurationSeconds, TabataDriver.restSec)
        XCTAssertEqual(vm.restDurationSeconds, 10)
    }

    /// Advance → round 2 → logSet re-enters rest with a fresh 10s window
    /// (not cumulative, not stale). Guards against a regression where
    /// `enterBlockTimerIfNeeded` or the workEndsAt refresh somehow stamps
    /// `restEndsAt` with a stale value on re-entry into the same block.
    func testTabataRoundTwoLogSetRefreshesRestEndsAt() {
        let start = Date(timeIntervalSince1970: 7_000_000)
        let clock = MutableClock(now: start)
        let (ctx, _) = makeSingleBlockContext(
            timingMode: .tabata,
            timingConfigJSON: "{}",
            items: [
                (name: "Air Squats", prescriptionJSON: #"{"reps":20}"#),
            ]
        )
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()
        vm.startCurrentSet()
        vm.logSet(reps: 18, rir: nil)
        XCTAssertEqual(vm.state.route, .rest)

        // Advance clock past rest and advance cursor.
        clock.now = start.addingTimeInterval(12)
        vm.advance()
        vm.startCurrentSet()
        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(vm.state.cursor.setIndex, 2)

        // Log round 2; rest should be exactly now + 10 (not cumulative).
        clock.now = start.addingTimeInterval(30)
        vm.logSet(reps: 15, rir: nil)
        XCTAssertEqual(vm.state.route, .rest)
        XCTAssertEqual(
            vm.state.restEndsAt?.timeIntervalSince1970,
            clock.now.timeIntervalSince1970 + TabataDriver.restSec
        )
    }
}

// MARK: - Driver-direct tests

@MainActor
final class StraightSetsDriverTests: XCTestCase {

    func testRestDurationReadsTimingConfig() {
        let blockID = UUID()
        let itemID = UUID()
        let exerciseID = UUID()
        let workoutID = UUID()
        let userID = UUID()
        let now = Date()

        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":120,"rest_between_exercises_sec":240}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: #"{"sets":3,"reps":5,"load_kg":100}"#
        )
        let ctx = WorkoutContext(
            workout: Workout(id: workoutID, userID: userID, name: "x",
                             scheduledDate: now, status: .planned, source: .claude,
                             notes: nil, createdAt: now, updatedAt: now,
                             completedAt: nil, tagsJSON: nil),
            blocks: [block],
            itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "X")]
        )
        let state = SessionSeeder.seed(context: ctx).withRoute(.active)
        let driver = StraightSetsDriver()
        XCTAssertEqual(driver.restDuration(state: state, context: ctx), 120)
    }

    // bug-039: single-field timing configs should still produce a
    // functional between-sets rest. When `rest_between_exercises_sec`
    // is omitted, the parser defaults it to `rest_between_sets_sec` so
    // the driver returns the authored value instead of falling through
    // to 0 on a strict-parse failure.
    func testRestDurationDefaultsExercisesToSetsWhenMissing() {
        let blockID = UUID()
        let itemID = UUID()
        let exerciseID = UUID()
        let workoutID = UUID()
        let userID = UUID()
        let now = Date()

        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":15}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: #"{"sets":3,"reps":5,"load_kg":100}"#
        )
        let ctx = WorkoutContext(
            workout: Workout(id: workoutID, userID: userID, name: "x",
                             scheduledDate: now, status: .planned, source: .claude,
                             notes: nil, createdAt: now, updatedAt: now,
                             completedAt: nil, tagsJSON: nil),
            blocks: [block],
            itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "X")]
        )
        let state = SessionSeeder.seed(context: ctx).withRoute(.active)
        let driver = StraightSetsDriver()
        XCTAssertEqual(driver.restDuration(state: state, context: ctx), 15)
    }

    func testActiveContentShowsLoadAndReps() {
        let blockID = UUID()
        let itemID = UUID()
        let exerciseID = UUID()
        let workoutID = UUID()
        let userID = UUID()
        let now = Date()

        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":180,"rest_between_exercises_sec":180}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: #"{"sets":4,"reps":5,"load_kg":102.5}"#
        )
        let ctx = WorkoutContext(
            workout: Workout(id: workoutID, userID: userID, name: "x",
                             scheduledDate: now, status: .planned, source: .claude,
                             notes: nil, createdAt: now, updatedAt: now,
                             completedAt: nil, tagsJSON: nil),
            blocks: [block],
            itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Bench")]
        )
        let state = SessionSeeder.seed(context: ctx).withRoute(.active)
        let content = StraightSetsDriver().activeContent(state: state, context: ctx)

        XCTAssertEqual(content?.exerciseName, "Bench")
        XCTAssertEqual(content?.setIndex, 1)
        XCTAssertEqual(content?.totalSets, 4)
        // R2.10: JSON fixture omits `weight_unit` → defaults to .lb suffix.
        XCTAssertEqual(content?.loadDisplay, "102.5 lb")
        XCTAssertEqual(content?.repsDisplay, "5")
    }

    func testActiveContentShowsKgSuffixWhenPrescribedKg() {
        // R2.10: an explicit `weight_unit: "kg"` on the prescription
        // still renders as "kg" — the cutover didn't remove kg support,
        // it changed the default. Locks that behavior.
        let blockID = UUID()
        let itemID = UUID()
        let exerciseID = UUID()
        let workoutID = UUID()
        let userID = UUID()
        let now = Date()
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":180}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: #"{"sets":4,"reps":5,"load_kg":102.5,"weight_unit":"kg"}"#
        )
        let ctx = WorkoutContext(
            workout: Workout(id: workoutID, userID: userID, name: "x",
                             scheduledDate: now, status: .planned, source: .claude,
                             notes: nil, createdAt: now, updatedAt: now,
                             completedAt: nil, tagsJSON: nil),
            blocks: [block],
            itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Bench")]
        )
        let state = SessionSeeder.seed(context: ctx).withRoute(.active)
        let content = StraightSetsDriver().activeContent(state: state, context: ctx)
        XCTAssertEqual(content?.loadDisplay, "102.5 kg")
    }
}

// MARK: - Helpers

private actor InMemorySessionStore: SessionStore {
    private var payload: Data?

    func load() async throws -> Data? { payload }
    func save(_ payload: Data) async throws { self.payload = payload }
    func clear() async throws { payload = nil }
}

private extension SessionState {
    /// Produce a copy with a different route (test convenience).
    func withRoute(_ route: SessionState.Route) -> SessionState {
        var next = self
        next.route = route
        return next
    }
}

/// Reference-typed clock whose `now` is mutable across VM boundaries.
/// `FixedClock` is a value type, so tests that need to advance time after
/// the VM captures the clock (e.g. "let block cap elapse") need a class-
/// backed clock. Scoped to the FeaturesExecutionTests — not a public
/// helper since production should not need mutable shared-now semantics.
private final class MutableClock: Clock, @unchecked Sendable {
    var now: Date
    init(now: Date) { self.now = now }
}

/// Records invocations of the `LocalCompletionWriter` — actor-isolated so
/// parallel closure invocations serialize.
private actor CompletionRecorder {
    struct Call {
        let workout: Workout
        let record: WorkoutCompletionRecord
    }
    private(set) var calls: [Call] = []

    func record(_ record: WorkoutCompletionRecord) {
        calls.append(Call(
            workout: record.workout,
            record: record
        ))
    }
}
