// SessionDetailViewModelFormatTests.swift
//
// Regression coverage for the History session-detail row renderer.
//
// Bug being fixed (codex review on R1.6): `formatSetRow` used to call
// `formatLoad(kg: log.weight)` regardless of `log.weightUnit`, so a set
// logged as "225 lb" rendered as "225 kg" in the detail row. The user
// would then tap the row, land in EditSetSheet which correctly reads
// "LOAD LB", and see a visible contradiction between the list and the
// editor. This test pins the row renderer to the SetLog's actual unit.
//
// Complements `EditSetSheetModelTests.testEditSheetLabelMatchesWeightUnit`
// which covers the editor side; together they lock down the unit-label
// invariant end-to-end for the History surface.

import XCTest
import CoreDomain
import WorkoutCoreFoundation
@testable import FeaturesHistory

@MainActor
final class SessionDetailViewModelFormatTests: XCTestCase {

    private var utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    func testSessionDetailRowRendersLbSuffix() {
        // A SetLog seeded with `weightUnit: .lb, weight: 225` must render
        // "225 lb", not "225 kg". Before R1.6 + this fix, the row would
        // show "225 kg" — the bug this test guards against.
        let itemID = WorkoutItemID()
        let completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let log = SetLog(
            id: SetLogID(),
            workoutItemID: itemID,
            setIndex: 1,
            reps: 5,
            weight: 225,
            weightUnit: .lb,
            rir: 2,
            completedAt: completedAt
        )
        let row = SessionDetailViewModel.formatSetRow(log)
        XCTAssertTrue(
            row.contains("225 lb"),
            "lb-logged set should render with lb suffix; got: \(row)"
        )
        XCTAssertFalse(
            row.contains("kg"),
            "lb-logged set must not leak kg suffix; got: \(row)"
        )
    }

    func testSessionDetailRowRendersKgSuffix() {
        // Kg-path regression: the legacy behavior (rendering "kg") must
        // still hold for rows actually logged in kg. Pins the other leg
        // of the switch.
        let itemID = WorkoutItemID()
        let completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let log = SetLog(
            id: SetLogID(),
            workoutItemID: itemID,
            setIndex: 1,
            reps: 5,
            weight: 100,
            weightUnit: .kg,
            rir: 2,
            completedAt: completedAt
        )
        let row = SessionDetailViewModel.formatSetRow(log)
        XCTAssertTrue(
            row.contains("100 kg"),
            "kg-logged set should render with kg suffix; got: \(row)"
        )
    }

    func testSessionDetailRowDefaultsToKgWhenUnitMissing() {
        // Older rows (pre-`weight_unit` field) stored `weightUnit == nil`.
        // The renderer must fall back to kg so those rows don't crash or
        // render without a unit. Matches the default in EditSetSheet's
        // `weightUnit` parameter (also `.kg`).
        let itemID = WorkoutItemID()
        let completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let log = SetLog(
            id: SetLogID(),
            workoutItemID: itemID,
            setIndex: 1,
            reps: 5,
            weight: 60,
            weightUnit: nil,
            rir: 3,
            completedAt: completedAt
        )
        let row = SessionDetailViewModel.formatSetRow(log)
        XCTAssertTrue(
            row.contains("60 kg"),
            "nil-unit row should fall back to kg; got: \(row)"
        )
    }

    func testSessionDetailRowRendersSkippedWithoutPhantomLoad() {
        let log = SetLog(
            id: SetLogID(),
            workoutItemID: WorkoutItemID(),
            setIndex: 2,
            reps: nil,
            weight: nil,
            weightUnit: nil,
            rir: nil,
            skipped: true,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let row = SessionDetailViewModel.formatSetRow(log)

        XCTAssertEqual(row, "2 · SKIPPED")
    }

    func testSessionDetailRowRendersCardioFields() {
        let log = SetLog(
            id: SetLogID(),
            workoutItemID: WorkoutItemID(),
            setIndex: 1,
            durationSec: 270,
            distanceM: 1000,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let row = SessionDetailViewModel.formatSetRow(log)

        XCTAssertEqual(row, "1 · 4:30 AT 4:30 / KM")
    }

    func testSessionDetailRowRendersExplicitSideWhenPresent() {
        let log = SetLog(
            id: SetLogID(),
            workoutItemID: WorkoutItemID(),
            setIndex: 1,
            reps: 10,
            weight: 20,
            weightUnit: .kg,
            side: .left,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let row = SessionDetailViewModel.formatSetRow(log)

        XCTAssertEqual(row, "1 · 20 kg × 10 · LEFT")
    }
}
