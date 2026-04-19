// SessionSeederTabataCollapseTelemetryTests.swift
//
// Regression coverage for the tabata multi-item collapse telemetry.
// `SessionSeeder.normalizeBlockItems` silently drops items[1..] from a
// multi-item tabata block — a deliberate paired behavior with
// `TabataDriver.activeContent` pinning to items[0] (see
// `docs/prescription.md` § "tabata"). The collapse is correct, but a
// user authoring such a block and seeing a single-item render had no
// signal that the drop happened.
//
// The VM now:
//   - seeds through `SessionSeeder.seedWithNormalization` which returns
//     a manifest of drops alongside the state;
//   - emits one `execution.tabata_multi_item_collapsed` event per
//     affected block, carrying block_index + dropped_item_count +
//     dropped_exercise_ids (lowercase via `.wireID`).
//
// The pure seeder path (`SessionSeeder.seed(context:)`) stays side-
// effect free — tests that exercise the seeder directly don't have to
// wire a telemetry emitter. `TelemetryRecorder` is shared with
// `ExecutionViewModelEditPastSetTests`.

import XCTest
import CoreDomain
import CoreTelemetry
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class SessionSeederTabataCollapseTelemetryTests: XCTestCase {

    func testTabataMultiItemCollapseEmitsTelemetry() throws {
        let workoutID = UUID()
        let userID = UUID()
        let blockID = UUID()
        let exerciseIDs = (0..<3).map { _ in UUID() }
        let itemIDs = (0..<3).map { _ in UUID() }
        let now = Date()

        let workout = Workout(
            id: workoutID, userID: userID, name: "tabata-collapse",
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
        let items: [WorkoutItem] = zip(itemIDs, exerciseIDs).enumerated().map { idx, pair in
            WorkoutItem(
                id: pair.0, blockID: blockID, position: idx,
                exerciseID: pair.1,
                prescriptionJSON: #"{"reps":10}"#
            )
        }
        let exercises = Dictionary(
            uniqueKeysWithValues: exerciseIDs.enumerated().map { idx, id in
                (id, Exercise(id: id, name: "Ex\(idx)"))
            }
        )
        let ctx = WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [items],
            exercises: exercises
        )

        let recorder = TelemetryRecorder()
        _ = ExecutionViewModel(context: ctx, telemetry: recorder)

        let collapseEvents = recorder.events.filter {
            $0.name == "execution.tabata_multi_item_collapsed"
        }
        XCTAssertEqual(collapseEvents.count, 1, "exactly one collapse event for the one affected block")

        let event = try XCTUnwrap(collapseEvents.first)
        XCTAssertEqual(event.workoutID, workoutID, "event is tagged with the owning workout")
        XCTAssertEqual(event.kind, "state")

        let data = try XCTUnwrap(event.dataJSON)
        XCTAssertTrue(
            data.contains(#""block_index":0"#),
            "payload carries the affected block index (snake_case). got: \(data)"
        )
        XCTAssertTrue(
            data.contains(#""dropped_item_count":2"#),
            "two of three items were dropped. got: \(data)"
        )
        // The kept item is items[0]; exercises for items[1] and items[2]
        // are the dropped ones. Exercise ids land in the payload pre-
        // lowercased via `.wireID`.
        XCTAssertTrue(
            data.contains(exerciseIDs[1].wireID),
            "dropped_exercise_ids contains items[1]'s exercise id. got: \(data)"
        )
        XCTAssertTrue(
            data.contains(exerciseIDs[2].wireID),
            "dropped_exercise_ids contains items[2]'s exercise id. got: \(data)"
        )
        XCTAssertFalse(
            data.contains(exerciseIDs[0].wireID),
            "items[0] was kept, so its exercise id must NOT appear in the drop list. got: \(data)"
        )
    }

    func testSingleItemTabataDoesNotEmitCollapse() {
        // A well-authored single-item tabata must not emit the collapse
        // event. This is the common case; the telemetry fires only when
        // normalization actually dropped something.
        let workoutID = UUID()
        let userID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let itemID = UUID()
        let now = Date()

        let workout = Workout(
            id: workoutID, userID: userID, name: "tabata-clean",
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
            prescriptionJSON: #"{"reps":20}"#
        )
        let ctx = WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "AirSquat")]
        )

        let recorder = TelemetryRecorder()
        _ = ExecutionViewModel(context: ctx, telemetry: recorder)

        let collapseEvents = recorder.events.filter {
            $0.name == "execution.tabata_multi_item_collapsed"
        }
        XCTAssertTrue(collapseEvents.isEmpty,
                      "no collapse event when nothing was dropped")
    }

    func testSeedWithNormalizationReturnsCollapseManifest() {
        // Lock the data shape on the seeder's own API — the VM is one
        // consumer, but a future caller (e.g. a pull-time validator)
        // should also get a structured manifest instead of diffing
        // itemsByBlock.
        let workoutID = UUID()
        let blockID = UUID()
        let e0 = UUID(); let e1 = UUID()
        let i0 = UUID(); let i1 = UUID()
        let now = Date()

        let workout = Workout(
            id: workoutID, userID: UUID(), name: "seed-manifest",
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
        let items = [
            WorkoutItem(id: i0, blockID: blockID, position: 0,
                        exerciseID: e0, prescriptionJSON: #"{"reps":20}"#),
            WorkoutItem(id: i1, blockID: blockID, position: 1,
                        exerciseID: e1, prescriptionJSON: #"{"reps":20}"#),
        ]
        let ctx = WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [items],
            exercises: [e0: Exercise(id: e0, name: "A"),
                        e1: Exercise(id: e1, name: "B")]
        )

        let result = SessionSeeder.seedWithNormalization(context: ctx)
        XCTAssertEqual(result.tabataCollapses.count, 1)
        let collapse = result.tabataCollapses[0]
        XCTAssertEqual(collapse.blockIndex, 0)
        XCTAssertEqual(collapse.droppedItemCount, 1)
        XCTAssertEqual(collapse.droppedExerciseIDs, [e1])
        // Sanity: the returned state already reflects the collapse.
        XCTAssertEqual(result.state.structure.itemsPerBlock, [1])
    }
}
