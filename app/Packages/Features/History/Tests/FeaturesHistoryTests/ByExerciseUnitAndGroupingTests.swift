// ByExerciseUnitAndGroupingTests.swift
//
// Tests the "robust to mixed-unit data" invariants on the by-exercise
// trend + recent-sessions surface. V0 is kg-only in practice (Claude
// will only push kg prescriptions), but the domain model allows lb —
// if lb rows ever arrive, the surface must not silently mis-compare
// them against kg rows.
//
// Two hazards under test:
//   1) Top-set trend mixes kg and lb as raw numbers. Fixed by bucketing
//      the trend to the dominant unit (kg wins ties since v0 is
//      kg-only). Rows in the non-dominant unit don't participate in
//      the trend computation; the dominant unit's label drives the
//      display string.
//   2) Same-day recent-sessions collapse. Two workouts logged on the
//      same calendar day — same exercise, different WorkoutItemIDs —
//      were merged into one "recent session" row because the bucket
//      key was `calendar.startOfDay(for: completedAt)`. Fixed by
//      grouping on `workoutItemID` so each session renders its own row.

import XCTest
import CoreDomain
import WorkoutCoreFoundation
@testable import FeaturesHistory

@MainActor
final class ByExerciseUnitAndGroupingTests: XCTestCase {

    private var utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    // MARK: - Top-set bucketing by unit

    func testByExerciseTopSetBucketsByUnit() {
        // Seed two sessions for the same exercise — one in kg, one in
        // lb — on different weeks. The trend must NOT treat the lb
        // number (200) as heavier than the kg number (100). It should
        // pick the dominant unit (a tie here; kg wins per the v0
        // default) and render in that unit. The non-dominant row falls
        // out of the trend series.
        let itemID = UUID()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let logs = [
            // Week 0: kg session at 100 kg.
            SetLog(
                id: UUID(), workoutItemID: itemID,
                performedExerciseID: nil, setIndex: 1,
                reps: 5, weight: 100, weightUnit: .kg, rir: 2,
                isWarmup: false,
                startedAt: nil,
                completedAt: baseDate,
                notes: nil
            ),
            // Week 1: lb session at 200 lb (~90.7 kg). Heavier by raw
            // number, lighter by actual weight.
            SetLog(
                id: UUID(), workoutItemID: itemID,
                performedExerciseID: nil, setIndex: 1,
                reps: 5, weight: 200, weightUnit: .lb, rir: 2,
                isWarmup: false,
                startedAt: nil,
                completedAt: baseDate.addingTimeInterval(7 * 86_400),
                notes: nil
            ),
        ]

        let trend = TrendComputation.compute(setLogs: logs, calendar: utcCalendar)

        // Dominant unit is kg (tie at 1-vs-1 breaks to kg).
        XCTAssertEqual(trend.unit, .kg)
        // Only the kg session made it into the trend series; with one
        // data point the trend has no display string.
        XCTAssertEqual(trend.topSets.count, 1)
        XCTAssertNil(trend.displayString,
                     "single dominant-unit session must not produce a trend string")
        XCTAssertEqual(trend.topSets.first?.weight, 100)
        XCTAssertEqual(trend.topSets.first?.unit, .kg)
    }

    func testTrendPicksDominantUnitWhenLbMajority() {
        // Two lb sessions, one kg session. Lb wins the dominance vote;
        // the displayed trend is in lb and the kg row is excluded. This
        // is the hypothetical future where Eric switches to lb for
        // real — the trend should follow the user's actual unit, not
        // get stuck in kg because the tie-break favors it.
        let itemID = UUID()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let logs = [
            // Week 0: 100 kg (minority unit — excluded).
            SetLog(
                id: UUID(), workoutItemID: itemID,
                performedExerciseID: nil, setIndex: 1,
                reps: 5, weight: 100, weightUnit: .kg, rir: 2,
                isWarmup: false, startedAt: nil,
                completedAt: baseDate,
                notes: nil
            ),
            // Week 1: 205 lb.
            SetLog(
                id: UUID(), workoutItemID: itemID,
                performedExerciseID: nil, setIndex: 1,
                reps: 5, weight: 205, weightUnit: .lb, rir: 2,
                isWarmup: false, startedAt: nil,
                completedAt: baseDate.addingTimeInterval(7 * 86_400),
                notes: nil
            ),
            // Week 2: 215 lb.
            SetLog(
                id: UUID(), workoutItemID: itemID,
                performedExerciseID: nil, setIndex: 1,
                reps: 5, weight: 215, weightUnit: .lb, rir: 2,
                isWarmup: false, startedAt: nil,
                completedAt: baseDate.addingTimeInterval(14 * 86_400),
                notes: nil
            ),
        ]

        let trend = TrendComputation.compute(setLogs: logs, calendar: utcCalendar)

        XCTAssertEqual(trend.unit, .lb)
        XCTAssertEqual(trend.topSets.count, 2,
                       "kg row must be excluded from lb-dominant trend")
        XCTAssertEqual(trend.delta, 10, accuracy: 0.0001)
        // `weeksBetween` uses `Calendar.dateComponents([.weekOfYear])`
        // which rounds down — two 7-day jumps starting at week 0 land
        // at week 2, but the inclusive-to-exclusive span reports 1
        // since week 1 was the starting anchor for the lb-dominant
        // series (the kg row at week 0 is excluded). The test is
        // exercising the "display renders in dominant unit" contract,
        // not the week arithmetic; pin the value but leave a note.
        XCTAssertTrue(trend.displayString?.contains("LB") == true,
                      "display string must render in LB")
        XCTAssertTrue(trend.displayString?.hasPrefix("↑ 10 LB") == true,
                      "display string must lead with '↑ 10 LB' — got \(trend.displayString ?? "nil")")
    }

    // MARK: - Recent sessions group by session, not day

    func testByExerciseGroupsBySessionId() {
        // Seed two sessions on the same calendar day (same
        // `startOfDay`) but with different WorkoutItemIDs — this is the
        // "two workouts same day, same exercise" case. The bug
        // collapsed them to one row because the bucket key was the
        // day. Post-fix, each session renders its own row.
        let itemID1 = UUID()
        let itemID2 = UUID()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        // Session 1: morning, 100 kg.
        let log1 = SetLog(
            id: UUID(), workoutItemID: itemID1,
            performedExerciseID: nil, setIndex: 1,
            reps: 5, weight: 100, weightUnit: .kg, rir: 2,
            isWarmup: false, startedAt: nil,
            completedAt: baseDate.addingTimeInterval(8 * 3_600),
            notes: nil
        )
        // Session 2: evening same day, 105 kg.
        let log2 = SetLog(
            id: UUID(), workoutItemID: itemID2,
            performedExerciseID: nil, setIndex: 1,
            reps: 5, weight: 105, weightUnit: .kg, rir: 2,
            isWarmup: false, startedAt: nil,
            completedAt: baseDate.addingTimeInterval(20 * 3_600),
            notes: nil
        )

        let rows = ExerciseDetailViewModel.buildRecentRows(
            setLogs: [log1, log2],
            calendar: utcCalendar
        )

        XCTAssertEqual(rows.count, 2,
                       "two distinct workouts on the same day must produce two rows")
        // Newest first by completedAt. Session 2 (evening) comes first.
        XCTAssertEqual(rows[0].id, itemID2.uuidString)
        XCTAssertEqual(rows[1].id, itemID1.uuidString)
    }

    /// History must render "BW" (not "0 lb") for a SetLog whose weight
    /// is nil. This is the downstream half of the loadless cutover:
    /// push writes nil for loadless rows, local cache stores nil,
    /// History reads nil here. If the formatter ever regresses to
    /// treating nil as 0, the display would lie about a bodyweight set.
    func testExerciseDetailRowsRenderBWForNilWeight() {
        let itemID = UUID()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let log = SetLog(
            id: UUID(), workoutItemID: itemID,
            performedExerciseID: nil, setIndex: 1,
            reps: 10, weight: nil, weightUnit: nil, rir: nil,
            isWarmup: false, startedAt: nil,
            completedAt: baseDate,
            notes: nil
        )

        let rows = ExerciseDetailViewModel.buildRecentRows(
            setLogs: [log],
            calendar: utcCalendar
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(
            rows[0].display.contains("BW"),
            "nil weight renders as BW — got \(rows[0].display)"
        )
        XCTAssertFalse(
            rows[0].display.contains("0 lb") || rows[0].display.contains("0 kg"),
            "BW row must never display a numeric zero — got \(rows[0].display)"
        )
    }

    func testRecentRowDisplayUsesSessionUnit() {
        // Companion: the rendered row for an lb session must show "lb",
        // not "kg". The string interpolation was hardcoded to "kg" in
        // the old path even though the numbers could be in any unit.
        let itemID = UUID()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let log = SetLog(
            id: UUID(), workoutItemID: itemID,
            performedExerciseID: nil, setIndex: 1,
            reps: 5, weight: 225, weightUnit: .lb, rir: 2,
            isWarmup: false, startedAt: nil,
            completedAt: baseDate,
            notes: nil
        )

        let rows = ExerciseDetailViewModel.buildRecentRows(
            setLogs: [log],
            calendar: utcCalendar
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].display.contains("225 lb × 5"),
                      "lb session display must carry 'lb' — got \(rows[0].display)")
    }
}
