// TodayViewModelTests.swift
//
// Given a constructed `TodayContext`, the view model produces the right
// display strings in the right order. No SwiftUI is exercised here —
// rendering is verified implicitly via previews.

import XCTest
import CoreDomain
import CoreSession
import Persistence
import WorkoutCoreFoundation
@testable import FeaturesToday

@MainActor
final class TodayViewModelTests: XCTestCase {

    func testWorkoutAccessibilityVisibilityHidesOffscreenCards() {
        let visibleID = UUID()
        let belowID = UUID()
        let aboveID = UUID()
        let frames: [UUID: CGRect] = [
            visibleID: CGRect(x: 16, y: 120, width: 320, height: 240),
            belowID: CGRect(x: 16, y: 950, width: 320, height: 240),
            aboveID: CGRect(x: 16, y: -260, width: 320, height: 120),
        ]

        let visible = TodayWorkoutAccessibilityVisibility.visibleWorkoutIDs(
            frames: frames,
            viewport: CGRect(x: 0, y: 0, width: 402, height: 874)
        )

        XCTAssertEqual(visible, [visibleID])
    }

    func testWorkoutAccessibilityVisibilityKeepsPartiallyVisibleCards() {
        let topClippedID = UUID()
        let bottomClippedID = UUID()
        let frames: [UUID: CGRect] = [
            topClippedID: CGRect(x: 16, y: -20, width: 320, height: 120),
            bottomClippedID: CGRect(x: 16, y: 840, width: 320, height: 120),
        ]

        let visible = TodayWorkoutAccessibilityVisibility.visibleWorkoutIDs(
            frames: frames,
            viewport: CGRect(x: 0, y: 0, width: 402, height: 874)
        )

        XCTAssertEqual(visible, [topClippedID, bottomClippedID])
    }

    func testDerivesSummariesInBlockAndPositionOrder() {
        let userID = UUID()
        let workoutID = UUID()
        let blockA = UUID()
        let blockB = UUID()
        let ex1 = UUID()
        let ex2 = UUID()
        let ex3 = UUID()
        let now = Date()

        let workout = Workout(
            id: workoutID, userID: userID, name: "Push A",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )

        // Two blocks, reversed on input, with items also reversed.
        // Expect final order: block A pos 0 → block A pos 1 → block B pos 0.
        let blocks = [
            Block(id: blockB, workoutID: workoutID, parentBlockID: nil,
                  position: 1, name: nil, timingMode: .straightSets,
                  timingConfigJSON: "{}", rounds: nil,
                  roundsRepSchemeJSON: nil, notes: nil),
            Block(id: blockA, workoutID: workoutID, parentBlockID: nil,
                  position: 0, name: nil, timingMode: .straightSets,
                  timingConfigJSON: "{}", rounds: nil,
                  roundsRepSchemeJSON: nil, notes: nil),
        ]

        let items = [
            WorkoutItem(id: UUID(), blockID: blockB, position: 0,
                        exerciseID: ex3,
                        prescriptionJSON: #"{"sets":3,"reps":10}"#),
            WorkoutItem(id: UUID(), blockID: blockA, position: 1,
                        exerciseID: ex2,
                        prescriptionJSON: #"{"sets":3,"reps":8,"load_kg":80}"#),
            WorkoutItem(id: UUID(), blockID: blockA, position: 0,
                        exerciseID: ex1,
                        prescriptionJSON: #"{"sets":4,"reps":5,"load_kg":102.5}"#),
        ]

        let exercises: [UUID: Exercise] = [
            ex1: Exercise(id: ex1, name: "Bench"),
            ex2: Exercise(id: ex2, name: "Row"),
            ex3: Exercise(id: ex3, name: "Dips"),
        ]

        let context = TodayContext(
            workout: workout,
            blocks: blocks,
            items: items,
            exercises: exercises,
            lastPerformed: [ex1: "5×5 @ 100 kg · RIR 2"],
            lastSessionSummary: "FRI · Push A · RIR 1.6 avg",
            programTags: ["week 3", "push day"]
        )

        let vm = TodayViewModel(context: context)

        XCTAssertEqual(vm.programName, "Push A")
        XCTAssertEqual(vm.programTags, ["week 3", "push day"])
        XCTAssertEqual(vm.lastSessionSummary, "FRI · Push A · RIR 1.6 avg")

        XCTAssertEqual(vm.exercises.count, 3)
        XCTAssertEqual(vm.exercises[0].name, "Bench")
        // R2.10: JSON fixtures in this test omit `weight_unit` → pound default.
        XCTAssertEqual(vm.exercises[0].prescriptionLine, "4 \u{00D7} 5 @ 102.5 lb")
        XCTAssertEqual(vm.exercises[0].lastTime, "5×5 @ 100 kg · RIR 2")

        XCTAssertEqual(vm.exercises[1].name, "Row")
        XCTAssertEqual(vm.exercises[1].prescriptionLine, "3 \u{00D7} 8 @ 80 lb")
        XCTAssertNil(vm.exercises[1].lastTime)

        XCTAssertEqual(vm.exercises[2].name, "Dips")
        // `{sets, reps}` with no load_kg discriminates as .bodyweight per
        // PrescriptionParser step 8 — renders as "3 × 10 BW".
        XCTAssertEqual(vm.exercises[2].prescriptionLine, "3 \u{00D7} 10 BW")
    }

    func testPlanSectionsGroupMissedTodayAndUpcomingWorkouts() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let userID = UUID()
        let missed = makeContext(
            userID: userID,
            name: "Lower Body",
            scheduledDate: now.addingTimeInterval(-86_400),
            tagsJSON: #"["lower","strength"]"#
        )
        let today = makeContext(
            userID: userID,
            name: "Push Pull",
            scheduledDate: now,
            tagsJSON: #"["upper","strength"]"#
        )
        let tomorrow = makeContext(
            userID: userID,
            name: "Conditioning",
            scheduledDate: now.addingTimeInterval(86_400),
            tagsJSON: #"["metcon"]"#
        )

        let plan = TodayPlanContext(
            selected: today,
            workouts: [today, missed, tomorrow]
        )
        let sections = TodayViewModel.derivePlanSections(from: plan, now: now)

        XCTAssertEqual(sections.map(\.kind), [.today, .missed, .upcoming])
        XCTAssertEqual(sections[0].workouts.first?.name, "Push Pull")
        XCTAssertEqual(sections[0].workouts.first?.badge, "ready")
        XCTAssertEqual(sections[0].workouts.first?.tagLine, "upper · strength")
        XCTAssertTrue(sections[0].workouts.first?.isStartable == true)
        XCTAssertEqual(sections[1].workouts.first?.name, "Lower Body")
        XCTAssertEqual(sections[1].workouts.first?.badge, "needs reschedule")
        XCTAssertFalse(sections[1].workouts.first?.isStartable == true)
        XCTAssertEqual(sections[2].workouts.first?.name, "Conditioning")
        XCTAssertNil(sections[2].workouts.first?.badge)
    }

    func testPlanSectionsTreatScheduledDateAsUTCDateOnly() {
        let originalTimeZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "America/Halifax")!
        defer { NSTimeZone.default = originalTimeZone }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let scheduledDate = formatter.date(from: "2026-04-24")!
        let now = ISO8601DateFormatter().date(from: "2026-04-24T12:00:00Z")!
        let context = makeContext(
            userID: UUID(),
            name: "Today By Wire Date",
            scheduledDate: scheduledDate,
            tagsJSON: nil
        )

        let sections = TodayViewModel.derivePlanSections(
            from: TodayPlanContext(selected: context, workouts: [context]),
            now: now
        )

        XCTAssertEqual(sections.first?.kind, .today)
        XCTAssertEqual(sections.first?.title, "TODAY · FRI APR 24")
    }

    func testWorkoutDetailShowsBlockTimingAndAllExercises() throws {
        let workoutID = UUID()
        let blockID = UUID()
        let benchID = UUID()
        let rowID = UUID()
        let dipsID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = Workout(
            id: workoutID,
            userID: UUID(),
            name: "Upper Superset",
            scheduledDate: now,
            status: .planned,
            source: .claude,
            notes: "Keep two reps in reserve.",
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            tagsJSON: #"["upper","density"]"#
        )
        let block = Block(
            id: blockID,
            workoutID: workoutID,
            parentBlockID: nil,
            position: 0,
            name: "A-series",
            timingMode: .superset,
            timingConfigJSON: #"{"rest_between_rounds_sec":90}"#,
            rounds: 3,
            roundsRepSchemeJSON: nil,
            notes: "Move quickly between lifts."
        )
        let context = TodayContext(
            workout: workout,
            blocks: [block],
            items: [
                WorkoutItem(
                    id: UUID(),
                    blockID: blockID,
                    position: 0,
                    exerciseID: benchID,
                    prescriptionJSON: #"{"sets":3,"reps":8,"load_kg":80}"#
                ),
                WorkoutItem(
                    id: UUID(),
                    blockID: blockID,
                    position: 1,
                    exerciseID: rowID,
                    prescriptionJSON: #"{"sets":3,"reps":10,"load_kg":60}"#
                ),
                WorkoutItem(
                    id: UUID(),
                    blockID: blockID,
                    position: 2,
                    exerciseID: dipsID,
                    prescriptionJSON: #"{"sets":3,"reps":12}"#
                ),
            ],
            exercises: [
                benchID: Exercise(id: benchID, name: "Bench Press"),
                rowID: Exercise(id: rowID, name: "Row"),
                dipsID: Exercise(id: dipsID, name: "Dips"),
            ],
            lastPerformed: [benchID: "3×8 @ 75 kg"]
        )
        let vm = TodayViewModel(
            planContext: TodayPlanContext(selected: context, workouts: [context])
        )
        let card = try XCTUnwrap(vm.planSections.first?.workouts.first)
        XCTAssertEqual(card.cardBlocks.count, 1)
        XCTAssertEqual(card.cardBlocks[0].title, "A-series")
        XCTAssertEqual(card.cardBlocks[0].timingLabel, "superset")
        XCTAssertEqual(card.cardBlocks[0].timingDetail, "3 rounds · rest between rounds 1:30")
        XCTAssertEqual(card.cardBlocks[0].exercises.map(\.name), ["Bench Press", "Row"])
        XCTAssertTrue(card.cardBlocks[0].hasMoreExercises)

        let detail = try XCTUnwrap(vm.detail(for: workoutID))
        XCTAssertEqual(detail.name, "Upper Superset")
        XCTAssertEqual(detail.tagLine, "upper · density")
        XCTAssertEqual(detail.notes, "Keep two reps in reserve.")
        XCTAssertEqual(detail.blocks.count, 1)
        XCTAssertEqual(detail.blocks[0].title, "A-series")
        XCTAssertEqual(detail.blocks[0].timingLabel, "superset")
        XCTAssertEqual(detail.blocks[0].timingDetail, "3 rounds · rest between rounds 1:30")
        XCTAssertEqual(detail.blocks[0].notes, "Move quickly between lifts.")
        XCTAssertEqual(detail.blocks[0].exercises.map(\.name), ["Bench Press", "Row", "Dips"])
        XCTAssertEqual(detail.blocks[0].exercises.first?.lastTime, "3×8 @ 75 kg")
    }

    func testWorkoutDetailUsesPrimitiveProjectionForPreviewSummary() throws {
        let workoutID = UUID()
        let blockID = UUID()
        let primitiveSetID = UUID()
        let benchSlotID = UUID()
        let rowSlotID = UUID()
        let benchID = UUID()
        let rowID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = Workout(
            id: workoutID,
            userID: UUID(),
            name: "Primitive Preview",
            scheduledDate: now,
            status: .planned,
            source: .claude,
            notes: nil,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            tagsJSON: nil
        )
        let block = Block(
            id: blockID,
            workoutID: workoutID,
            position: 0,
            name: "A-series",
            timingMode: .superset,
            timingConfigJSON: #"{"rounds":2}"#,
            rounds: 2,
            intent: "Keep transitions crisp."
        )
        let primitiveWorkout = PrimitiveWorkout(
            id: workoutID,
            name: "Primitive Preview",
            blocks: [
                PrimitiveBlock(id: blockID, sets: [
                    PrimitiveSet(
                        id: primitiveSetID,
                        timing: .init(mode: .setBounded),
                        traversal: .roundRobin,
                        repeatCount: 2,
                        slots: [
                            PrimitiveSlot(
                                id: benchSlotID,
                                exerciseID: benchID,
                                workTargets: [
                                    .init(
                                        metric: .reps,
                                        valueForm: .single,
                                        value: 5,
                                        role: .completion
                                    ),
                                ],
                                load: .init(value: 100, unit: .kg, unitType: .absolute)
                            ),
                            PrimitiveSlot(
                                id: rowSlotID,
                                exerciseID: rowID,
                                workTargets: [
                                    .init(
                                        metric: .reps,
                                        valueForm: .single,
                                        value: 8,
                                        role: .completion
                                    ),
                                ]
                            ),
                        ]
                    ),
                ]),
            ]
        )
        let context = TodayContext(
            workout: workout,
            primitiveWorkout: primitiveWorkout,
            primitiveExecutionPlan: try ExecutionPlan.validated(workout: primitiveWorkout),
            blocks: [block],
            items: [],
            exercises: [
                benchID: Exercise(id: benchID, name: "Bench Press"),
                rowID: Exercise(id: rowID, name: "Row"),
            ],
            lastPerformed: [:]
        )

        let vm = TodayViewModel(
            planContext: TodayPlanContext(selected: context, workouts: [context])
        )
        let detail = try XCTUnwrap(vm.detail(for: workoutID))
        let preview = try XCTUnwrap(detail.preview)

        XCTAssertEqual(preview.currentTitle, "Bench Press")
        XCTAssertEqual(preview.currentDetail, "100 kg · 5 reps")
        XCTAssertEqual(preview.blockIntent, "Keep transitions crisp.")
        XCTAssertEqual(preview.remainingLine, "2 sets left in current block of 2")
        XCTAssertEqual(preview.upcoming.map(\.title), ["Row", "Bench Press", "Row"])
        XCTAssertEqual(preview.upcoming.map(\.detail), ["8 reps", "100 kg · 5 reps", "8 reps"])
    }

    func testWorkoutDetailDoesNotPreviewZeroSlotTimedPrimitiveWork() throws {
        let workoutID = UUID()
        let blockID = UUID()
        let primitiveSetID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = Workout(
            id: workoutID,
            userID: UUID(),
            name: "Intervals",
            scheduledDate: now,
            status: .planned,
            source: .claude,
            notes: nil,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            tagsJSON: nil
        )
        let block = Block(
            id: blockID,
            workoutID: workoutID,
            position: 0,
            name: "Bike intervals",
            timingMode: .emom,
            timingConfigJSON: #"{"interval_sec":60,"total_minutes":3}"#,
            intent: "Hold a steady cadence"
        )
        let primitiveWorkout = PrimitiveWorkout(
            id: workoutID,
            name: "Intervals",
            blocks: [
                PrimitiveBlock(id: blockID, sets: [
                    PrimitiveSet(
                        id: primitiveSetID,
                        timing: .init(mode: .timeBounded, intervalSec: 60, rounds: 3),
                        slots: []
                    ),
                ]),
            ]
        )
        let context = TodayContext(
            workout: workout,
            primitiveWorkout: primitiveWorkout,
            primitiveExecutionPlan: nil,
            blocks: [block],
            items: [],
            exercises: [:],
            lastPerformed: [:]
        )

        let vm = TodayViewModel(
            planContext: TodayPlanContext(selected: context, workouts: [context])
        )
        let detail = try XCTUnwrap(vm.detail(for: workoutID))
        XCTAssertNil(detail.preview)
    }

    func testAdjustmentDraftIncludesWorkoutContext() throws {
        let workoutID = UUID()
        let blockID = UUID()
        let benchID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let context = TodayContext(
            workout: Workout(
                id: workoutID,
                userID: UUID(),
                name: "Push Pull",
                scheduledDate: now,
                status: .planned,
                source: .claude,
                notes: "Avoid overhead pressing.",
                createdAt: now,
                updatedAt: now,
                completedAt: nil,
                tagsJSON: #"["upper"]"#
            ),
            blocks: [Block(
                id: blockID,
                workoutID: workoutID,
                parentBlockID: nil,
                position: 0,
                name: "Main Strength",
                timingMode: .straightSets,
                timingConfigJSON: #"{"rest_between_sets_sec":120}"#,
                rounds: nil,
                roundsRepSchemeJSON: nil,
                notes: nil
            )],
            items: [WorkoutItem(
                id: UUID(),
                blockID: blockID,
                position: 0,
                exerciseID: benchID,
                prescriptionJSON: #"{"sets":4,"reps":5,"load_kg":100}"#
            )],
            exercises: [benchID: Exercise(id: benchID, name: "Bench Press")],
            lastPerformed: [:]
        )
        let vm = TodayViewModel(
            planContext: TodayPlanContext(selected: context, workouts: [context])
        )
        let detail = try XCTUnwrap(vm.detail(for: workoutID))
        let draft = vm.adjustmentDraft(for: detail)

        XCTAssertTrue(draft.body.contains("Please adjust this planned workout:"))
        XCTAssertTrue(draft.body.contains("Workout: Push Pull"))
        XCTAssertTrue(draft.body.contains("Notes: Avoid overhead pressing."))
        XCTAssertTrue(draft.body.contains("- Main Strength (straight sets)"))
        XCTAssertTrue(draft.body.contains("  - Bench Press — 4 × 5 @ 100 lb"))
    }

    func testRefreshActionUpdatesRefreshState() async {
        final class CaptureBox: @unchecked Sendable {
            var callCount = 0
        }
        let box = CaptureBox()
        let context = makeContext(
            userID: UUID(),
            name: "Refreshable",
            scheduledDate: Date(timeIntervalSince1970: 1_700_000_000),
            tagsJSON: nil
        )
        let vm = TodayViewModel(
            planContext: TodayPlanContext(selected: context, workouts: [context])
        )
        vm.setRefreshAction {
            box.callCount += 1
            return false
        }

        await vm.refresh()

        XCTAssertEqual(box.callCount, 1)
        XCTAssertEqual(vm.refreshState, .failed)
    }

    func testUnknownExerciseDoesNotCrash() {
        let workoutID = UUID()
        let blockID = UUID()
        let orphanExerciseID = UUID()
        let now = Date()

        let ctx = TodayContext(
            workout: Workout(
                id: workoutID, userID: UUID(), name: "X",
                scheduledDate: now, status: .planned, source: .claude,
                notes: nil, createdAt: now, updatedAt: now,
                completedAt: nil, tagsJSON: nil
            ),
            blocks: [Block(
                id: blockID, workoutID: workoutID, parentBlockID: nil,
                position: 0, name: nil, timingMode: .straightSets,
                timingConfigJSON: "{}", rounds: nil,
                roundsRepSchemeJSON: nil, notes: nil
            )],
            items: [WorkoutItem(
                id: UUID(), blockID: blockID, position: 0,
                exerciseID: orphanExerciseID,
                prescriptionJSON: #"{"sets":3,"reps":5,"load_kg":60}"#
            )],
            exercises: [:], // deliberately empty — item's exerciseID is orphan
            lastPerformed: [:]
        )

        let vm = TodayViewModel(context: ctx)
        XCTAssertEqual(vm.exercises.count, 1)
        XCTAssertEqual(vm.exercises[0].name, "(unknown exercise)")
        XCTAssertEqual(vm.exercises[0].prescriptionLine, "3 \u{00D7} 5 @ 60 lb")
    }

    func testWorkoutKitHandoffActionIsPendingBeforeAwaitingScheduler() async {
        let workoutID = UUID()
        let context = makeContext(
            userID: UUID(),
            name: "Run",
            scheduledDate: Date(),
            tagsJSON: nil,
            workoutID: workoutID
        )
        let vm = TodayViewModel(context: context)
        vm.setWorkoutKitHandoffs([
            workoutID: TodayViewModel.WorkoutKitHandoffSummary(
                state: .ready,
                title: "Apple Workout",
                message: "Ready",
                actionTitle: "Watch",
                isActionable: true
            ),
        ])

        var scheduleCalls = 0
        vm.setWorkoutKitHandoffAction { _ in
            scheduleCalls += 1
            try? await Task.sleep(nanoseconds: 25_000_000)
            return TodayViewModel.WorkoutKitHandoffSummary(
                state: .scheduled,
                title: "Apple Workout",
                message: "Scheduled",
                isActionable: false
            )
        }

        async let first: Void = vm.scheduleWorkoutKitHandoff(workoutID: workoutID)
        async let second: Void = vm.scheduleWorkoutKitHandoff(workoutID: workoutID)
        _ = await (first, second)

        XCTAssertEqual(scheduleCalls, 1)
        XCTAssertEqual(vm.detail(for: workoutID)?.workoutKitHandoff?.state, .scheduled)
    }

    private func makeContext(
        userID: UUID,
        name: String,
        scheduledDate: Date,
        tagsJSON: String?,
        workoutID: UUID = UUID()
    ) -> TodayContext {
        return TodayContext(
            workout: Workout(
                id: workoutID,
                userID: userID,
                name: name,
                scheduledDate: scheduledDate,
                status: .planned,
                source: .claude,
                notes: nil,
                createdAt: scheduledDate,
                updatedAt: scheduledDate,
                completedAt: nil,
                tagsJSON: tagsJSON
            ),
            blocks: [],
            items: [],
            exercises: [:],
            lastPerformed: [:]
        )
    }

    func testStartDispatchesMutation() {
        final class CaptureBox: @unchecked Sendable {
            var captured: [SessionMutation] = []
        }
        let box = CaptureBox()

        let workoutID = UUID()
        let ctx = TodayContext(
            workout: Workout(
                id: workoutID, userID: UUID(), name: "X",
                scheduledDate: Date(), status: .planned, source: .claude,
                notes: nil, createdAt: Date(), updatedAt: Date(),
                completedAt: nil, tagsJSON: nil
            ),
            blocks: [],
            items: [],
            exercises: [:],
            lastPerformed: [:],
            sessionStateBinding: { m in box.captured.append(m) }
        )
        let vm = TodayViewModel(context: ctx)
        vm.start()
        XCTAssertEqual(box.captured, [.start])
    }

    func testStartSpecificWorkoutUsesInjectedAction() async {
        final class CaptureBox: @unchecked Sendable {
            var started: [WorkoutID] = []
        }
        let box = CaptureBox()
        let selectedID = UUID()
        let alternateID = UUID()
        let selected = makeContext(
            userID: UUID(),
            name: "Today",
            scheduledDate: Date(),
            tagsJSON: nil,
            workoutID: selectedID
        )
        let alternate = makeContext(
            userID: selected.workout.userID,
            name: "Tomorrow",
            scheduledDate: Date().addingTimeInterval(86_400),
            tagsJSON: nil,
            workoutID: alternateID
        )
        let vm = TodayViewModel(planContext: TodayPlanContext(
            selected: selected,
            workouts: [selected, alternate]
        ))
        vm.setStartWorkoutAction { id in
            box.started.append(id)
            return true
        }

        await vm.start(workoutID: alternateID)

        XCTAssertEqual(box.started, [alternateID])
    }

    func testPreviewStartGateRequiresSelectedWorkoutOrInjectedStarter() {
        let selectedID = UUID()
        let alternateID = UUID()
        let selected = makeContext(
            userID: UUID(),
            name: "Today",
            scheduledDate: Date(),
            tagsJSON: nil,
            workoutID: selectedID
        )
        let alternate = makeContext(
            userID: selected.workout.userID,
            name: "Tomorrow",
            scheduledDate: Date().addingTimeInterval(86_400),
            tagsJSON: nil,
            workoutID: alternateID
        )
        let vm = TodayViewModel(planContext: TodayPlanContext(
            selected: selected,
            workouts: [selected, alternate]
        ))

        XCTAssertTrue(vm.canStart(workoutID: selectedID))
        XCTAssertFalse(vm.canStart(workoutID: alternateID))

        vm.setStartWorkoutAction { _ in true }

        XCTAssertTrue(vm.canStart(workoutID: alternateID))
    }

    func testPreviewStartGateRejectsInvalidPrimitiveAlternateEvenWithInjectedStarter() {
        let selectedID = UUID()
        let alternateID = UUID()
        let selected = makeContext(
            userID: UUID(),
            name: "Today",
            scheduledDate: Date(),
            tagsJSON: nil,
            workoutID: selectedID
        )
        let alternateWorkout = Workout(
            id: alternateID,
            userID: selected.workout.userID,
            name: "Invalid primitive alternate",
            scheduledDate: Date().addingTimeInterval(86_400),
            status: .planned,
            source: .claude,
            notes: nil,
            createdAt: Date(),
            updatedAt: Date(),
            completedAt: nil,
            tagsJSON: nil
        )
        let primitiveWorkout = PrimitiveWorkout(
            id: alternateID,
            name: alternateWorkout.name,
            blocks: [
                PrimitiveBlock(id: UUID(), sets: [
                    PrimitiveSet(
                        id: UUID(),
                        timing: .init(mode: .timeBounded, intervalSec: 60, rounds: 1),
                        slots: []
                    ),
                ]),
            ]
        )
        let alternate = TodayContext(
            workout: alternateWorkout,
            primitiveWorkout: primitiveWorkout,
            primitiveExecutionPlan: nil,
            blocks: [],
            items: [],
            exercises: [:],
            lastPerformed: [:]
        )
        let vm = TodayViewModel(planContext: TodayPlanContext(
            selected: selected,
            workouts: [selected, alternate]
        ))
        vm.setStartWorkoutAction { _ in true }

        XCTAssertFalse(vm.canStart(workoutID: alternateID))
    }

    // MARK: - Reload (bug-036)

    /// Seed two planned workouts, complete the first via a cache status
    /// flip, then call `reload`. The VM must advance to the second
    /// workout — previously the completed workout stayed on screen
    /// until relaunch.
    func testTodayViewModelReloadPicksNextPlannedAfterCompletion() async throws {
        let userID = UUID()
        let workout1ID = UUID()
        let workout2ID = UUID()
        let blockA = UUID()
        let blockB = UUID()
        let benchID = UUID()
        let squatID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Schedule workout 2 further in the past — both are past-or-today
        // candidates and `TodayLoader.pickClosest` picks the nearer one.
        // After workout 1 flips to `.completed`, the loader sees only
        // workout 2 as planned.
        let workout1 = Workout(
            id: workout1ID, userID: userID, name: "Push A",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let workout2 = Workout(
            id: workout2ID, userID: userID, name: "Pull A",
            scheduledDate: now.addingTimeInterval(-86_400),
            status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block1 = Block(
            id: blockA, workoutID: workout1ID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: "{}", rounds: nil,
            roundsRepSchemeJSON: nil, notes: nil
        )
        let block2 = Block(
            id: blockB, workoutID: workout2ID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: "{}", rounds: nil,
            roundsRepSchemeJSON: nil, notes: nil
        )
        let item1 = WorkoutItem(
            id: UUID(), blockID: blockA, position: 0,
            exerciseID: benchID,
            prescriptionJSON: #"{"sets":4,"reps":5,"load_kg":102.5}"#
        )
        let item2 = WorkoutItem(
            id: UUID(), blockID: blockB, position: 0,
            exerciseID: squatID,
            prescriptionJSON: #"{"sets":3,"reps":8,"load_kg":140}"#
        )

        let cache = MutableFakeCache(
            workouts: [workout1, workout2],
            blocks: [workout1ID: [block1], workout2ID: [block2]],
            items: [blockA: [item1], blockB: [item2]],
            exercises: [
                Exercise(id: benchID, name: "Bench"),
                Exercise(id: squatID, name: "Squat"),
            ]
        )
        let loader = TodayLoader(cache: cache, clock: { now })

        // Initial load → workout 1 (today, closer than workout 2).
        let firstCtx = try await loader.load()
        let ctx = try XCTUnwrap(firstCtx)
        let vm = TodayViewModel(context: ctx)
        XCTAssertEqual(vm.workoutID, workout1ID)
        XCTAssertEqual(vm.programName, "Push A")

        // Simulate save-and-done: flip workout 1 to `.completed` in the
        // cache. Workout 2 remains `.planned`.
        cache.markCompleted(workoutID: workout1ID)

        // Reload → VM must advance to workout 2.
        await vm.reload(using: loader)
        XCTAssertFalse(vm.isEmpty)
        XCTAssertEqual(vm.workoutID, workout2ID)
        XCTAssertEqual(vm.programName, "Pull A")
        XCTAssertEqual(vm.exercises.count, 1)
        XCTAssertEqual(vm.exercises.first?.name, "Squat")
    }

    /// qa-008 regression: the VM must expose `showsStartButton` that
    /// tracks `!isEmpty`. The view uses this to gate the pinned CTA —
    /// previously, the start button rendered even when `isEmpty == true`,
    /// producing a black screen with a disconnected "start workout"
    /// button after the last planned workout was completed.
    func testTodayViewShowsStartButtonWhenContextPresent() {
        let workoutID = UUID()
        let ctx = TodayContext(
            workout: Workout(
                id: workoutID, userID: UUID(), name: "Push A",
                scheduledDate: Date(), status: .planned, source: .claude,
                notes: nil, createdAt: Date(), updatedAt: Date(),
                completedAt: nil, tagsJSON: nil
            ),
            blocks: [],
            items: [],
            exercises: [:],
            lastPerformed: [:]
        )
        let vm = TodayViewModel(context: ctx)
        XCTAssertFalse(vm.isEmpty)
        XCTAssertTrue(vm.showsStartButton)
    }

    /// qa-008 regression: `showsStartButton` is `false` when the VM is
    /// in its empty-shaped state (S11 — reload returned `nil`). The
    /// view must hide the pinned "start workout" button in this case.
    func testTodayViewHidesStartButtonWhenEmpty() {
        let workoutID = UUID()
        let ctx = TodayContext(
            workout: Workout(
                id: workoutID, userID: UUID(), name: "Push A",
                scheduledDate: Date(), status: .planned, source: .claude,
                notes: nil, createdAt: Date(), updatedAt: Date(),
                completedAt: nil, tagsJSON: nil
            ),
            blocks: [],
            items: [],
            exercises: [:],
            lastPerformed: [:]
        )
        let vm = TodayViewModel(context: ctx)
        // Flip to empty-shaped state — models reload-to-empty (S11).
        vm.apply(nil)
        XCTAssertTrue(vm.isEmpty)
        XCTAssertFalse(vm.showsStartButton)
    }

    // MARK: - qa-001 — lastPerformed sourced from LastPerformedStore

    /// Regression for qa-001 — `TodayLoader.load()` used to default
    /// `lastPerformed` to `[:]`, so even when a pull successfully
    /// returned a snapshot it never reached the VM. The loader now
    /// pulls from an injected `LastPerformedStore`; this test proves
    /// the derived chip strings appear on `vm.exercises[*].lastTime`.
    func testTodayViewRendersLastChipWhenLastPerformedPresent() async throws {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let benchID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let workout = Workout(
            id: workoutID, userID: userID, name: "Push A",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: "{}", rounds: nil,
            roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: UUID(), blockID: blockID, position: 0,
            exerciseID: benchID,
            prescriptionJSON: #"{"sets":4,"reps":5,"load_kg":100}"#
        )

        let cache = MutableFakeCache(
            workouts: [workout],
            blocks: [workoutID: [block]],
            items: [blockID: [item]],
            exercises: [Exercise(id: benchID, name: "Bench")]
        )
        let store = FakeLastPerformedStore(
            initial: [benchID: "5×5 @ 100 kg · RIR 2"]
        )
        let loader = TodayLoader(
            cache: cache,
            lastPerformedStore: store,
            clock: { now }
        )

        let loaded = try await loader.load()
        let ctx = try XCTUnwrap(loaded)
        let vm = TodayViewModel(context: ctx)
        XCTAssertEqual(vm.exercises.count, 1)
        XCTAssertEqual(vm.exercises.first?.lastTime, "5×5 @ 100 kg · RIR 2")
    }

    /// Same shape but the store is empty — the chip must be nil so the
    /// UI hides the "LAST TIME" row rather than rendering a blank chip
    /// (qa-001 symptom).
    func testTodayViewHidesLastChipWhenStoreEmpty() async throws {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let benchID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let workout = Workout(
            id: workoutID, userID: userID, name: "Push A",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: "{}", rounds: nil,
            roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: UUID(), blockID: blockID, position: 0,
            exerciseID: benchID,
            prescriptionJSON: #"{"sets":4,"reps":5,"load_kg":100}"#
        )
        let cache = MutableFakeCache(
            workouts: [workout],
            blocks: [workoutID: [block]],
            items: [blockID: [item]],
            exercises: [Exercise(id: benchID, name: "Bench")]
        )
        let store = FakeLastPerformedStore(initial: [:])
        let loader = TodayLoader(
            cache: cache,
            lastPerformedStore: store,
            clock: { now }
        )

        let loaded = try await loader.load()
        let ctx = try XCTUnwrap(loaded)
        let vm = TodayViewModel(context: ctx)
        XCTAssertNil(vm.exercises.first?.lastTime)
    }

    /// Seed a single planned workout, complete it, and reload. The
    /// loader returns nil; the VM must flip to empty-shaped so the UI
    /// renders the "nothing scheduled" glance.
    func testTodayViewModelReloadToEmptyWhenNoPlannedWorkouts() async throws {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let benchID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = Workout(
            id: workoutID, userID: userID, name: "Only",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON: "{}", rounds: nil,
            roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: UUID(), blockID: blockID, position: 0,
            exerciseID: benchID,
            prescriptionJSON: #"{"sets":4,"reps":5,"load_kg":100}"#
        )

        let cache = MutableFakeCache(
            workouts: [workout],
            blocks: [workoutID: [block]],
            items: [blockID: [item]],
            exercises: [Exercise(id: benchID, name: "Bench")]
        )
        let loader = TodayLoader(cache: cache, clock: { now })

        let firstCtx = try await loader.load()
        let ctx = try XCTUnwrap(firstCtx)
        let vm = TodayViewModel(context: ctx)
        XCTAssertFalse(vm.isEmpty)
        XCTAssertEqual(vm.workoutID, workoutID)

        cache.markCompleted(workoutID: workoutID)

        await vm.reload(using: loader)
        XCTAssertTrue(vm.isEmpty)
        XCTAssertNil(vm.workoutID)
        XCTAssertEqual(vm.exercises, [])
        XCTAssertEqual(vm.programName, "")
        XCTAssertNil(vm.lastSessionSummary)
        XCTAssertEqual(vm.programTags, [])
        // qa-008: the pinned "start workout" CTA must be hidden in
        // this state — rendering it produces an orphaned button.
        XCTAssertFalse(vm.showsStartButton)
    }
}

// MARK: - Test cache

/// Minimal mutable `WorkoutCache` stand-in used by the reload tests.
/// `markCompleted(workoutID:)` flips the in-memory workout's status so
/// the next `TodayLoader.load()` skips it — models what the
/// `ExecutionViewModel.saveAndDone` → `WorkoutCache.saveWorkout` write
/// does in production without requiring a full in-memory SwiftData stack
/// here (FeaturesToday's test target deliberately stays off SwiftData —
/// see `Package.swift` test target note).
private final class MutableFakeCache: WorkoutCache, @unchecked Sendable {
    private let lock = NSLock()
    private var workouts: [Workout]
    private let blocksByWorkout: [UUID: [Block]]
    private let itemsByBlock: [UUID: [WorkoutItem]]
    private let exercises: [Exercise]

    init(
        workouts: [Workout],
        blocks: [UUID: [Block]],
        items: [UUID: [WorkoutItem]],
        exercises: [Exercise]
    ) {
        self.workouts = workouts
        self.blocksByWorkout = blocks
        self.itemsByBlock = items
        self.exercises = exercises
    }

    func markCompleted(workoutID: UUID) {
        lock.withLock {
            workouts = workouts.map { workout in
                guard workout.id == workoutID else { return workout }
                return Workout(
                    id: workout.id,
                    userID: workout.userID,
                    name: workout.name,
                    scheduledDate: workout.scheduledDate,
                    status: .completed,
                    source: workout.source,
                    notes: workout.notes,
                    createdAt: workout.createdAt,
                    updatedAt: workout.updatedAt,
                    completedAt: Date(),
                    tagsJSON: workout.tagsJSON
                )
            }
        }
    }

    func save(_ dataset: PulledDataset) async throws {}

    func loadWorkouts(status: WorkoutStatus?, since: Date?) async throws -> [Workout] {
        lock.withLock {
            guard let status else { return workouts }
            return workouts.filter { $0.status == status }
        }
    }

    func loadPrimitiveWorkouts() async throws -> [PrimitiveWorkout] { [] }

    func loadBlocks(workoutID: WorkoutID) async throws -> [Block] {
        blocksByWorkout[workoutID] ?? []
    }

    func loadItems(blockID: BlockID) async throws -> [WorkoutItem] {
        itemsByBlock[blockID] ?? []
    }

    func loadItems(
        workoutIDs: [WorkoutID]
    ) async throws -> [WorkoutID: [WorkoutItem]] {
        guard !workoutIDs.isEmpty else { return [:] }
        let wanted = Set(workoutIDs)
        var out: [WorkoutID: [WorkoutItem]] = [:]
        for (workoutID, blocks) in blocksByWorkout where wanted.contains(workoutID) {
            var items: [WorkoutItem] = []
            for block in blocks.sorted(by: { $0.position < $1.position }) {
                items.append(contentsOf: itemsByBlock[block.id] ?? [])
            }
            if !items.isEmpty { out[workoutID] = items }
        }
        return out
    }

    func loadAlternatives(workoutItemID: WorkoutItemID) async throws -> [ExerciseAlternative] {
        []
    }

    func loadExercises() async throws -> [Exercise] {
        exercises
    }

    func loadUserParametersLatest() async throws -> [String: UserParameter] {
        [:]
    }

    func loadUserParameters(key: String) async throws -> [UserParameter] {
        []
    }

    func loadCompletedWorkouts(limit: Int, offset: Int) async throws -> [Workout] {
        []
    }

    func loadSetLogs(workoutID: WorkoutID) async throws -> [SetLog] {
        []
    }

    func loadPrimitiveSetLogs(workoutID: WorkoutID) async throws -> [PrimitiveSetLog] { [] }

    func loadPrimitiveSetLogs(exerciseID: ExerciseID, limit: Int) async throws -> [PrimitiveSetLog] {
        []
    }

    func loadSetLogs(exerciseID: ExerciseID, limit: Int) async throws -> [SetLog] {
        []
    }

    func loadOrphanedSetLogs() async throws -> [SetLog] { [] }

    func saveSetLogs(_ setLogs: [SetLog], workoutID: WorkoutID) async throws {}

    func savePrimitiveSetLogs(_ setLogs: [PrimitiveSetLog], workoutID: WorkoutID) async throws {}

    func resetWorkout(workoutID: WorkoutID) async throws {}

    func saveWorkout(_ workout: Workout) async throws {
        lock.withLock {
            if let idx = workouts.firstIndex(where: { $0.id == workout.id }) {
                workouts[idx] = workout
            } else {
                workouts.append(workout)
            }
        }
    }

    func saveUserParameter(_ param: UserParameter) async throws {}

    func clear() async throws {}
}

/// In-memory `LastPerformedStore` for the qa-001 regression tests.
/// Mirrors the UserDefaults-backed `LastPerformedStoreImpl` without
/// depending on the host's standardUserDefaults (keeps the test target
/// hermetic — see FeaturesToday Package.swift's "Swift code only" note).
private final class FakeLastPerformedStore: LastPerformedStore, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [UUID: String]

    init(initial: [UUID: String]) {
        self.entries = initial
    }

    func load() async -> [UUID: String] {
        lock.withLock { entries }
    }

    func save(_ entries: [UUID: String]) async {
        lock.withLock {
            self.entries = entries
        }
    }

    func clear() async {
        lock.withLock {
            entries = [:]
        }
    }
}
