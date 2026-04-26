// ExecutionViewModelTickBlockTimerTests.swift
//
// Bug-042 regression coverage. `ExecutionViewModel.tickBlockTimer()`
// exists + is unit-tested, but prior to this fix no view invoked it at
// runtime — AMRAP / ForTime / EMOM / Tabata caps were dead code. This
// test file pins two complementary invariants:
//
//   1. **View wiring (source inspection).** `ActiveView.swift` and
//      `RestView.swift` both instantiate a `Timer.publish(every: 1, ...)`,
//      gate on active cap/work/rest timing state, and call
//      `viewModel.tickBlockTimer()` on each tick. Swift has no ViewInspector
//      analogue in this repo — previews + `xcodebuild` are the visual
//      check — so we read the source files and assert the canonical
//      wiring strings are present. Any refactor that removes the tick
//      trips these tests, not the runtime.
//
//   2. **VM tick behavior under a moving clock.** `tickBlockTimer()`
//      increments `tickCallCount` on every call (even no-ops), routes
//      clock-owned modes once `clock.now >= state.blockEndsAt`, and does
//      not bypass manual score capture for AMRAP / For Time.
//      We drive the VM's `tickBlockTimer()` directly three times across
//      advancing wall-clock instants to mirror "TimelineView fires the
//      view's `.onReceive` once per second" without booting a SwiftUI
//      runtime in tests.
//
// If SwiftUI view testing ever becomes practical in this harness, swap
// the source-inspection half for a mounted-view assertion. Until then
// this is the strongest check available.

import XCTest
import CoreDomain
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class ExecutionViewModelTickBlockTimerTests: XCTestCase {

    // MARK: - VM behavior

    func testForTimeStartExposesCapTimerPresentationImmediately() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableTickClock(now: start)
        let (ctx, _) = makeForTimeContext(timeCapSec: 600)
        let vm = ExecutionViewModel(context: ctx, clock: clock)

        vm.start()

        let timer = vm.timerPresentation(now: start)
        XCTAssertEqual(timer?.label, "TIME CAP")
        XCTAssertEqual(timer?.direction, .countdown)
        XCTAssertEqual(timer?.seconds, 600)
        XCTAssertEqual(timer?.inlineText, "TIME CAP 10:00")

        clock.now = start.addingTimeInterval(2)
        XCTAssertEqual(vm.timerPresentation(now: clock.now)?.inlineText, "TIME CAP 9:58")
    }

    func testAMRAPStartExposesGlobalCapTimerPresentationImmediately() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableTickClock(now: start)
        let (ctx, _) = makeAMRAPContext(timeCapSec: 600)
        let vm = ExecutionViewModel(context: ctx, clock: clock)

        vm.start()

        let timer = vm.timerPresentation(now: start)
        XCTAssertEqual(timer?.label, "AMRAP CAP")
        XCTAssertEqual(timer?.direction, .countdown)
        XCTAssertEqual(timer?.seconds, 600)
        XCTAssertEqual(timer?.inlineText, "AMRAP CAP 10:00")
    }

    func testForTimeStartExposesNextExerciseContext() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableTickClock(now: start)
        let (ctx, _) = makeForTimeContext(timeCapSec: 600)
        let vm = ExecutionViewModel(context: ctx, clock: clock)

        vm.start()

        XCTAssertEqual(vm.nextUpPresentation?.label, "next exercise")
        XCTAssertEqual(vm.nextUpPresentation?.title, "Pull-up")
        XCTAssertEqual(vm.nextUpPresentation?.detail, "BW · 12 reps")
    }

    func testStraightSetStartExposesReadyThenElapsedTimerWhenNoCountdownExists() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableTickClock(now: start)
        let (ctx, _) = makeStraightSetsContext()
        let vm = ExecutionViewModel(context: ctx, clock: clock)

        vm.start()

        clock.now = start.addingTimeInterval(7)
        let readyTimer = vm.timerPresentation(now: clock.now)
        XCTAssertEqual(readyTimer?.label, "WAITING TO START")
        XCTAssertEqual(readyTimer?.direction, .elapsed)
        XCTAssertEqual(readyTimer?.seconds, 7)
        XCTAssertEqual(readyTimer?.inlineText, "WAITING TO START 0:07")

        vm.startCurrentSet()

        clock.now = start.addingTimeInterval(12)
        let workTimer = vm.timerPresentation(now: clock.now)
        XCTAssertEqual(workTimer?.label, "SET ELAPSED")
        XCTAssertEqual(workTimer?.direction, .elapsed)
        XCTAssertEqual(workTimer?.seconds, 5)
        XCTAssertEqual(workTimer?.inlineText, "SET ELAPSED 0:05")
    }

    func testStraightSetStartExposesNextSetContext() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableTickClock(now: start)
        let (ctx, _) = makeStraightSetsContext()
        let vm = ExecutionViewModel(context: ctx, clock: clock)

        vm.start()

        XCTAssertEqual(vm.nextUpPresentation?.label, "next set")
        XCTAssertEqual(vm.nextUpPresentation?.title, "Bench")
        XCTAssertEqual(vm.nextUpPresentation?.detail, "100 lb · 5 reps")
    }

    func testRestBlockStartExposesNextBlockContext() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableTickClock(now: start)
        let ctx = makeRestThenStraightSetsContext()
        let vm = ExecutionViewModel(context: ctx, clock: clock)

        vm.start()

        XCTAssertEqual(vm.state.route, .rest)
        XCTAssertEqual(vm.nextUpPresentation?.label, "next block")
        XCTAssertEqual(vm.nextUpPresentation?.title, "Bench")
        XCTAssertEqual(vm.nextUpPresentation?.detail, "185 lb · 5 reps")
    }

    /// `testActiveViewInvokesTickBlockTimerOncePerSecond` — contract from
    /// the bug-042 brief. We can't mount a SwiftUI `TimelineView` in a
    /// unit test harness, so we mirror its effect: call
    /// `viewModel.tickBlockTimer()` three times, advancing the clock by
    /// 1s between each call. AMRAP caps now require athlete-facing result
    /// capture, so the low-level tick must not silently complete the block.
    func testActiveViewInvokesTickBlockTimerOncePerSecond() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableTickClock(now: start)
        let (ctx, _) = makeAMRAPContext(timeCapSec: 2)
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()
        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(
            vm.state.blockEndsAt?.timeIntervalSince1970,
            start.timeIntervalSince1970 + 2,
            "AMRAP start must stamp blockEndsAt = now + time_cap_sec"
        )

        // Tick 1: 1s after start — cap not yet elapsed, no-op.
        clock.now = start.addingTimeInterval(1)
        vm.tickBlockTimer()
        XCTAssertEqual(vm.tickCallCount, 1)
        XCTAssertNotEqual(vm.state.route, .complete)

        // Tick 2: 2s after start — cap elapsed, but VM waits for the
        // AMRAP result sheet instead of dispatching `.complete`.
        clock.now = start.addingTimeInterval(2)
        vm.tickBlockTimer()
        XCTAssertEqual(vm.tickCallCount, 2)
        XCTAssertEqual(vm.state.route, .active)

        // Tick 3: 3s after start — route already complete, no-op but
        // count still increments (safe to call every second regardless
        // of state).
        clock.now = start.addingTimeInterval(3)
        vm.tickBlockTimer()
        XCTAssertEqual(vm.tickCallCount, 3)
        XCTAssertEqual(vm.state.route, .active)
    }

    /// Calling `tickBlockTimer` when no cap/work/rest boundary is active
    /// (straight_sets block) is a no-op. View-side gates are an
    /// optimization — correctness doesn't depend on them.
    func testTickBlockTimerIsSafeWhenNoBlockEndsAt() {
        let (ctx, _) = makeStraightSetsContext()
        let vm = ExecutionViewModel(context: ctx)
        vm.start()
        XCTAssertNil(vm.state.blockEndsAt)

        for _ in 0..<5 {
            vm.tickBlockTimer()
        }
        XCTAssertEqual(vm.tickCallCount, 5)
        XCTAssertEqual(vm.state.route, .active)
        XCTAssertNil(vm.state.blockEndsAt)
    }

    func testStraightSetRestDoesNotAutoAdvanceWhenOverRested() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableTickClock(now: start)
        let (ctx, _) = makeStraightSetsContext()
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()
        vm.startCurrentSet()

        clock.now = start.addingTimeInterval(10)
        vm.logSet(reps: 5, rir: nil)

        XCTAssertEqual(vm.state.route, .rest)
        XCTAssertFalse(vm.currentRestShouldAutoAdvance)

        clock.now = start.addingTimeInterval(10 + 120)
        vm.tickBlockTimer()

        XCTAssertEqual(vm.state.route, .rest)
        XCTAssertEqual(vm.state.cursor.setIndex, 1)
    }

    func testIntervalsStartStampsWorkWindowAndAutoLogsToRest() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableTickClock(now: start)
        let (ctx, itemID) = makeTimedIntervalsContext()
        let vm = ExecutionViewModel(context: ctx, clock: clock)

        vm.start()

        XCTAssertEqual(vm.state.workEndsAt?.timeIntervalSince1970, start.timeIntervalSince1970 + 5)
        XCTAssertEqual(vm.timerPresentation(now: start)?.inlineText, "WORK 0:05")

        clock.now = start.addingTimeInterval(5)
        vm.tickBlockTimer()

        XCTAssertEqual(vm.state.route, .rest)
        XCTAssertNil(vm.state.workEndsAt)
        XCTAssertEqual(vm.state.restEndsAt?.timeIntervalSince1970, start.timeIntervalSince1970 + 8)
        let row = try XCTUnwrap(vm.state.items.first(where: { $0.itemID == itemID })?.sets.first)
        XCTAssertTrue(row.done)
        XCTAssertEqual(row.durationSec, 5)
    }

    func testCustomTimedSegmentsAutoAdvanceToNextSegment() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableTickClock(now: start)
        let ctx = makeTimedCustomContext()
        let vm = ExecutionViewModel(context: ctx, clock: clock)

        vm.start()

        XCTAssertEqual(vm.state.workEndsAt?.timeIntervalSince1970, start.timeIntervalSince1970 + 15)
        XCTAssertEqual(vm.timerPresentation(now: start)?.inlineText, "WORK 0:15")

        clock.now = start.addingTimeInterval(15)
        vm.tickBlockTimer()

        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(vm.state.cursor.setIndex, 2)
        XCTAssertEqual(vm.activeContent?.loadDisplay, "REST · easy")
        XCTAssertEqual(vm.activeContent?.repsDisplay, "10 s")
        XCTAssertEqual(vm.state.workEndsAt?.timeIntervalSince1970, start.timeIntervalSince1970 + 25)
    }

    func testContinuousDurationTargetStampsTargetCountdownOnStart() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableTickClock(now: start)
        let (ctx, _) = makeContinuousContext(configJSON: #"{"target_duration_sec":12}"#)
        let vm = ExecutionViewModel(context: ctx, clock: clock)

        vm.start()

        XCTAssertEqual(vm.state.workEndsAt?.timeIntervalSince1970, start.timeIntervalSince1970 + 12)
        XCTAssertEqual(vm.timerPresentation(now: start)?.inlineText, "TARGET 0:12")
        XCTAssertFalse(vm.continuousTargetReached)
    }

    func testContinuousDistanceTargetStaysManualUntilSensorDistanceExists() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableTickClock(now: start)
        let (ctx, _) = makeContinuousContext(configJSON: #"{"target_distance_m":2000}"#)
        let vm = ExecutionViewModel(context: ctx, clock: clock)

        vm.start()

        XCTAssertNil(vm.state.workEndsAt)
        XCTAssertEqual(vm.timerPresentation(now: start)?.inlineText, "ELAPSED 0:00")
    }

    func testStandaloneContinuousTargetReachedWaitsForCompleteOrContinue() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableTickClock(now: start)
        let (ctx, _) = makeContinuousContext(configJSON: #"{"target_duration_sec":12}"#)
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()

        clock.now = start.addingTimeInterval(12)
        vm.tickBlockTimer()

        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(vm.timerPresentation(now: clock.now)?.inlineText, "TARGET 0:00")
        XCTAssertTrue(vm.continuousTargetReached)

        vm.continueContinuousPastTarget()

        XCTAssertNil(vm.state.workEndsAt)
        XCTAssertFalse(vm.continuousTargetReached)
        XCTAssertEqual(vm.timerPresentation(now: clock.now)?.inlineText, "ELAPSED 0:12")
    }

    func testComposedContinuousDurationTargetAutoTransitionsToNextBlock() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableTickClock(now: start)
        let (ctx, runItemID, pressItemID) = makeContinuousThenStraightSetsContext(
            configJSON: #"{"target_duration_sec":12}"#
        )
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()

        clock.now = start.addingTimeInterval(12)
        vm.tickBlockTimer()

        XCTAssertEqual(vm.state.route, .active)
        XCTAssertEqual(vm.state.cursor.blockIndex, 1)
        XCTAssertEqual(vm.state.cursor.itemIndex, 0)
        XCTAssertEqual(vm.state.cursor.setIndex, 1)
        XCTAssertTrue(vm.requiresExplicitSetStartForCurrentWork)
        XCTAssertFalse(vm.isCurrentWorkStarted)
        XCTAssertNil(vm.state.workEndsAt)

        let runRow = try XCTUnwrap(
            vm.state.items.first(where: { $0.itemID == runItemID })?.sets.first
        )
        XCTAssertTrue(runRow.done)
        XCTAssertEqual(runRow.durationSec, 12)

        vm.logSet(reps: 5, rir: 2)
        let pressItem = vm.state.items.first { $0.itemID == pressItemID }
        XCTAssertEqual(
            pressItem?.sets.first?.done,
            false,
            "auto-transition into strength still must require Set Start"
        )
    }

    /// Regression for "Tabata placeholder log dropped after long suspend
    /// past block cap". When the phone wakes with BOTH `workEndsAt`
    /// (per-round work window) and `blockEndsAt` (total 240s cap) overdue,
    /// the tick must still write the 8th round's placeholder log BEFORE
    /// flipping the route to `.complete`. The prior ordering returned on
    /// the block-cap path first and the final log was lost.
    func testTabataWorkWindowAutoLogsEvenIfBlockCapElapsed() {
        // Fix the clock at T0; start the Tabata block so workEndsAt and
        // blockEndsAt are both set. Then jump the clock past both anchors
        // and tick once.
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableTickClock(now: start)
        let ctx = makeTabataContext(prescriptionJSON: "{}")
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()
        XCTAssertEqual(vm.state.route, .active)
        // Anchors are set: workEndsAt at T0+20s, blockEndsAt at T0+240s.
        XCTAssertEqual(
            vm.state.workEndsAt?.timeIntervalSince1970,
            start.timeIntervalSince1970 + TabataDriver.workSec
        )
        XCTAssertEqual(
            vm.state.blockEndsAt?.timeIntervalSince1970,
            start.timeIntervalSince1970
                + Double(TabataDriver.rounds)
                    * (TabataDriver.workSec + TabataDriver.restSec)
        )

        // Prior sets logged so we can assert the TICK adds one more.
        let itemID = ctx.itemsByBlock[0][0].id
        let doneBefore = vm.state.items
            .first(where: { $0.itemID == itemID })?
            .sets.filter(\.done).count ?? -1
        XCTAssertEqual(doneBefore, 0, "no rounds logged before the long suspend")

        // Jump past BOTH anchors — simulate the phone waking up a long
        // time after the Tabata block should have ended.
        clock.now = start.addingTimeInterval(10_000)
        vm.tickBlockTimer()

        // Must have auto-logged the cardio duration BEFORE completing,
        // so the item's logged-set count bumps to 1.
        let doneAfter = vm.state.items
            .first(where: { $0.itemID == itemID })?
            .sets.filter(\.done).count ?? -1
        XCTAssertEqual(
            doneAfter, 1,
            "work-window cardio log must run BEFORE the block-cap complete path"
        )
        // And the block cap still fires — route is .complete after this tick.
        XCTAssertEqual(
            vm.state.route, .complete,
            "block cap still dispatches .complete in the same tick"
        )
    }

    // MARK: - View wiring (source inspection)

    func testActiveViewWiresTickBlockTimerViaPeriodicTimer() throws {
        let source = try loadFeatureSource(named: "ActiveView.swift")
        XCTAssertTrue(
            source.contains("Timer.publish(every: 1"),
            "ActiveView must carry a 1-second Timer.publish for the bug-042 tick source"
        )
        XCTAssertTrue(
            source.contains(".autoconnect()"),
            "ActiveView's tick timer must autoconnect so the publisher starts/stops with view lifecycle"
        )
        XCTAssertTrue(
            source.contains(".onReceive(tickTimer)"),
            "ActiveView must attach .onReceive(tickTimer) so the VM's tick fires on each interval"
        )
        XCTAssertTrue(
            source.contains("viewModel.tickBlockTimer()"),
            "ActiveView must invoke viewModel.tickBlockTimer() — the behavior guarded by bug-042"
        )
        XCTAssertTrue(
            source.contains("shouldTickBlockTimer("),
            "ActiveView's tick must gate through shouldTickBlockTimer so non-time-capped blocks don't wake the VM and metcon result entry cannot be preempted"
        )
    }

    func testRestViewWiresTickBlockTimerViaPeriodicTimer() throws {
        let source = try loadFeatureSource(named: "RestView.swift")
        XCTAssertTrue(
            source.contains("Timer.publish(every: 1"),
            "RestView must carry a 1-second Timer.publish — block caps can elapse during rest"
        )
        XCTAssertTrue(
            source.contains(".autoconnect()"),
            "RestView's tick timer must autoconnect"
        )
        XCTAssertTrue(
            source.contains(".onReceive(tickTimer)"),
            "RestView must attach .onReceive(tickTimer)"
        )
        XCTAssertTrue(
            source.contains("viewModel.tickBlockTimer()"),
            "RestView must invoke viewModel.tickBlockTimer() — an EMOM / For-Time cap can expire while the user rests"
        )
        XCTAssertTrue(
            source.contains("state.blockEndsAt != nil"),
            "RestView's tick must gate on state.blockEndsAt != nil"
        )
        XCTAssertTrue(
            source.contains("state.workEndsAt != nil"),
            "RestView must also tick active work windows that can expire during rest"
        )
        XCTAssertTrue(
            source.contains("currentRestShouldAutoAdvance"),
            "RestView must also tick clock-owned rest transitions without waking strength over-rest"
        )
    }

    func testActiveViewScopesSwapLongPressAwayFromTimerHero() throws {
        let source = try loadFeatureSource(named: "ActiveView.swift")
        XCTAssertTrue(
            source.contains("hold exercise to swap"),
            "ActiveView should expose a visible hint for the hidden long-press swap affordance"
        )
        XCTAssertFalse(
            source.contains("The whole card is the long-press zone"),
            "Swap should not be attached to the whole active card; the timer needs timer-only semantics"
        )
        XCTAssertTrue(
            source.contains("Long press to open exercise alternatives"),
            "The narrowed swap target should still be accessible"
        )
    }

    func testRestViewLabelsEditableJustLoggedPills() throws {
        let source = try loadFeatureSource(named: "RestView.swift")
        XCTAssertTrue(
            source.contains("tap to correct"),
            "RestView should make just-logged correction controls discoverable"
        )
        XCTAssertTrue(
            source.contains("Tap to correct logged reps"),
            "Editable rest pills should carry accessibility hints"
        )
    }

    func testRestViewHidesStrengthJustLoggedPillsForCardio() throws {
        let source = try loadFeatureSource(named: "RestView.swift")
        XCTAssertTrue(
            source.contains("shouldShowStrengthJustDidRow"),
            "RestView should centralize the strength-only just-logged row gate"
        )
        XCTAssertTrue(
            source.contains("!viewModel.isCurrentBlockCardio"),
            "Cardio rest screens must not render strength correction pills like 0 reps / RIR"
        )
    }

    func testRestAddTimeControlsAreManualRecoveryOnly() throws {
        let source = try loadFeatureSource(named: "RestView.swift")
        XCTAssertTrue(
            source.contains("restExtensionControls"),
            "RestView should keep add-time controls as a named timer affordance"
        )
        XCTAssertTrue(
            source.contains("if !viewModel.currentRestShouldAutoAdvance"),
            "Rest add-time controls should be hidden during clock-owned interval rests"
        )
        XCTAssertTrue(
            source.contains("accessibilityLabel(\"add 30 seconds rest\")"),
            "RestView should expose the +30 sec control to accessibility"
        )
        XCTAssertFalse(
            source.contains("if isOverdue {\n                    restExtensionControls"),
            "Rest add-time controls should not be gated behind the overdue state"
        )
    }

    func testClockOwnedRestCannotBeExtended() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MutableTickClock(now: start)
        let ctx = makeTabataContext()
        let vm = ExecutionViewModel(context: ctx, clock: clock)
        vm.start()

        clock.now = start.addingTimeInterval(TabataDriver.workSec)
        vm.tickBlockTimer()

        XCTAssertTrue(vm.currentRestShouldAutoAdvance)
        let originalRestEnd = vm.state.restEndsAt
        vm.extendRest(by: 30)

        XCTAssertEqual(vm.state.restEndsAt, originalRestEnd,
            "clock-owned interval rest must not be delayed by manual add-time")
    }

    func testNextUpCardsOpenReadOnlyPreviewSheet() throws {
        let activeSource = try loadFeatureSource(named: "ActiveView.swift")
        let restSource = try loadFeatureSource(named: "RestView.swift")
        let restSheetsSource = try loadFeatureSource(named: "RestView+Sheets.swift")
        let sheetSource = try loadFeatureSource(named: "Sheets/NextUpSheet.swift")

        XCTAssertTrue(
            activeSource.contains("tap to preview"),
            "Active next-up card should expose its tap affordance"
        )
        XCTAssertTrue(
            activeSource.contains("showNextUpSheet = true"),
            "Active next-up card should open the preview sheet"
        )
        XCTAssertTrue(
            restSource.contains("activeSheet = .nextUp"),
            "Rest next-up card should open through the existing sheet router"
        )
        XCTAssertTrue(
            restSheetsSource.contains("NextUpSheet(")
                && restSheetsSource.contains("nextUp: nextUp")
                && restSheetsSource.contains("workQueue: viewModel.executionProjection"),
            "Rest sheet router should render the shared preview sheet"
        )
        XCTAssertTrue(
            sheetSource.contains("read-only workout preview"),
            "Next-up sheet must clearly stay informational, not plan-editing"
        )
        XCTAssertTrue(
            sheetSource.contains("if workQueue.isEmpty"),
            "Next-up sheet should not render the legacy next-up card when the projection queue is available"
        )
        XCTAssertTrue(
            sheetSource.contains("title: \"done\""),
            "Next-up sheet should provide an explicit one-handed dismiss control"
        )
        XCTAssertFalse(
            sheetSource.contains("viewModel."),
            "Next-up sheet should not mutate execution state"
        )
    }

    func testContinuousTargetReachedShowsCompleteAndContinueActions() throws {
        let source = try loadFeatureSource(named: "ActiveView+LogButton.swift")
        XCTAssertTrue(
            source.contains("viewModel.continuousTargetReached"),
            "Cardio log buttons should branch on continuous target expiry"
        )
        XCTAssertTrue(
            source.contains("title: \"continue\""),
            "Standalone continuous target expiry should offer continue"
        )
        XCTAssertTrue(
            source.contains("continueContinuousPastTarget()"),
            "Continue must clear the target deadline rather than logging the effort"
        )
    }

    // MARK: - Helpers

    private func makeAMRAPContext(
        timeCapSec: Int
    ) -> (WorkoutContext, UUID) {
        let workoutID = UUID()
        let userID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "amrap",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .amrap,
            timingConfigJSON: #"{"time_cap_sec":\#(timeCapSec)}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: #"{"reps":10}"#
        )
        let ctx = WorkoutContext(
            workout: workout, blocks: [block], itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Pull-ups")]
        )
        return (ctx, itemID)
    }

    private func makeForTimeContext(
        timeCapSec: Int
    ) -> (WorkoutContext, UUID) {
        let workoutID = UUID()
        let userID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let nextItemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "for time",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .forTime,
            timingConfigJSON: #"{"time_cap_sec":\#(timeCapSec)}"#,
            rounds: 2, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: #"{"reps":12,"load_kg":43.1}"#
        )
        let nextExerciseID = UUID()
        let nextItem = WorkoutItem(
            id: nextItemID, blockID: blockID, position: 1,
            exerciseID: nextExerciseID,
            prescriptionJSON: #"{"reps":12}"#
        )
        let ctx = WorkoutContext(
            workout: workout, blocks: [block], itemsByBlock: [[item, nextItem]],
            exercises: [
                exerciseID: Exercise(id: exerciseID, name: "Thruster"),
                nextExerciseID: Exercise(id: nextExerciseID, name: "Pull-up")
            ]
        )
        return (ctx, itemID)
    }

    /// Single-item tabata context for the long-suspend regression test.
    /// Matches the shape `ExecutionViewModelPersistencePipelineTests`
    /// uses for its Tabata restore coverage.
    private func makeTabataContext(prescriptionJSON: String = #"{"reps":20}"#) -> WorkoutContext {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "Tabata",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .tabata,
            timingConfigJSON: "{}",
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: prescriptionJSON
        )
        return WorkoutContext(
            workout: workout, blocks: [block],
            itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Air Squats")]
        )
    }

    private func makeStraightSetsContext() -> (WorkoutContext, UUID) {
        let workoutID = UUID()
        let userID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "ss",
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
            prescriptionJSON: #"{"sets":3,"reps":5,"load_kg":100}"#
        )
        let ctx = WorkoutContext(
            workout: workout, blocks: [block], itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Bench")]
        )
        return (ctx, itemID)
    }

    private func makeRestThenStraightSetsContext() -> WorkoutContext {
        let workoutID = UUID()
        let userID = UUID()
        let restBlockID = UUID()
        let strengthBlockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "warmup then strength",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let restBlock = Block(
            id: restBlockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: "Warm-up", timingMode: .rest,
            timingConfigJSON: #"{"duration_sec":60}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let strengthBlock = Block(
            id: strengthBlockID, workoutID: workoutID, parentBlockID: nil,
            position: 1, name: "Main", timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":90,"rest_between_exercises_sec":120}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: strengthBlockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: #"{"sets":4,"reps":5,"load_kg":185,"unit":"lb"}"#
        )
        return WorkoutContext(
            workout: workout,
            blocks: [restBlock, strengthBlock],
            itemsByBlock: [[], [item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Bench")]
        )
    }

    private func makeTimedIntervalsContext() -> (WorkoutContext, UUID) {
        let workoutID = UUID()
        let userID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "intervals",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .intervals,
            timingConfigJSON: #"{"work_sec":5,"rest_sec":3,"interval_count":2}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: "{}"
        )
        return (
            WorkoutContext(
                workout: workout, blocks: [block], itemsByBlock: [[item]],
                exercises: [exerciseID: Exercise(id: exerciseID, name: "Run")]
            ),
            itemID
        )
    }

    private func makeTimedCustomContext() -> WorkoutContext {
        let workoutID = UUID()
        let userID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "custom",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .custom,
            timingConfigJSON: #"""
            {"segments":[
              {"type":"work","duration_sec":15,"label":"hard"},
              {"type":"rest","duration_sec":10,"label":"easy"}
            ]}
            """#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: "{}"
        )
        return WorkoutContext(
            workout: workout, blocks: [block], itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Run")]
        )
    }

    private func makeContinuousContext(
        configJSON: String
    ) -> (WorkoutContext, UUID) {
        let workoutID = UUID()
        let userID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "continuous",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .continuous,
            timingConfigJSON: configJSON,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON: "{}"
        )
        return (
            WorkoutContext(
                workout: workout, blocks: [block], itemsByBlock: [[item]],
                exercises: [exerciseID: Exercise(id: exerciseID, name: "Run")]
            ),
            itemID
        )
    }

    private func makeContinuousThenStraightSetsContext(
        configJSON: String
    ) -> (WorkoutContext, UUID, UUID) {
        let userID = UUID()
        let workoutID = UUID()
        let runBlockID = UUID()
        let pressBlockID = UUID()
        let runExerciseID = UUID()
        let pressExerciseID = UUID()
        let runItemID = UUID()
        let pressItemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "run then press",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let runBlock = Block(
            id: runBlockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: "run", timingMode: .continuous,
            timingConfigJSON: configJSON,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let pressBlock = Block(
            id: pressBlockID, workoutID: workoutID, parentBlockID: nil,
            position: 1, name: "press", timingMode: .straightSets,
            timingConfigJSON: #"{"rest_between_sets_sec":90}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let runItem = WorkoutItem(
            id: runItemID, blockID: runBlockID, position: 0,
            exerciseID: runExerciseID,
            prescriptionJSON: "{}"
        )
        let pressItem = WorkoutItem(
            id: pressItemID, blockID: pressBlockID, position: 0,
            exerciseID: pressExerciseID,
            prescriptionJSON: #"{"sets":1,"reps":5,"load_kg":100}"#
        )
        return (
            WorkoutContext(
                workout: workout,
                blocks: [runBlock, pressBlock],
                itemsByBlock: [[runItem], [pressItem]],
                exercises: [
                    runExerciseID: Exercise(id: runExerciseID, name: "Run"),
                    pressExerciseID: Exercise(id: pressExerciseID, name: "Bench"),
                ]
            ),
            runItemID,
            pressItemID
        )
    }

    /// Load a source file from `../../Sources/FeaturesExecution` relative
    /// to this test file via `#filePath`. The swift package layout is
    /// stable (tests sit next to sources in a standard SwiftPM tree), so
    /// the relative walk is safe across machines and CI.
    private func loadFeatureSource(
        named filename: String,
        filePath: String = #filePath
    ) throws -> String {
        let testFileURL = URL(fileURLWithPath: filePath)
        // .../Tests/FeaturesExecutionTests/<thisfile>
        // → .../Tests/FeaturesExecutionTests/
        // → .../Tests/
        // → .../
        // → .../Sources/FeaturesExecution/<filename>
        let pkgRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = pkgRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("FeaturesExecution")
            .appendingPathComponent(filename)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}

// MARK: - Helpers

/// A class-backed mutable clock. `FixedClock` is a value type — tests that
/// need to advance the clock after the VM captures it need reference-
/// typed storage. Local-scoped to this file (mirrors the pattern in
/// `ExecutionViewModelTests.swift`).
private final class MutableTickClock: Clock, @unchecked Sendable {
    var now: Date
    init(now: Date) { self.now = now }
}
