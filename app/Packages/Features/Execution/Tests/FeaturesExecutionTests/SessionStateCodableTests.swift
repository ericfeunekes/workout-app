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
}
