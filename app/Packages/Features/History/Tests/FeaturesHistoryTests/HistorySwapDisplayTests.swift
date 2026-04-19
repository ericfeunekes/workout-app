// HistorySwapDisplayTests.swift
//
// qa-021 — exercise-swap.md S11 + history.md S8 / S20: the History
// surfaces must render swapped exercises under their PERFORMED
// identity, not the planned one. Covered here:
//
//  • By-exercise picker lists any exercise with ANY set_log pointing
//    at it (via `performedExerciseID` or the planned item's
//    `exerciseID`), even when the performed exercise is not in the
//    current program. Drives `HistoryViewModel.pickerRows`.
//  • Session detail groups a swapped set under the performed
//    exercise, not the planned one. Drives
//    `SessionDetailViewModel.buildCards`.

import XCTest
import CoreDomain
import WorkoutCoreFoundation
@testable import FeaturesHistory

@MainActor
final class HistorySwapDisplayTests: XCTestCase {

    private var utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    // Fixed "now" — Wednesday 2026-04-15 UTC, matches
    // `HistoryViewModelTests` for familiarity.
    private let now = Date(timeIntervalSince1970: 1_776_297_600)

    // MARK: - Picker surfaces the swapped (alternative) exercise

    func testByExercisePickerIncludesAlternativesUsedInCompletedSessions() {
        // One completed session. The item planned Bench Press; the
        // user swapped mid-workout to Dumbbell Bench Press and logged
        // one set under `performedExerciseID`. The picker must surface
        // the performed exercise — it has a set_log pointing at its
        // exerciseID via `performedExerciseID`.
        let ids = PickerFixtureIDs()
        let cache = makePickerCache(ids: ids)
        let vm = HistoryViewModel(
            cache: cache,
            calendar: utcCalendar,
            now: { [now] in now }
        )

        let expectation = expectation(description: "load")
        Task { await vm.load(); expectation.fulfill() }
        wait(for: [expectation], timeout: 2)

        let performedRow = vm.pickerRows.first { $0.id == ids.performedID }
        XCTAssertNotNil(
            performedRow,
            "Picker must surface the swap target — it has a set_log pointing at its exerciseID via performedExerciseID"
        )
        XCTAssertEqual(performedRow?.name, "Dumbbell Bench Press")
        XCTAssertEqual(performedRow?.sessionSummary, "1 SESSION")
        // Dumbbell variant was logged in lb at 70 lb.
        XCTAssertEqual(performedRow?.topLoadSummary, "TOP 70 LB")
    }

    // MARK: - Session detail groups by performed exercise on swap

    func testSessionDetailGroupsByPerformedExerciseWhenSwap() {
        // Two items in one block. Item A (Bench Press) was swapped
        // mid-workout to Dumbbell Bench Press — the user logged one
        // set BEFORE the swap (planned) and two sets AFTER (performed).
        // Item B (Overhead Press) had no swap. Detail must produce
        // THREE cards: Bench (1 set), Dumbbell Bench (2 sets), OHP
        // (3 sets). Grouping by performed-first is the S8 contract.
        let ids = DetailFixtureIDs()
        let session = makeDetailSession(ids: ids)

        let detail = SessionDetailViewModel(
            session: session,
            exerciseName: [
                ids.plannedBenchID: "Bench Press",
                ids.performedBenchID: "Dumbbell Bench Press",
                ids.ohpID: "Overhead Press",
            ],
            calendar: utcCalendar
        )

        XCTAssertEqual(
            detail.cards.count, 3,
            "Swapped sets must split into their own card, not merge with the planned exercise"
        )
        // Order follows the order of first appearance in the log
        // stream (see SessionDetailViewModel.buildCards).
        XCTAssertEqual(detail.cards[0].name, "Bench Press")
        XCTAssertEqual(detail.cards[0].setRows.count, 1)
        XCTAssertEqual(detail.cards[1].name, "Dumbbell Bench Press")
        XCTAssertEqual(detail.cards[1].setRows.count, 2)
        XCTAssertEqual(detail.cards[2].name, "Overhead Press")
        XCTAssertEqual(detail.cards[2].setRows.count, 3)
        // None of the cards may fall back to "(unknown exercise)" —
        // the `exerciseName` lookup MUST include every id referenced
        // by a set_log, including swap targets.
        XCTAssertFalse(
            detail.cards.contains { $0.name == "(unknown exercise)" },
            "Every performed exerciseID must resolve via exerciseName — the catalog feed must include alternatives"
        )
    }

    // MARK: - Picker fixture

    private struct PickerFixtureIDs {
        let userID = UUID()
        let plannedID = UUID()   // Bench Press
        let performedID = UUID() // Dumbbell Bench Press
        let workoutID = UUID()
        let blockID = UUID()
        let itemID = UUID()
    }

    private func makePickerCache(ids: PickerFixtureIDs) -> FakeHistoryCache {
        let workout = Workout(
            id: ids.workoutID, userID: ids.userID, name: "Push A",
            scheduledDate: now, status: .completed, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: now,
            tagsJSON: makeTagsJSON(["push_day"])
        )
        let block = Block(
            id: ids.blockID, workoutID: ids.workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: "{}", rounds: nil,
            roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: ids.itemID, blockID: ids.blockID, position: 0,
            exerciseID: ids.plannedID,
            prescriptionJSON: #"{"sets":3,"reps":5,"load_kg":100}"#
        )
        // Only the performed set — the user swapped before logging.
        let log = SetLog(
            id: UUID(), workoutItemID: ids.itemID,
            performedExerciseID: ids.performedID, setIndex: 1,
            reps: 10, weight: 70, weightUnit: .lb, rir: 2,
            isWarmup: false, startedAt: nil,
            completedAt: now, notes: nil
        )
        return FakeHistoryCache(
            workouts: [workout],
            blocksByWorkout: [ids.workoutID: [block]],
            itemsByBlock: [ids.blockID: [item]],
            exercises: [
                Exercise(id: ids.plannedID, name: "Bench Press"),
                Exercise(id: ids.performedID, name: "Dumbbell Bench Press"),
            ],
            setLogsByWorkout: [ids.workoutID: [log]]
        )
    }

    // MARK: - Session-detail fixture

    private struct DetailFixtureIDs {
        let plannedBenchID = UUID()
        let performedBenchID = UUID()
        let ohpID = UUID()
        let itemABenchID = UUID()
        let itemBOhpID = UUID()
    }

    private func makeDetailSession(ids: DetailFixtureIDs) -> SessionDetail {
        // Pre-swap set: no performedExerciseID, falls through to
        // plannedExerciseByItem lookup and groups under Bench Press.
        let preSwap = SetLog(
            id: UUID(), workoutItemID: ids.itemABenchID,
            performedExerciseID: nil, setIndex: 1,
            reps: 5, weight: 100, weightUnit: .kg, rir: 2,
            isWarmup: false, startedAt: nil,
            completedAt: now, notes: nil
        )
        let postSwapLogs = (2...3).map { idx in
            SetLog(
                id: UUID(), workoutItemID: ids.itemABenchID,
                performedExerciseID: ids.performedBenchID, setIndex: idx,
                reps: 10, weight: 70, weightUnit: .lb, rir: 2,
                isWarmup: false, startedAt: nil,
                completedAt: now.addingTimeInterval(TimeInterval(60 * (idx - 1))),
                notes: nil
            )
        }
        let ohpLogs = (1...3).map { idx in
            SetLog(
                id: UUID(), workoutItemID: ids.itemBOhpID,
                performedExerciseID: nil, setIndex: idx,
                reps: 8, weight: 52.5, weightUnit: .kg, rir: 2,
                isWarmup: false, startedAt: nil,
                completedAt: now.addingTimeInterval(TimeInterval(600 + 60 * idx)),
                notes: nil
            )
        }
        return SessionDetail(
            workout: Workout(
                id: UUID(), userID: UUID(), name: "Push A",
                scheduledDate: now, status: .completed, source: .claude,
                notes: nil, createdAt: now, updatedAt: now,
                completedAt: now, tagsJSON: nil
            ),
            setLogs: [preSwap] + postSwapLogs + ohpLogs,
            plannedExerciseByItem: [
                ids.itemABenchID: ids.plannedBenchID,
                ids.itemBOhpID: ids.ohpID,
            ]
        )
    }

    // MARK: - Helpers

    private func makeTagsJSON(_ tags: [String]) -> String? {
        let data = (try? JSONEncoder().encode(tags)) ?? Data()
        return String(data: data, encoding: .utf8)
    }
}
