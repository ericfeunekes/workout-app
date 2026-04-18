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
        let itemID = UUID()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var logs: [SetLog] = []
        for week in 0..<13 {
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
        XCTAssertEqual(trend.deltaKg, 24, accuracy: 0.0001)
        XCTAssertEqual(trend.displayString, "↑ 24 KG / 12 WK")
    }

    func testDecimalDeltaKeepsDecimalInDisplay() {
        // 0.5kg progression across 4 weeks — delta is 1.5, rendered
        // with one decimal.
        let itemID = UUID()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var logs: [SetLog] = []
        for week in 0..<4 {
            let day = baseDate.addingTimeInterval(TimeInterval(week * 7 * 86_400))
            logs.append(SetLog(
                id: UUID(), workoutItemID: itemID,
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
        let itemID = UUID()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let logs = (0..<4).map { week in
            SetLog(
                id: UUID(), workoutItemID: itemID,
                performedExerciseID: nil, setIndex: 0,
                reps: 5, weight: 100, weightUnit: .kg, rir: 2,
                isWarmup: false,
                startedAt: nil,
                completedAt: baseDate.addingTimeInterval(TimeInterval(week * 7 * 86_400)),
                notes: nil
            )
        }
        let trend = TrendComputation.compute(setLogs: logs, calendar: utcCalendar)
        XCTAssertEqual(trend.deltaKg, 0)
        XCTAssertEqual(trend.weeks, 3)
        XCTAssertEqual(trend.displayString, "→ 0 KG / 3 WK")
    }

    func testDownwardTrend() {
        let itemID = UUID()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let weights: [Double] = [100, 95, 92.5, 90]
        let logs = weights.enumerated().map { (offset, weight) in
            SetLog(
                id: UUID(), workoutItemID: itemID,
                performedExerciseID: nil, setIndex: 0,
                reps: 5, weight: weight, weightUnit: .kg, rir: 2,
                isWarmup: false,
                startedAt: nil,
                completedAt: baseDate.addingTimeInterval(TimeInterval(offset * 7 * 86_400)),
                notes: nil
            )
        }
        let trend = TrendComputation.compute(setLogs: logs, calendar: utcCalendar)
        XCTAssertEqual(trend.deltaKg, -10)
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
        let top = TrendComputation.topSetsByDay(setLogs: logs, calendar: utcCalendar)
        XCTAssertEqual(top.count, 1)
        XCTAssertEqual(top[0].reps, 7)
        XCTAssertEqual(top[0].weightKg, 100)
    }
}
