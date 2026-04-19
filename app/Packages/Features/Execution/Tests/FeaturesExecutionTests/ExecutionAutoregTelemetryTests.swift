// ExecutionAutoregTelemetryTests.swift
//
// Covers the `execution.autoreg_proposed` telemetry payload. Per
// `docs/observability-map.md` the event must carry the full
// `{item_id, set_index, proposed_load_kg, step_kg, reason}` shape; a
// prior implementation fired the event with `dataJSON == nil` and the
// analyst's queries silently dropped the row.

import XCTest
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreTelemetry
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class ExecutionAutoregTelemetryTests: XCTestCase {

    /// Log set 1 at RIR 4 on a 2-rir target → overshoot fires. The
    /// emitted event must carry every documented key and the itemID
    /// must ride through `.wireID` (lowercase).
    func testAutoregProposedEventCarriesFullPayload() throws {
        // swiftlint:disable:next force_unwrapping
        let seededItemID = UUID(uuidString: "bbbbbbbb-2222-4333-8444-555555555555")!
        let (ctx, itemID) = Self.context(itemID: seededItemID)
        let telemetry = TelemetryRecorder()
        let vm = ExecutionViewModel(context: ctx, telemetry: telemetry)
        vm.start()

        vm.logSet(reps: 5, rir: 4)

        let events = telemetry.events.filter {
            $0.name == "execution.autoreg_proposed"
        }
        XCTAssertEqual(
            events.count, 1,
            "one overshoot log should emit exactly one autoreg_proposed event"
        )
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.workoutID, ctx.workout.id)
        let payload = try XCTUnwrap(event.dataJSON)
        // Document the full set of keys — the prior regression fired
        // the event with a nil payload, so "contains the key" is what
        // we pin here. Exact formatting is JSON encoder territory.
        XCTAssertTrue(
            payload.contains("\"item_id\":\"\(itemID.uuidString.lowercased())\""),
            "payload must carry lowercase item_id; got \(payload)"
        )
        XCTAssertTrue(
            payload.contains("\"set_index\":1"),
            "payload must carry set_index; got \(payload)"
        )
        XCTAssertTrue(
            payload.contains("\"proposed_load_kg\""),
            "payload must carry proposed_load_kg; got \(payload)"
        )
        XCTAssertTrue(
            payload.contains("\"step_kg\""),
            "payload must carry step_kg; got \(payload)"
        )
        XCTAssertTrue(
            payload.contains("\"reason\":\"overshoot\""),
            "payload must carry canonical `overshoot` reason; got \(payload)"
        )
        // step_kg should equal the autoreg overshoot step (R2.10
        // unit-aware default: 5.0 for the lb/no-unit fixture, which
        // is the US-gym smallest loadable plate pair). proposed = 100
        // + 5 = 105.
        XCTAssertTrue(
            payload.contains("\"step_kg\":5"),
            "step_kg must derive from |proposed - prescribed|; got \(payload)"
        )
        XCTAssertTrue(
            payload.contains("\"proposed_load_kg\":105"),
            "proposed_load_kg must equal prescribed + overshoot step; got \(payload)"
        )
    }

    /// Undershoot path — same shape contract, different `reason` token.
    /// Guards that the switch in `autoregReasonToken` stays in lockstep
    /// with the `AutoregProposal.Reason` cases.
    func testAutoregProposedPayloadForUndershootCarriesReason() throws {
        let (ctx, _) = Self.context(reps: 8, targetRir: 2)
        let telemetry = TelemetryRecorder()
        let vm = ExecutionViewModel(context: ctx, telemetry: telemetry)
        vm.start()

        // Logged 6 vs prescribed 8 → undershoot-reps.
        vm.logSet(reps: 6, rir: 1)

        let event = try XCTUnwrap(
            telemetry.events.first { $0.name == "execution.autoreg_proposed" }
        )
        let payload = try XCTUnwrap(event.dataJSON)
        XCTAssertTrue(
            payload.contains("\"reason\":\"undershoot_reps\""),
            "undershoot must carry `undershoot_reps` reason token; got \(payload)"
        )
    }

    /// No proposal → no event. Prevents a regression where the emit
    /// path unconditionally fires.
    func testNoAutoregProposedEventWhenNoProposal() {
        let (ctx, _) = Self.context(targetRir: 2)
        let telemetry = TelemetryRecorder()
        let vm = ExecutionViewModel(context: ctx, telemetry: telemetry)
        vm.start()

        // RIR 2 == target, no overshoot, no undershoot → no proposal.
        vm.logSet(reps: 5, rir: 2)

        let events = telemetry.events.filter {
            $0.name == "execution.autoreg_proposed"
        }
        XCTAssertTrue(
            events.isEmpty,
            "no proposal means no event; got \(events.count) events"
        )
    }

    // MARK: - Fixtures

    /// Straight-sets context sized to trigger the overshoot path on
    /// RIR 4 / target 2. Default prescription: 4 sets × 5 reps @ 100 kg
    /// with default autoreg thresholds (`overshoot_at=2`,
    /// `overshoot_step_kg=2.5`).
    static func context(
        sets: Int = 4,
        reps: Int = 5,
        loadKg: Double = 100,
        targetRir: Int = 2,
        itemID: UUID = UUID()
    ) -> (WorkoutContext, UUID) {
        let userID = UUID()
        let workoutID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let now = Date()

        let workout = Workout(
            id: workoutID, userID: userID, name: "AutoregTel",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .straightSets,
            timingConfigJSON:
                #"{"rest_between_sets_sec":60,"rest_between_exercises_sec":60}"#,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        let item = WorkoutItem(
            id: itemID, blockID: blockID, position: 0,
            exerciseID: exerciseID,
            prescriptionJSON:
                #"{"sets":\#(sets),"reps":\#(reps),"load_kg":\#(loadKg),"target_rir":\#(targetRir),"autoreg":{}}"#
        )
        let ctx = WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [[item]],
            exercises: [exerciseID: Exercise(id: exerciseID, name: "Bench")],
            lastPerformed: [:]
        )
        return (ctx, itemID)
    }
}
