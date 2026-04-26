// SessionStateCodableTests.swift
//
// Regression for the `advancementByBlock` decode path. The earlier shape
// used `compactMap(SessionState.BlockAdvancement.init(rawValue:))`, which
// silently dropped unknown raw values. A future enum case (e.g. a V3
// advancement mode) landing on a phone still running an older build
// would drop that entry entirely — the remaining policies shifted onto
// earlier block indices, corrupting round-robin / set-major alignment
// for every block after the unknown one.
//
// Post-fix: decode throws on unknown raw values AND on a count mismatch
// between `advancementByBlock` and `itemsPerBlock`. `restoreIfPossible`
// catches the throw and routes down the "no saved state" path, forcing
// the session to re-seed from the pulled workout rather than silently
// mis-advancing.

import XCTest
import CoreAutoreg
import CoreDomain
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

final class SessionStateCodableTests: XCTestCase {

    func testAdvancementByBlockRejectsUnknownRawValue() throws {
        // Encode a known-good payload, then splice an invented rawValue
        // into `advancementByBlock`. The decode path must throw rather
        // than silently dropping the unknown entry and leaving a shorter
        // array that shifts later policies onto earlier indices.
        let state = SessionState(
            workoutID: UUID(),
            route: .today,
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
            items: [
                SessionState.ItemLog(
                    itemID: UUID(),
                    sets: [SetPlan(setIndex: 1, loadKg: 100, reps: 5, done: false, adjust: nil)]
                ),
                SessionState.ItemLog(
                    itemID: UUID(),
                    sets: [SetPlan(setIndex: 1, loadKg: 60, reps: 8, done: false, adjust: nil)]
                ),
            ],
            note: "",
            structure: SessionState.Structure(
                itemsPerBlock: [1, 1],
                setsPerItem: [[1], [1]],
                advancementByBlock: [.setMajor, .roundRobin]
            )
        )
        let encoded = try JSONEncoder().encode(SessionStateCodable(state: state))
        guard var dict = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            XCTFail("expected encoded payload to be a JSON object")
            return
        }
        guard var structureDict = dict["structure"] as? [String: Any] else {
            XCTFail("expected structure field in payload")
            return
        }
        // Splice an invented rawValue in position 1 — the valid shape is
        // ["setMajor", "roundRobin"]; we corrupt it so a future V3 case
        // landing on an older build surfaces as the same input shape.
        structureDict["advancementByBlock"] = ["setMajor", "futureMode_V3"]
        dict["structure"] = structureDict
        let tampered = try JSONSerialization.data(withJSONObject: dict)

        XCTAssertThrowsError(
            try JSONDecoder().decode(SessionStateCodable.self, from: tampered),
            "unknown BlockAdvancement rawValue must fail decode, not silent-drop"
        )
    }

    func testAdvancementByBlockRejectsCountMismatch() throws {
        // Count mismatch is a second failure mode — a shorter policy
        // array would shift every policy onto an earlier block index.
        // Even if every rawValue is known, the decoder must reject a
        // payload where the count disagrees with `itemsPerBlock`.
        let state = SessionState(
            workoutID: UUID(),
            route: .today,
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
            items: [
                SessionState.ItemLog(
                    itemID: UUID(),
                    sets: [SetPlan(setIndex: 1, loadKg: 100, reps: 5, done: false, adjust: nil)]
                ),
                SessionState.ItemLog(
                    itemID: UUID(),
                    sets: [SetPlan(setIndex: 1, loadKg: 60, reps: 8, done: false, adjust: nil)]
                ),
            ],
            note: "",
            structure: SessionState.Structure(
                itemsPerBlock: [1, 1],
                setsPerItem: [[1], [1]],
                advancementByBlock: [.setMajor, .roundRobin]
            )
        )
        let encoded = try JSONEncoder().encode(SessionStateCodable(state: state))
        guard var dict = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            XCTFail("expected encoded payload to be a JSON object")
            return
        }
        guard var structureDict = dict["structure"] as? [String: Any] else {
            XCTFail("expected structure field in payload")
            return
        }
        // Valid rawValues but too few — 1 policy for 2 blocks.
        structureDict["advancementByBlock"] = ["setMajor"]
        dict["structure"] = structureDict
        let tampered = try JSONSerialization.data(withJSONObject: dict)

        XCTAssertThrowsError(
            try JSONDecoder().decode(SessionStateCodable.self, from: tampered),
            "count mismatch between advancementByBlock and itemsPerBlock must fail decode"
        )
    }

    func testAdvancementByBlockMissingFieldFallsBackToStructureDefault() throws {
        // Back-compat: payloads persisted before the field existed have
        // no `advancementByBlock` key. Those still decode cleanly — the
        // `Structure` init derives the default (zero-item → `.zeroItem`,
        // everything else → `.setMajor`). This pins the back-compat path
        // so it stays distinct from the unknown-rawValue reject path.
        let state = SessionState(
            workoutID: UUID(),
            route: .today,
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
            items: [
                SessionState.ItemLog(
                    itemID: UUID(),
                    sets: [SetPlan(setIndex: 1, loadKg: 100, reps: 5, done: false, adjust: nil)]
                ),
            ],
            note: "",
            structure: SessionState.Structure(
                itemsPerBlock: [1],
                setsPerItem: [[1]],
                advancementByBlock: [.setMajor]
            )
        )
        let encoded = try JSONEncoder().encode(SessionStateCodable(state: state))
        guard var dict = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            XCTFail("expected encoded payload to be a JSON object")
            return
        }
        guard var structureDict = dict["structure"] as? [String: Any] else {
            XCTFail("expected structure field in payload")
            return
        }
        structureDict.removeValue(forKey: "advancementByBlock")
        dict["structure"] = structureDict
        let stripped = try JSONSerialization.data(withJSONObject: dict)

        let decoded = try JSONDecoder().decode(SessionStateCodable.self, from: stripped)
        XCTAssertEqual(decoded.state.structure.advancementByBlock, [.setMajor])
    }

    func testSetPlanSkipAndSideRoundTrip() throws {
        let itemID = UUID()
        let stamp = Date(timeIntervalSince1970: 1_700_030_000)
        let state = SessionState(
            workoutID: UUID(),
            route: .rest,
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
            items: [
                SessionState.ItemLog(
                    itemID: itemID,
                    sets: [
                        SetPlan(
                            setIndex: 1,
                            loadKg: 100,
                            reps: 5,
                            done: true,
                            adjust: nil,
                            completedAt: stamp,
                            skipped: true,
                            side: .left
                        ),
                    ]
                ),
            ],
            note: "",
            structure: SessionState.Structure(itemsPerBlock: [1], setsPerItem: [[1]])
        )

        let encoded = try JSONEncoder().encode(SessionStateCodable(state: state))
        let decoded = try JSONDecoder().decode(SessionStateCodable.self, from: encoded).state
        let set = try XCTUnwrap(decoded.items.first?.sets.first)
        XCTAssertTrue(set.skipped)
        XCTAssertEqual(set.side, .left)
    }

    func testCompositeSetPhaseRoundTripsWorkingAndIntraRest() throws {
        let itemID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_700_020_000)
        let endsAt = startedAt.addingTimeInterval(15)
        let state = makeCompositeState(
            itemID: itemID,
            compositeSets: [
                SessionState.CompositeSetProgress(
                    itemID: itemID,
                    setIndex: 1,
                    kind: .cluster,
                    targetRepsPerSlot: 5,
                    slotCount: 2,
                    intraRestSec: 15,
                    firstStartedAt: startedAt,
                    phase: .working(slotIndex: 1, startedAt: startedAt),
                    completedSlots: 0
                ),
                SessionState.CompositeSetProgress(
                    itemID: itemID,
                    setIndex: 2,
                    kind: .cluster,
                    targetRepsPerSlot: 5,
                    slotCount: 2,
                    intraRestSec: 15,
                    phase: .intraRest(afterSlotIndex: 1, endsAt: endsAt),
                    completedSlots: 1
                ),
            ]
        )

        let encoded = try JSONEncoder().encode(SessionStateCodable(state: state))
        let decoded = try JSONDecoder().decode(SessionStateCodable.self, from: encoded).state

        XCTAssertEqual(decoded.compositeSets.count, 2)
        XCTAssertEqual(decoded.compositeSets[0].phase, .working(slotIndex: 1, startedAt: startedAt))
        XCTAssertEqual(decoded.compositeSets[1].phase, .intraRest(afterSlotIndex: 1, endsAt: endsAt))
    }

    func testCompositeSetPhaseRejectsMissingRequiredFields() throws {
        let itemID = UUID()
        let state = makeCompositeState(
            itemID: itemID,
            compositeSets: [
                SessionState.CompositeSetProgress(
                    itemID: itemID,
                    setIndex: 1,
                    kind: .cluster,
                    targetRepsPerSlot: 5,
                    slotCount: 2,
                    intraRestSec: 15,
                    phase: .working(slotIndex: 1, startedAt: Date(timeIntervalSince1970: 1_700_020_000))
                ),
            ]
        )
        let encoded = try JSONEncoder().encode(SessionStateCodable(state: state))
        guard var dict = try JSONSerialization.jsonObject(with: encoded) as? [String: Any],
              var compositeSets = dict["compositeSets"] as? [[String: Any]],
              var first = compositeSets.first,
              var phase = first["phase"] as? [String: Any] else {
            XCTFail("expected compositeSets payload")
            return
        }
        phase.removeValue(forKey: "startedAt")
        first["phase"] = phase
        compositeSets[0] = first
        dict["compositeSets"] = compositeSets
        let tampered = try JSONSerialization.data(withJSONObject: dict)

        XCTAssertThrowsError(
            try JSONDecoder().decode(SessionStateCodable.self, from: tampered),
            "working phase without startedAt must fail decode, not restore from Unix epoch"
        )
    }

    private func makeCompositeState(
        itemID: UUID,
        compositeSets: [SessionState.CompositeSetProgress]
    ) -> SessionState {
        SessionState(
            workoutID: UUID(),
            route: .active,
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
            items: [
                SessionState.ItemLog(
                    itemID: itemID,
                    sets: [
                        SetPlan(setIndex: 1, loadKg: 100, reps: 10, done: false, adjust: nil),
                        SetPlan(setIndex: 2, loadKg: 100, reps: 10, done: false, adjust: nil),
                    ]
                ),
            ],
            compositeSets: compositeSets,
            note: "",
            structure: SessionState.Structure(
                itemsPerBlock: [1],
                setsPerItem: [[2]],
                advancementByBlock: [.setMajor]
            )
        )
    }
}
