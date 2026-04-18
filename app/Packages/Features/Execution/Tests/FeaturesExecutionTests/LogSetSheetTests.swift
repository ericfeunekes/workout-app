// LogSetSheetTests.swift
//
// Unit tests for `LogSetSheetModel` — the state-and-commit controller
// behind the combined reps + RIR sheet (bug-023 fix). SwiftUI view
// rendering is not exercised; the model is the testable surface.
//
// Contract under test:
//   - Prime seeds the buffer with prescribed reps exactly once.
//   - Commit with RIR untouched fires `onCommit(reps: primed, rir: nil)`.
//   - Commit after tapping a RIR button fires
//     `onCommit(reps: primed, rir: picked)`.
//   - Tapping the already-picked RIR clears it (toggle to nil).
//   - Buffer edits (digit / delete) track the NumPad semantics.

import XCTest
@testable import FeaturesExecution

@MainActor
final class LogSetSheetTests: XCTestCase {

    // MARK: - Helpers

    /// Recorder for the `onCommit` callback. Tests inspect `lastReps` /
    /// `lastRir` / `callCount` after driving the model.
    private final class Recorder {
        var callCount = 0
        var lastReps: Int?
        var lastRir: Int?

        func receive(reps: Int, rir: Int?) {
            callCount += 1
            lastReps = reps
            lastRir = rir
        }
    }

    /// Build a primed model + its recorder. `prime()` is called so tests
    /// see the seeded buffer state (mirrors the SwiftUI view's onAppear).
    private func makePrimedModel(
        initialReps: Int = 5
    ) -> (LogSetSheetModel, Recorder) {
        let rec = Recorder()
        let model = LogSetSheetModel(initialReps: initialReps) { reps, rir in
            rec.receive(reps: reps, rir: rir)
        }
        model.prime()
        return (model, rec)
    }

    // MARK: - Priming

    func testPrimeSeedsBufferWithInitialReps() {
        let (model, _) = makePrimedModel(initialReps: 5)
        XCTAssertEqual(model.buffer, "5")
        XCTAssertEqual(model.displayBuffer, "5")
        XCTAssertNil(model.pickedRir)
    }

    func testPrimeIsIdempotent() {
        let (model, _) = makePrimedModel(initialReps: 5)
        model.pressDigit(8)  // buffer becomes "58"
        model.prime()        // second prime is a no-op
        XCTAssertEqual(model.buffer, "58")
    }

    // MARK: - Commit with RIR untouched

    func testCommitWithRirUntouchedFiresNilRir() {
        let (model, rec) = makePrimedModel(initialReps: 5)
        model.commit()
        XCTAssertEqual(rec.callCount, 1)
        XCTAssertEqual(rec.lastReps, 5)
        XCTAssertNil(rec.lastRir)
    }

    func testCommitAfterEditingRepsFiresEditedReps() {
        let (model, rec) = makePrimedModel(initialReps: 5)
        // User wants 7 — press delete then 7.
        model.pressDelete()
        XCTAssertEqual(model.buffer, "0")  // NumPad parity: empty reverts to "0"
        model.pressDigit(7)
        XCTAssertEqual(model.buffer, "7")
        model.commit()
        XCTAssertEqual(rec.lastReps, 7)
        XCTAssertNil(rec.lastRir)
    }

    // MARK: - Commit with RIR picked

    func testCommitAfterPickingRirFiresBoth() {
        let (model, rec) = makePrimedModel(initialReps: 5)
        model.pressRir(2)
        XCTAssertEqual(model.pickedRir, 2)
        model.commit()
        XCTAssertEqual(rec.callCount, 1)
        XCTAssertEqual(rec.lastReps, 5)
        XCTAssertEqual(rec.lastRir, 2)
    }

    func testPickingDifferentRirReplacesPrevious() {
        let (model, rec) = makePrimedModel(initialReps: 5)
        model.pressRir(2)
        model.pressRir(4)
        model.commit()
        XCTAssertEqual(rec.lastRir, 4)
    }

    func testTappingSameRirClearsIt() {
        let (model, rec) = makePrimedModel(initialReps: 5)
        model.pressRir(3)
        XCTAssertEqual(model.pickedRir, 3)
        model.pressRir(3)  // toggle off
        XCTAssertNil(model.pickedRir)
        model.commit()
        XCTAssertNil(rec.lastRir)
    }

    // MARK: - Buffer semantics (NumPad parity)

    func testPressDigitAppendsAfterPrimedBuffer() {
        let (model, _) = makePrimedModel(initialReps: 5)
        model.pressDigit(2)
        XCTAssertEqual(model.buffer, "52")
    }

    func testPressDigitOverwritesZeroFirstSlot() {
        let rec = Recorder()
        let model = LogSetSheetModel(initialReps: 0) { reps, rir in
            rec.receive(reps: reps, rir: rir)
        }
        model.prime()
        XCTAssertEqual(model.buffer, "0")
        model.pressDigit(7)
        XCTAssertEqual(model.buffer, "7")
    }

    func testCommitWithUnparseableBufferFallsBackToInitialReps() {
        let rec = Recorder()
        let model = LogSetSheetModel(initialReps: 8) { reps, rir in
            rec.receive(reps: reps, rir: rir)
        }
        // Skip prime, then delete the empty buffer so it's "" (edge case).
        // An empty buffer parses to nil; commit should fall back to
        // initialReps (NumPad-style safety).
        model.pressDelete()  // no-op on empty
        model.commit()
        XCTAssertEqual(rec.lastReps, 8)
    }
}
