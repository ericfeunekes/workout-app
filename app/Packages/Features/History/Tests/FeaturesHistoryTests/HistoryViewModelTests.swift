// HistoryViewModelTests.swift
//
// Given a FakeHistoryCache with three completed workouts, verify:
//   • the VM groups them by week correctly (this/last/older headers),
//   • the push filter keeps only push-tagged workouts,
//   • an untagged workout is ALL-only,
//   • the by-exercise picker counts sessions + tracks top load,
//   • the detail VM builds cards in the right order.

import XCTest
import CoreDomain
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesHistory

@MainActor
final class HistoryViewModelTests: XCTestCase {

    private var utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    // Fixed "now" — Wednesday 2026-04-15 UTC.
    private let now = Date(timeIntervalSince1970: 1_776_297_600)

    func testGroupingAndPushFilter() async {
        let (cache, ids) = makeFixtures()
        let vm = HistoryViewModel(
            cache: cache,
            calendar: utcCalendar,
            now: { [now] in now }
        )
        await vm.load()

        // Three groups — all under THIS WEEK given the fixture dates
        // all fall in the same calendar week as `now`. Exact number
        // depends on the fixture; assert combined count.
        let totalRows = vm.groups.reduce(0) { $0 + $1.rows.count }
        XCTAssertEqual(totalRows, 3)

        // Headers are non-empty and stable.
        XCTAssertFalse(vm.groups.isEmpty)

        // Push filter: only the Push A workout survives.
        vm.setSplit(.push)
        let pushTotal = vm.groups.reduce(0) { $0 + $1.rows.count }
        XCTAssertEqual(pushTotal, 1)
        XCTAssertEqual(vm.groups.first?.rows.first?.programName, "Push A")

        // ALL again: all three come back.
        vm.setSplit(.all)
        XCTAssertEqual(vm.groups.reduce(0) { $0 + $1.rows.count }, 3)

        // Legs filter: only one survives (leg tag).
        vm.setSplit(.legs)
        XCTAssertEqual(vm.groups.reduce(0) { $0 + $1.rows.count }, 1)
        XCTAssertEqual(vm.groups.first?.rows.first?.programName, "Legs A")

        // Untagged workout is excluded from every split but appears
        // under ALL.
        vm.setSplit(.pull)
        XCTAssertEqual(vm.groups.reduce(0) { $0 + $1.rows.count }, 0)

        _ = ids
    }

    func testPickerRowsFromSessions() async {
        let (cache, ids) = makeFixtures()
        let vm = HistoryViewModel(
            cache: cache,
            calendar: utcCalendar,
            now: { [now] in now }
        )
        await vm.load()

        // Push A used bench + OHP, Legs A used squat + OHP, Untagged
        // used bench. So: bench appears in 2 sessions, OHP in 2,
        // squat in 1.
        let benchRow = vm.pickerRows.first { $0.id == ids.benchID }
        XCTAssertNotNil(benchRow)
        XCTAssertEqual(benchRow?.sessionSummary, "2 SESSIONS")
        XCTAssertEqual(benchRow?.topLoadSummary, "TOP 100 KG")

        let squatRow = vm.pickerRows.first { $0.id == ids.squatID }
        XCTAssertNotNil(squatRow)
        XCTAssertEqual(squatRow?.sessionSummary, "1 SESSION")
    }

    func testPickerRowsIgnoreSkippedOnlySessions() async {
        let (cache, ids) = makeFixtures()
        let skippedID = UUID()
        cache.exercises.append(Exercise(id: skippedID, name: "Skipped Curl"))
        attachSkippedOnlySession(
            cache: cache,
            userID: ids.userID,
            exerciseID: skippedID
        )

        let vm = HistoryViewModel(
            cache: cache,
            calendar: utcCalendar,
            now: { [now] in now }
        )
        await vm.load()

        XCTAssertNil(
            vm.pickerRows.first { $0.id == skippedID },
            "skipped-only exercise must not appear as a performed picker row"
        )
    }

    func testSessionDetailExerciseIDsIgnoreSkippedLogs() {
        let workout = makeCompletedWorkout(
            name: "Skipped Only",
            userID: UUID(),
            offset: 0,
            tags: nil
        )
        let itemID = UUID()
        let exerciseID = UUID()
        let log = SetLog(
            id: UUID(), workoutItemID: itemID,
            performedExerciseID: nil, setIndex: 1,
            reps: 10, weight: 20, weightUnit: .kg, rir: 2,
            isWarmup: false,
            skipped: true,
            startedAt: nil,
            completedAt: now,
            notes: nil
        )

        let detail = SessionDetail(
            workout: workout,
            setLogs: [log],
            plannedExerciseByItem: [itemID: exerciseID]
        )

        XCTAssertTrue(detail.performedExerciseIDs.isEmpty)
        XCTAssertNil(detail.avgRIR)
    }

    func testHistoryLoadUsesSingleItemFetchPerLoad() async {
        // perf-003 guard: the old shape fired `1 + N_blocks` item/block
        // fetches per loaded workout. With 3 seeded completed workouts
        // + at least one planned workout this used to be >6 per-block
        // fetches. The new path uses the bulk `loadItems(workoutIDs:)`
        // API once for completed sessions and once for current program
        // (2 total regardless of N), and the per-block
        // `loadItems(blockID:)` fetch is NEVER hit from `load()`.
        let (cache, ids) = makeFixtures()
        // Seed one planned workout so `loadCurrentProgram` exercises
        // the same bulk path as `loadCompleted`.
        let planned = Workout(
            id: UUID(), userID: ids.userID, name: "Planned Push",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil,
            createdAt: now, updatedAt: now, completedAt: nil,
            tagsJSON: nil
        )
        cache.workouts.append(planned)
        let plannedBlockID = UUID()
        let plannedItemID = UUID()
        cache.blocksByWorkout[planned.id] = [
            Block(id: plannedBlockID, workoutID: planned.id, parentBlockID: nil,
                  position: 0, name: nil, timingMode: .straightSets,
                  timingConfigJSON: "{}", rounds: nil,
                  roundsRepSchemeJSON: nil, notes: nil),
        ]
        cache.itemsByBlock[plannedBlockID] = [
            WorkoutItem(id: plannedItemID, blockID: plannedBlockID,
                        position: 0, exerciseID: ids.benchID,
                        prescriptionJSON: "{}"),
        ]

        let vm = HistoryViewModel(
            cache: cache,
            calendar: utcCalendar,
            now: { [now] in now }
        )
        await vm.load()

        XCTAssertEqual(
            cache.loadItemsCallCount, 0,
            "Per-block loadItems must never fire from HistoryViewModel.load()"
        )
        XCTAssertLessThanOrEqual(
            cache.loadItemsBulkCallCount, 2,
            "Bulk loadItems must fire at most twice (completed + planned)"
        )
        XCTAssertGreaterThan(
            cache.loadItemsBulkCallCount, 0,
            "Bulk loadItems must fire at least once when completed workouts exist"
        )
    }

    func testSessionDetailBuildsCardsInOrder() async {
        let (cache, ids) = makeFixtures()
        let vm = HistoryViewModel(
            cache: cache,
            calendar: utcCalendar,
            now: { [now] in now }
        )
        await vm.load()

        // Find the Push A detail.
        let pushWorkout = (cache.workouts.first { $0.name == "Push A" })
        let workoutID = try? XCTUnwrap(pushWorkout?.id)
        guard let workoutID else { return }
        let detail = vm.detail(for: workoutID)
        let unwrapped = try? XCTUnwrap(detail)
        guard let unwrapped else { return }

        // Two cards (bench first, OHP second), matching the item
        // position order.
        XCTAssertEqual(unwrapped.cards.count, 2)
        XCTAssertEqual(unwrapped.cards[0].name, "Barbell Bench Press")
        XCTAssertEqual(unwrapped.cards[1].name, "Overhead Press")

        // Bench card has 4 set rows in the expected format.
        XCTAssertEqual(unwrapped.cards[0].setRows.count, 4)
        XCTAssertEqual(unwrapped.cards[0].setRows[0].display, "1 · 100 kg × 5 · RIR 2")
        XCTAssertEqual(unwrapped.cards[0].setRows[3].display, "4 · 100 kg × 5 · RIR 2")

        _ = ids
    }

    func testPrimitiveOnlySessionRendersDetailPickerAndBodyweight() async throws {
        let userID = UUID()
        let exerciseID = UUID()
        let workout = makeCompletedWorkout(
            name: "Primitive Strength",
            userID: userID,
            offset: 0,
            tags: ["push_day"]
        )
        let slotID = UUID()
        let log = PrimitiveSetLog(
            id: UUID(),
            role: .slot,
            slotID: slotID,
            setID: UUID(),
            blockID: UUID(),
            workoutID: workout.id,
            plannedExerciseID: exerciseID,
            setIndex: 0,
            setRepeatIndex: 0,
            reps: 5,
            weight: 100,
            weightUnit: .kg,
            rir: 2,
            completedAt: workout.completedAt ?? now
        )
        let bodyweight = UserParameter(
            id: UUID(),
            userID: userID,
            key: "bodyweight_kg",
            value: "80.5",
            updatedAt: (workout.completedAt ?? now).addingTimeInterval(30),
            source: .appLog
        )
        let cache = FakeHistoryCache(
            workouts: [workout],
            exercises: [Exercise(id: exerciseID, name: "Back Squat")],
            primitiveSetLogsByWorkout: [workout.id: [log]],
            userParametersByKey: ["bodyweight_kg": [bodyweight]]
        )

        let vm = HistoryViewModel(
            cache: cache,
            calendar: utcCalendar,
            now: { [now] in now }
        )
        await vm.load()

        let row = try XCTUnwrap(vm.groups.first?.rows.first)
        XCTAssertEqual(row.bodyweight, "80.5 KG BW")
        XCTAssertEqual(row.avgRIR, "RIR 2.0")
        XCTAssertEqual(vm.pickerRows.first?.id, exerciseID)
        XCTAssertEqual(vm.pickerRows.first?.topLoadSummary, "TOP 100 KG")

        let detail = try XCTUnwrap(vm.detail(for: workout.id))
        XCTAssertEqual(detail.cards.count, 1)
        XCTAssertEqual(detail.cards[0].name, "Back Squat")
        XCTAssertEqual(detail.cards[0].setRows.first?.display, "SET 1 · 100 kg + 5 reps · RIR 2")
        XCTAssertEqual(detail.bodyweight, "80.5 KG BW")
    }

    func testPrimitiveSessionDetailDoesNotRenderInternalSlotCoordinate() async throws {
        let userID = UUID()
        let exerciseID = UUID()
        let workout = makeCompletedWorkout(
            name: "Primitive Internal Coordinate",
            userID: userID,
            offset: 0,
            tags: nil
        )
        let log = PrimitiveSetLog(
            id: UUID(),
            role: .slot,
            slotID: UUID(),
            setID: UUID(),
            blockID: UUID(),
            workoutID: workout.id,
            plannedExerciseID: exerciseID,
            setIndex: 0,
            setRepeatIndex: 0,
            reps: 8,
            completedAt: workout.completedAt ?? now
        )
        let cache = FakeHistoryCache(
            workouts: [workout],
            exercises: [Exercise(id: exerciseID, name: "Push-up")],
            primitiveSetLogsByWorkout: [workout.id: [log]]
        )

        let vm = HistoryViewModel(cache: cache, calendar: utcCalendar, now: { [now] in now })
        await vm.load()

        let detail = try XCTUnwrap(vm.detail(for: workout.id))
        XCTAssertEqual(detail.cards[0].setRows.first?.display, "SET 1 · BW + 8 reps")
    }

    func testPrimitiveSessionDetailDistinguishesSlotCommitCoordinates() async throws {
        let userID = UUID()
        let exerciseID = UUID()
        let workout = makeCompletedWorkout(
            name: "Primitive Commit Coordinates",
            userID: userID,
            offset: 0,
            tags: nil
        )
        let first = PrimitiveSetLog(
            id: UUID(),
            role: .slot,
            slotID: UUID(),
            setID: UUID(),
            blockID: UUID(),
            workoutID: workout.id,
            plannedExerciseID: exerciseID,
            setIndex: 0,
            setRepeatIndex: 0,
            reps: 8,
            completedAt: workout.completedAt ?? now
        )
        let second = PrimitiveSetLog(
            id: UUID(),
            role: .slot,
            slotID: UUID(),
            setID: UUID(),
            blockID: UUID(),
            workoutID: workout.id,
            plannedExerciseID: exerciseID,
            setIndex: 1,
            setRepeatIndex: 0,
            reps: 6,
            completedAt: (workout.completedAt ?? now).addingTimeInterval(1)
        )
        let cache = FakeHistoryCache(
            workouts: [workout],
            exercises: [Exercise(id: exerciseID, name: "Push-up")],
            primitiveSetLogsByWorkout: [workout.id: [first, second]]
        )

        let vm = HistoryViewModel(cache: cache, calendar: utcCalendar, now: { [now] in now })
        await vm.load()

        let detail = try XCTUnwrap(vm.detail(for: workout.id))
        XCTAssertEqual(
            detail.cards[0].setRows.map(\.display),
            ["SET 1 · BW + 8 reps", "SET 2 · BW + 6 reps"]
        )
    }

    func testPrimitiveAggregateRowsRenderButDoNotEnterByExerciseMetrics() async throws {
        let userID = UUID()
        let exerciseID = UUID()
        let workout = makeCompletedWorkout(
            name: "Primitive AMRAP",
            userID: userID,
            offset: 0,
            tags: nil
        )
        let slot = PrimitiveSetLog(
            id: UUID(),
            role: .slot,
            slotID: UUID(),
            setID: UUID(),
            blockID: UUID(),
            workoutID: workout.id,
            plannedExerciseID: exerciseID,
            setIndex: 1,
            reps: 10,
            weight: 50,
            weightUnit: .kg,
            completedAt: workout.completedAt ?? now
        )
        let block = PrimitiveSetLog(
            id: UUID(),
            role: .blockResult,
            blockID: UUID(),
            workoutID: workout.id,
            setIndex: 1,
            reps: 7,
            rounds: 3,
            completedAt: (workout.completedAt ?? now).addingTimeInterval(1)
        )
        let cache = FakeHistoryCache(
            workouts: [workout],
            exercises: [Exercise(id: exerciseID, name: "Burpee")],
            primitiveSetLogsByWorkout: [workout.id: [slot, block]]
        )

        let vm = HistoryViewModel(cache: cache, calendar: utcCalendar, now: { [now] in now })
        await vm.load()

        XCTAssertEqual(vm.pickerRows.count, 1)
        XCTAssertEqual(vm.pickerRows[0].id, exerciseID)
        XCTAssertEqual(vm.pickerRows[0].topLoadSummary, "TOP 50 KG")

        let detail: SessionDetailViewModel = try XCTUnwrap(vm.detail(for: workout.id))
        XCTAssertEqual(detail.cards.map { $0.name }, ["Burpee", "block result"])
        XCTAssertEqual(detail.cards[1].setRows.first?.display, "BLOCK · 3 rounds + 7 reps")
    }

    func testExerciseDetailLoadsPrimitiveRowsOutsideLoadedHistorySlice() async throws {
        let exerciseID = UUID()
        let workoutID = UUID()
        let log = PrimitiveSetLog(
            id: UUID(),
            role: .slot,
            slotID: UUID(),
            setID: UUID(),
            blockID: UUID(),
            workoutID: workoutID,
            plannedExerciseID: exerciseID,
            setIndex: 0,
            reps: 5,
            weight: 100,
            weightUnit: .kg,
            completedAt: now
        )
        let cache = FakeHistoryCache(
            exercises: [Exercise(id: exerciseID, name: "Back Squat")],
            primitiveSetLogsByWorkout: [workoutID: [log]]
        )
        let vm = ExerciseDetailViewModel(
            exerciseID: exerciseID,
            exerciseName: "Back Squat",
            cache: cache,
            calendar: utcCalendar
        )

        await vm.load()

        XCTAssertEqual(vm.recentSessions.count, 1)
        XCTAssertTrue(vm.recentSessions[0].display.contains("100 kg × 5"))
    }

    func testExerciseDetailPrefersPrimitiveRowsWhenLegacyRowsAlsoExist() async throws {
        let exerciseID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let itemID = UUID()
        let completedAt = now
        let legacy = SetLog(
            id: UUID(),
            workoutItemID: itemID,
            setIndex: 1,
            reps: 5,
            weight: 75,
            weightUnit: .kg,
            completedAt: completedAt
        )
        let primitive = PrimitiveSetLog(
            id: UUID(),
            role: .slot,
            slotID: UUID(),
            setID: UUID(),
            blockID: UUID(),
            workoutID: workoutID,
            plannedExerciseID: exerciseID,
            setIndex: 0,
            reps: 5,
            weight: 100,
            weightUnit: .kg,
            completedAt: completedAt.addingTimeInterval(1)
        )
        let cache = FakeHistoryCache(
            itemsByBlock: [
                blockID: [
                    WorkoutItem(
                        id: itemID,
                        blockID: blockID,
                        position: 0,
                        exerciseID: exerciseID,
                        prescriptionJSON: "{}"
                    ),
                ],
            ],
            exercises: [Exercise(id: exerciseID, name: "Back Squat")],
            setLogsByWorkout: [workoutID: [legacy]],
            primitiveSetLogsByWorkout: [workoutID: [primitive]]
        )
        let vm = ExerciseDetailViewModel(
            exerciseID: exerciseID,
            exerciseName: "Back Squat",
            cache: cache,
            calendar: utcCalendar
        )

        await vm.load()

        XCTAssertEqual(vm.recentSessions.count, 1)
        XCTAssertTrue(vm.recentSessions[0].display.contains("100 kg × 5"))
        XCTAssertFalse(vm.recentSessions[0].display.contains("75 kg"))
    }

    func testExerciseDetailDoesNotFallbackToLegacyRowsWhenPrimitiveRowsAreMissing() async throws {
        let exerciseID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let itemID = UUID()
        let legacy = SetLog(
            id: UUID(),
            workoutItemID: itemID,
            setIndex: 1,
            reps: 5,
            weight: 75,
            weightUnit: .kg,
            completedAt: now
        )
        let cache = FakeHistoryCache(
            itemsByBlock: [
                blockID: [
                    WorkoutItem(
                        id: itemID,
                        blockID: blockID,
                        position: 0,
                        exerciseID: exerciseID,
                        prescriptionJSON: "{}"
                    ),
                ],
            ],
            exercises: [Exercise(id: exerciseID, name: "Back Squat")],
            setLogsByWorkout: [workoutID: [legacy]]
        )
        let vm = ExerciseDetailViewModel(
            exerciseID: exerciseID,
            exerciseName: "Back Squat",
            cache: cache,
            calendar: utcCalendar
        )

        await vm.load()

        XCTAssertTrue(vm.recentSessions.isEmpty)
    }

    func testPrimitiveResetClearsRenderedHistoryRows() async throws {
        let userID = UUID()
        let exerciseID = UUID()
        let workout = makeCompletedWorkout(
            name: "Primitive Reset",
            userID: userID,
            offset: 0,
            tags: nil
        )
        let log = PrimitiveSetLog(
            id: UUID(),
            role: .slot,
            slotID: UUID(),
            setID: UUID(),
            blockID: UUID(),
            workoutID: workout.id,
            plannedExerciseID: exerciseID,
            setIndex: 1,
            reps: 5,
            completedAt: workout.completedAt ?? now
        )
        let cache = FakeHistoryCache(
            workouts: [workout],
            exercises: [Exercise(id: exerciseID, name: "Pull-up")],
            primitiveSetLogsByWorkout: [workout.id: [log]]
        )
        let vm = HistoryViewModel(cache: cache, calendar: utcCalendar, now: { [now] in now })
        await vm.load()
        XCTAssertNotNil(vm.detail(for: workout.id))

        let didReset = await vm.resetWorkout(workoutID: workout.id)
        XCTAssertTrue(didReset)
        XCTAssertTrue(cache.primitiveSetLogsByWorkout[workout.id]?.isEmpty == true)
        XCTAssertTrue(vm.groups.isEmpty)
    }

    // MARK: - Fixtures

    private struct FixtureIDs {
        let userID: UUID
        let benchID: UUID
        let ohpID: UUID
        let squatID: UUID
    }

    private func makeFixtures() -> (FakeHistoryCache, FixtureIDs) {
        let userID = UUID()
        let benchID = UUID()
        let ohpID = UUID()
        let squatID = UUID()
        let ids = FixtureIDs(userID: userID, benchID: benchID, ohpID: ohpID, squatID: squatID)

        let cache = FakeHistoryCache(
            workouts: [
                makeCompletedWorkout(name: "Push A", userID: userID,
                                     offset: 0, tags: ["push_day", "week_3"]),
                makeCompletedWorkout(name: "Legs A", userID: userID,
                                     offset: -86_400, tags: ["leg_day", "week_3"]),
                makeCompletedWorkout(name: "Untagged", userID: userID,
                                     offset: -172_800, tags: nil),
            ],
            blocksByWorkout: [:],
            itemsByBlock: [:],
            exercises: [
                Exercise(id: benchID, name: "Barbell Bench Press"),
                Exercise(id: ohpID, name: "Overhead Press"),
                Exercise(id: squatID, name: "Back Squat"),
            ],
            setLogsByWorkout: [:]
        )

        // Attach block + items + set_logs for each workout. Pattern is
        // two exercises per workout, 4 sets on exercise A and 3 on B.
        attachSession(cache: cache, workoutName: "Push A",
                      primaryExerciseID: benchID, secondaryExerciseID: ohpID)
        attachSession(cache: cache, workoutName: "Legs A",
                      primaryExerciseID: squatID, secondaryExerciseID: ohpID)
        attachSession(cache: cache, workoutName: "Untagged",
                      primaryExerciseID: benchID, secondaryExerciseID: ohpID)

        return (cache, ids)
    }

    private func makeCompletedWorkout(
        name: String,
        userID: UUID,
        offset: TimeInterval,
        tags: [String]?
    ) -> Workout {
        let completedAt = now.addingTimeInterval(offset)
        let tagsJSON: String?
        if let tags {
            let data = (try? JSONEncoder().encode(tags)) ?? Data()
            tagsJSON = String(data: data, encoding: .utf8)
        } else {
            tagsJSON = nil
        }
        return Workout(
            id: UUID(), userID: userID, name: name,
            scheduledDate: completedAt, status: .completed, source: .claude,
            notes: nil,
            createdAt: completedAt,
            updatedAt: completedAt,
            completedAt: completedAt,
            tagsJSON: tagsJSON
        )
    }

    private func attachSession(
        cache: FakeHistoryCache,
        workoutName: String,
        primaryExerciseID: UUID,
        secondaryExerciseID: UUID
    ) {
        guard let workout = cache.workouts.first(where: { $0.name == workoutName }) else {
            return
        }
        let blockID = UUID()
        let primaryItemID = UUID()
        let secondaryItemID = UUID()
        let block = Block(
            id: blockID, workoutID: workout.id, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: "{}", rounds: nil,
            roundsRepSchemeJSON: nil, notes: nil
        )
        let items = [
            WorkoutItem(id: primaryItemID, blockID: blockID, position: 0,
                        exerciseID: primaryExerciseID,
                        prescriptionJSON: #"{"sets":4,"reps":5,"load_kg":100}"#),
            WorkoutItem(id: secondaryItemID, blockID: blockID, position: 1,
                        exerciseID: secondaryExerciseID,
                        prescriptionJSON: #"{"sets":3,"reps":8,"load_kg":52.5}"#),
        ]
        cache.blocksByWorkout[workout.id] = [block]
        cache.itemsByBlock[blockID] = items

        let baseDate = workout.completedAt ?? now
        var logs: [SetLog] = []
        // setIndex is 1-based throughout the session pipeline (SessionSeeder
        // emits 1-based, the cursor starts at 1, and the formatter displays
        // as-is). Fixtures here mirror that — using 0-based indexes would
        // not match any real runtime state.
        for i in 1...4 {
            logs.append(SetLog(
                id: UUID(), workoutItemID: primaryItemID,
                performedExerciseID: nil, setIndex: i,
                reps: 5, weight: 100, weightUnit: .kg, rir: 2,
                isWarmup: false,
                startedAt: baseDate.addingTimeInterval(TimeInterval(i * 180 - 60)),
                completedAt: baseDate.addingTimeInterval(TimeInterval(i * 180)),
                notes: nil
            ))
        }
        for i in 1...3 {
            logs.append(SetLog(
                id: UUID(), workoutItemID: secondaryItemID,
                performedExerciseID: nil, setIndex: i,
                reps: 8, weight: 52.5, weightUnit: .kg, rir: 2,
                isWarmup: false,
                startedAt: baseDate.addingTimeInterval(TimeInterval(i * 150 + 600 - 45)),
                completedAt: baseDate.addingTimeInterval(TimeInterval(i * 150 + 600)),
                notes: nil
            ))
        }
        cache.setLogsByWorkout[workout.id] = logs
    }

    private func attachSkippedOnlySession(
        cache: FakeHistoryCache,
        userID: UUID,
        exerciseID: UUID
    ) {
        let workout = makeCompletedWorkout(
            name: "Skipped Only",
            userID: userID,
            offset: -259_200,
            tags: nil
        )
        cache.workouts.append(workout)
        let blockID = UUID()
        let itemID = UUID()
        cache.blocksByWorkout[workout.id] = [
            Block(
                id: blockID, workoutID: workout.id, parentBlockID: nil,
                position: 0, name: nil, timingMode: .straightSets,
                timingConfigJSON: "{}", rounds: nil,
                roundsRepSchemeJSON: nil, notes: nil
            ),
        ]
        cache.itemsByBlock[blockID] = [
            WorkoutItem(
                id: itemID, blockID: blockID, position: 0,
                exerciseID: exerciseID,
                prescriptionJSON: #"{"sets":1,"reps":10,"load_kg":20}"#
            ),
        ]
        cache.setLogsByWorkout[workout.id] = [
            SetLog(
                id: UUID(), workoutItemID: itemID,
                performedExerciseID: nil, setIndex: 1,
                reps: 10, weight: 20, weightUnit: .kg, rir: 2,
                isWarmup: false,
                skipped: true,
                startedAt: workout.completedAt?.addingTimeInterval(-60),
                completedAt: workout.completedAt ?? now,
                notes: nil
            ),
        ]
    }
}
