// SessionDetailBodyweightTests.swift
//
// Covers the History bodyweight lookup — `SessionDetail.bodyweightKg`
// is populated from the local `user_parameters` cache by finding the
// most recent `bodyweight_kg` row whose `updatedAt` falls inside the
// workout's wall-clock window. The prior behavior (hardcoded nil)
// suppressed the "82 KG BW" chip even when `saveAndDone` had captured
// the value through the push path.

import XCTest
import CoreDomain
import WorkoutCoreFoundation
@testable import FeaturesHistory

@MainActor
final class SessionDetailBodyweightTests: XCTestCase {

    private var utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    /// A bodyweight captured at `completedAt - 1hr` (during the workout)
    /// binds to the session — `SessionDetail.bodyweightKg` is populated
    /// and the detail VM renders "82.1 KG BW".
    func testSessionDetailLoadsBodyweightFromUserParametersInWorkoutWindow() async throws {
        let userID = UUID()
        let completedAt = Date(timeIntervalSince1970: 1_776_297_600)
        let workoutStartedAt = completedAt.addingTimeInterval(-3600)
        let workout = Self.completedWorkout(
            userID: userID,
            completedAt: completedAt,
            scheduledDate: workoutStartedAt
        )
        // Bodyweight logged 30 minutes into the workout — inside the
        // start → completedAt window.
        let bodyweight = UserParameter(
            id: UUID(),
            userID: userID,
            key: "bodyweight_kg",
            value: "82.1",
            updatedAt: workoutStartedAt.addingTimeInterval(30 * 60),
            source: .appLog
        )
        let cache = FakeHistoryCache(
            workouts: [workout],
            userParametersByKey: ["bodyweight_kg": [bodyweight]]
        )
        let vm = HistoryViewModel(
            cache: cache, calendar: utcCalendar,
            now: { completedAt.addingTimeInterval(60) }
        )
        await vm.load()

        let detail = try XCTUnwrap(vm.detail(for: workout.id))
        XCTAssertEqual(detail.bodyweight, "82.1 KG BW")
    }

    /// No user_parameter exists for `bodyweight_kg` → the detail VM's
    /// `bodyweight` field is nil and the chip row renders without the
    /// BW label.
    func testSessionDetailHasNilBodyweightWhenNoneCaptured() async throws {
        let userID = UUID()
        let completedAt = Date(timeIntervalSince1970: 1_776_297_600)
        let workout = Self.completedWorkout(
            userID: userID,
            completedAt: completedAt,
            scheduledDate: completedAt.addingTimeInterval(-3600)
        )
        let cache = FakeHistoryCache(
            workouts: [workout],
            userParametersByKey: [:]
        )
        let vm = HistoryViewModel(
            cache: cache, calendar: utcCalendar,
            now: { completedAt.addingTimeInterval(60) }
        )
        await vm.load()

        let detail = try XCTUnwrap(vm.detail(for: workout.id))
        XCTAssertNil(detail.bodyweight)
    }

    /// A bodyweight outside the window — say yesterday's weigh-in — is
    /// ignored. The chip stays nil even though the cache holds a row.
    func testSessionDetailIgnoresBodyweightOutsideWindow() async throws {
        let userID = UUID()
        let completedAt = Date(timeIntervalSince1970: 1_776_297_600)
        let workout = Self.completedWorkout(
            userID: userID,
            completedAt: completedAt,
            scheduledDate: completedAt.addingTimeInterval(-3600)
        )
        // 24h before the workout started — outside the bound.
        let stale = UserParameter(
            id: UUID(),
            userID: userID,
            key: "bodyweight_kg",
            value: "79.9",
            updatedAt: completedAt.addingTimeInterval(-86_400),
            source: .appLog
        )
        let cache = FakeHistoryCache(
            workouts: [workout],
            userParametersByKey: ["bodyweight_kg": [stale]]
        )
        let vm = HistoryViewModel(
            cache: cache, calendar: utcCalendar,
            now: { completedAt.addingTimeInterval(60) }
        )
        await vm.load()

        let detail = try XCTUnwrap(vm.detail(for: workout.id))
        XCTAssertNil(detail.bodyweight)
    }

    /// A bodyweight captured 30s after `completedAt` still binds — the
    /// +2min grace window tolerates a late enqueue/save.
    func testSessionDetailAcceptsBodyweightJustAfterCompletedAt() async throws {
        let userID = UUID()
        let completedAt = Date(timeIntervalSince1970: 1_776_297_600)
        let workout = Self.completedWorkout(
            userID: userID,
            completedAt: completedAt,
            scheduledDate: completedAt.addingTimeInterval(-3600)
        )
        let bodyweight = UserParameter(
            id: UUID(),
            userID: userID,
            key: "bodyweight_kg",
            value: "82.5",
            updatedAt: completedAt.addingTimeInterval(30),
            source: .appLog
        )
        let cache = FakeHistoryCache(
            workouts: [workout],
            userParametersByKey: ["bodyweight_kg": [bodyweight]]
        )
        let vm = HistoryViewModel(
            cache: cache, calendar: utcCalendar,
            now: { completedAt.addingTimeInterval(120) }
        )
        await vm.load()

        let detail = try XCTUnwrap(vm.detail(for: workout.id))
        XCTAssertEqual(detail.bodyweight, "82.5 KG BW")
    }

    // MARK: - Fixtures

    private static func completedWorkout(
        userID: UUID,
        completedAt: Date,
        scheduledDate: Date
    ) -> Workout {
        Workout(
            id: UUID(),
            userID: userID,
            name: "Push A",
            scheduledDate: scheduledDate,
            status: .completed,
            source: .claude,
            notes: nil,
            createdAt: scheduledDate,
            updatedAt: completedAt,
            completedAt: completedAt,
            tagsJSON: nil
        )
    }
}
