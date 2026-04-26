// CardioDisplayQa043Tests.swift
//
// Regression coverage for qa-043. Before the fix:
//
//   * Continuous blocks with `target_duration_sec = 2700` rendered the
//     Active hero as "45 min reps" — the view appended " reps" to the
//     driver's primary-target display.
//   * Intervals blocks with `work_distance_m = 400` rendered "400 m
//     reps" for the same reason.
//   * The Complete ledger rendered "1×0 @ BW" for every cardio item
//     because the strength `N×R @ load` template fell through with
//     `reps=0, loadKg=nil`.
//
// Post-fix:
//
//   * `ActiveContent.kind = .cardio` (driver-populated) flips the
//     Active hero to render the primary target without " reps".
//   * `CompleteView.ledgerSummary(for:)` branches on cardio-shaped
//     rows and renders them via `formatCardioSummary`.

import XCTest
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class CardioDisplayQa043Tests: XCTestCase {

    // MARK: - Active view cardio branch

    func testActiveViewRendersDurationForContinuousItem() {
        // 45-min Z2 run. Continuous driver populates:
        //   repsDisplay = "45 min"  — primary target
        //   loadDisplay = "6:00 / km" — pace
        //   kind = .cardio
        // The view must NOT render "45 min reps"; the " reps" suffix
        // is strength-only. Instead "45 min" is the hero face and
        // "6:00 / km" is the secondary line verbatim.
        let ctx = makeContinuousContext(
            configJSON: #"""
            {"target_duration_sec":2700,"target_pace_sec_per_km":360}
            """#
        )
        let state = seed(context: ctx, route: .active)
        let content = ContinuousDriver().activeContent(
            state: state, context: ctx
        )
        let unwrapped = try? XCTUnwrap(content)
        XCTAssertEqual(unwrapped?.kind, .cardio)
        XCTAssertEqual(unwrapped?.repsDisplay, "45 min")
        XCTAssertEqual(unwrapped?.loadDisplay, "6:00 / km")

        // Hero face: cardio renders the primary target alone (no "
        // reps"). The view's formatting helpers are exercised by
        // `ActiveView.formattedMetaLine` elsewhere; here we just pin
        // the driver's contract that the view branches on.
        XCTAssertFalse(
            (unwrapped?.repsDisplay ?? "").contains(" reps"),
            "cardio repsDisplay must not embed the strength ' reps' suffix"
        )
    }

    func testActiveViewRendersDistanceForIntervalsItem() {
        // 10 × 400 m. Intervals driver populates:
        //   repsDisplay = "400 m" — work distance
        //   loadDisplay = "4:30 / km" — pace
        //   kind = .cardio
        let ctx = makeIntervalsContext(
            configJSON: #"""
            {"work_distance_m":400,"rest_distance_m":200,"interval_count":10,"target_pace_sec_per_km":270}
            """#
        )
        let state = seed(context: ctx, route: .active)
        let content = IntervalsDriver().activeContent(
            state: state, context: ctx
        )
        XCTAssertEqual(content?.kind, .cardio)
        XCTAssertEqual(content?.repsDisplay, "400 m")
        XCTAssertEqual(content?.loadDisplay, "4:30 / km")
    }

    // MARK: - Complete ledger cardio branch

    func testCompleteLedgerRendersCardioSummaryForContinuousLog() {
        // One continuous effort: 45 min over an unknown distance. The
        // ledger must NOT fall through to "1×0 @ BW" — the cardio
        // branch kicks in as soon as any done row carries
        // durationSec / distanceM.
        let itemID = UUID()
        let exerciseID = UUID()
        let context = makeCompleteContext(
            itemID: itemID,
            exerciseID: exerciseID,
            exerciseName: "Run",
            timingMode: .continuous
        )
        let log = SessionState.ItemLog(
            itemID: itemID,
            sets: [
                SetPlan(
                    setIndex: 1,
                    loadKg: nil,
                    unit: .lb,
                    reps: 0,
                    done: true,
                    adjust: nil,
                    durationSec: 2700,
                    distanceM: nil
                )
            ]
        )

        let entries = CompleteView.ledgerEntries(
            context: context, items: [log]
        )
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.name, "Run")
        let summary = entries.first?.summary ?? ""
        XCTAssertFalse(
            summary.contains("@ BW"),
            "cardio ledger must not render as '1×0 @ BW' (got: \(summary))"
        )
        XCTAssertEqual(summary, "45:00")
    }

    func testCompleteLedgerRendersCardioSummaryForIntervalsLog() {
        // Six 400 m intervals, each logged with duration + distance.
        let itemID = UUID()
        let exerciseID = UUID()
        let context = makeCompleteContext(
            itemID: itemID,
            exerciseID: exerciseID,
            exerciseName: "Run",
            timingMode: .intervals
        )
        let sets: [SetPlan] = (1...6).map { idx in
            SetPlan(
                setIndex: idx,
                loadKg: nil,
                unit: .lb,
                reps: 0,
                done: true,
                adjust: nil,
                durationSec: 96.0,
                distanceM: 400.0
            )
        }
        let log = SessionState.ItemLog(itemID: itemID, sets: sets)

        let entries = CompleteView.ledgerEntries(
            context: context, items: [log]
        )
        XCTAssertEqual(entries.count, 1)
        let summary = entries.first?.summary ?? ""
        // Uniform intervals → "6 × 400 m at <pace>". Exact pace
        // depends on formatCardioPace; we pin the prefix + suffix
        // shape rather than the arithmetic.
        XCTAssertTrue(
            summary.hasPrefix("6 × 400 m"),
            "expected '6 × 400 m ...' prefix, got: \(summary)"
        )
        XCTAssertFalse(summary.contains("@ BW"))
        XCTAssertFalse(summary.contains("×0"))
    }

    // MARK: - Fixture helpers

    private func makeContinuousContext(
        configJSON: String
    ) -> WorkoutContext {
        makeCardioContext(
            timingMode: .continuous,
            timingConfigJSON: configJSON
        )
    }

    private func makeIntervalsContext(
        configJSON: String
    ) -> WorkoutContext {
        makeCardioContext(
            timingMode: .intervals,
            timingConfigJSON: configJSON
        )
    }

    private func makeCardioContext(
        timingMode: TimingMode,
        timingConfigJSON: String
    ) -> WorkoutContext {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "qa-043",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: timingMode,
            timingConfigJSON: timingConfigJSON,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID, prescriptionJSON: "{}"
        )
        return WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Run")]
        )
    }

    private func seed(
        context: WorkoutContext,
        route: SessionState.Route
    ) -> SessionState {
        var state = SessionSeeder.seed(context: context)
        state.route = route
        return state
    }

    private func makeCompleteContext(
        itemID: UUID,
        exerciseID: UUID,
        exerciseName: String,
        timingMode: TimingMode
    ) -> WorkoutContext {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let now = Date()
        let workout = Workout(
            id: workoutID, userID: userID, name: "qa-043 complete",
            scheduledDate: now, status: .completed, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: now, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: timingMode,
            timingConfigJSON: "{}", rounds: nil,
            roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID, prescriptionJSON: "{}"
        )
        return WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: exerciseName)]
        )
    }
}
