// TrendComputationTests.swift
//
// Exercises the pure TrendComputation helpers with a 12-week bench
// press progression. Calendar is pinned to UTC so day bucketing is
// deterministic across the machine running the test.

import XCTest
import CoreDomain
import WorkoutCoreFoundation
@testable import FeaturesHistory

final class TrendComputationTests: XCTestCase {

    private var utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    func testBenchProgressionOverTwelveWeeks() {
        // Bench progression: 80kg → 105kg across 12 weeks, one session
        // per week, 4 sets per session. Progression is exactly 2kg/week
        // so the delta is the integer 24 kg (to satisfy the formatter's
        // "integer-valued loads drop the decimal" rule).
        // Each weekly session is its own WorkoutItem — matching real
        // data, where every scheduled workout owns a distinct item for
        // the same exercise.
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var logs: [SetLog] = []
        for week in 0..<13 {
            let itemID = UUID()
            let day = baseDate.addingTimeInterval(TimeInterval(week * 7 * 86_400))
            let topWeight = 80.0 + Double(week) * 2.0
            for set in 0..<4 {
                let when = day.addingTimeInterval(TimeInterval(set * 180))
                logs.append(SetLog(
                    id: UUID(), workoutItemID: itemID,
                    performedExerciseID: nil, setIndex: set,
                    reps: 5,
                    weight: topWeight,
                    weightUnit: .kg, rir: 2,
                    isWarmup: false,
                    startedAt: when.addingTimeInterval(-60),
                    completedAt: when,
                    notes: nil
                ))
            }
        }

        let trend = TrendComputation.compute(setLogs: logs, calendar: utcCalendar)

        XCTAssertEqual(trend.topSets.count, 13)
        XCTAssertEqual(trend.weeks, 12)
        XCTAssertEqual(trend.delta, 24, accuracy: 0.0001)
        XCTAssertEqual(trend.unit, .kg)
        XCTAssertEqual(trend.displayString, "↑ 24 KG / 12 WK")
    }

    func testDecimalDeltaKeepsDecimalInDisplay() {
        // 0.5kg progression across 4 weeks — delta is 1.5, rendered
        // with one decimal. Each weekly session is a distinct
        // WorkoutItem.
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var logs: [SetLog] = []
        for week in 0..<4 {
            let day = baseDate.addingTimeInterval(TimeInterval(week * 7 * 86_400))
            logs.append(SetLog(
                id: UUID(), workoutItemID: UUID(),
                performedExerciseID: nil, setIndex: 0,
                reps: 5,
                weight: 100.0 + Double(week) * 0.5,
                weightUnit: .kg, rir: 2,
                isWarmup: false, startedAt: nil,
                completedAt: day,
                notes: nil
            ))
        }
        let trend = TrendComputation.compute(setLogs: logs, calendar: utcCalendar)
        XCTAssertEqual(trend.weeks, 3)
        XCTAssertEqual(trend.displayString, "↑ 1.5 KG / 3 WK")
    }

    func testFlatTrendShowsArrow() {
        // 4 flat sessions across 3 weeks, each its own WorkoutItem.
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let logs = (0..<4).map { week in
            SetLog(
                id: UUID(), workoutItemID: UUID(),
                performedExerciseID: nil, setIndex: 0,
                reps: 5, weight: 100, weightUnit: .kg, rir: 2,
                isWarmup: false,
                startedAt: nil,
                completedAt: baseDate.addingTimeInterval(TimeInterval(week * 7 * 86_400)),
                notes: nil
            )
        }
        let trend = TrendComputation.compute(setLogs: logs, calendar: utcCalendar)
        XCTAssertEqual(trend.delta, 0)
        XCTAssertEqual(trend.weeks, 3)
        XCTAssertEqual(trend.displayString, "→ 0 KG / 3 WK")
    }

    func testDownwardTrend() {
        // Deload pattern across 4 weekly sessions, each its own WorkoutItem.
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let weights: [Double] = [100, 95, 92.5, 90]
        let logs = weights.enumerated().map { (offset, weight) in
            SetLog(
                id: UUID(), workoutItemID: UUID(),
                performedExerciseID: nil, setIndex: 0,
                reps: 5, weight: weight, weightUnit: .kg, rir: 2,
                isWarmup: false,
                startedAt: nil,
                completedAt: baseDate.addingTimeInterval(TimeInterval(offset * 7 * 86_400)),
                notes: nil
            )
        }
        let trend = TrendComputation.compute(setLogs: logs, calendar: utcCalendar)
        XCTAssertEqual(trend.delta, -10)
        XCTAssertEqual(trend.displayString, "↓ 10 KG / 3 WK")
    }

    func testSingleSessionProducesNoDisplayString() {
        let itemID = UUID()
        let log = SetLog(
            id: UUID(), workoutItemID: itemID,
            performedExerciseID: nil, setIndex: 0,
            reps: 5, weight: 100, weightUnit: .kg, rir: 2,
            isWarmup: false, startedAt: nil,
            completedAt: Date(),
            notes: nil
        )
        let trend = TrendComputation.compute(setLogs: [log], calendar: utcCalendar)
        XCTAssertNil(trend.displayString)
        XCTAssertEqual(trend.topSets.count, 1)
        XCTAssertEqual(trend.weeks, 0)
    }

    /// qa-006 regression: two completed sessions on the same calendar
    /// day (e.g. Burpee in a circuit block and Burpee in a later AMRAP
    /// block during scenario 01's simulator run) must render the trend
    /// line, not "— not enough history yet". Same-day → weeks == 0,
    /// which formats as "→ 0 KG / 0 WK" for a flat delta per
    /// history.md S7's flat-delta semantics.
    func testTrendWithTwoSessionsSameDayRendersFlatDelta() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let circuitItemID = UUID()
        let amrapItemID = UUID()
        let logs = [
            SetLog(
                id: UUID(), workoutItemID: circuitItemID,
                performedExerciseID: nil, setIndex: 0,
                reps: 10, weight: 0, weightUnit: .kg, rir: 2,
                isWarmup: false, startedAt: nil,
                completedAt: baseDate,
                notes: nil
            ),
            SetLog(
                id: UUID(), workoutItemID: amrapItemID,
                performedExerciseID: nil, setIndex: 0,
                reps: 10, weight: 0, weightUnit: .kg, rir: 2,
                isWarmup: false, startedAt: nil,
                completedAt: baseDate.addingTimeInterval(3_600),
                notes: nil
            ),
        ]
        let trend = TrendComputation.compute(setLogs: logs, calendar: utcCalendar)
        XCTAssertEqual(trend.topSets.count, 2, "two distinct sessions must not collapse")
        XCTAssertEqual(trend.weeks, 0)
        XCTAssertEqual(trend.delta, 0)
        XCTAssertNotNil(trend.displayString, "flat same-day delta must still render")
        XCTAssertEqual(trend.displayString, "→ 0 KG / 0 WK")
    }

    /// Companion to the same-day case: two sessions in different weeks
    /// still compute the delta + week span correctly.
    func testTrendWithTwoSessionsDifferentDaysRendersCorrectDelta() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let logs = [
            SetLog(
                id: UUID(), workoutItemID: UUID(),
                performedExerciseID: nil, setIndex: 0,
                reps: 5, weight: 100, weightUnit: .kg, rir: 2,
                isWarmup: false, startedAt: nil,
                completedAt: baseDate,
                notes: nil
            ),
            SetLog(
                id: UUID(), workoutItemID: UUID(),
                performedExerciseID: nil, setIndex: 0,
                reps: 5, weight: 105, weightUnit: .kg, rir: 2,
                isWarmup: false, startedAt: nil,
                completedAt: baseDate.addingTimeInterval(TimeInterval(2 * 7 * 86_400)),
                notes: nil
            ),
        ]
        let trend = TrendComputation.compute(setLogs: logs, calendar: utcCalendar)
        XCTAssertEqual(trend.topSets.count, 2)
        XCTAssertEqual(trend.weeks, 2)
        XCTAssertEqual(trend.delta, 5, accuracy: 0.0001)
        XCTAssertEqual(trend.displayString, "↑ 5 KG / 2 WK")
    }

    func testTopSetPrefersHigherRepsOnTie() {
        let itemID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let logs = [
            SetLog(
                id: UUID(), workoutItemID: itemID,
                performedExerciseID: nil, setIndex: 0,
                reps: 5, weight: 100, weightUnit: .kg, rir: 2,
                isWarmup: false, startedAt: nil,
                completedAt: now.addingTimeInterval(10),
                notes: nil
            ),
            SetLog(
                id: UUID(), workoutItemID: itemID,
                performedExerciseID: nil, setIndex: 1,
                reps: 7, weight: 100, weightUnit: .kg, rir: 1,
                isWarmup: false, startedAt: nil,
                completedAt: now.addingTimeInterval(200),
                notes: nil
            ),
        ]
        let top = TrendComputation.topSetsBySession(setLogs: logs, unit: .kg, calendar: utcCalendar)
        XCTAssertEqual(top.count, 1)
        XCTAssertEqual(top[0].reps, 7)
        XCTAssertEqual(top[0].weight, 100)
        XCTAssertEqual(top[0].unit, .kg)
    }
}
