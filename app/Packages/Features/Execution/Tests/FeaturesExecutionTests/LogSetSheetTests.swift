// LogSetSheetTests.swift
//
// Unit tests for the row-based strength logger model. The sheet exposes
// load, reps, and RIR as compact cells; the keypad only edits the selected
// numeric field.

import XCTest
@testable import FeaturesExecution

@MainActor
final class LogSetSheetTests: XCTestCase {

    private final class Recorder {
        var callCount = 0
        var lastLoad: Double?
        var lastReps: Int?
        var lastRir: Int?

        func receive(load: Double?, reps: Int, rir: Int?) {
            callCount += 1
            lastLoad = load
            lastReps = reps
            lastRir = rir
        }
    }

    private func makePrimedModel(
        initialLoad: Double? = 100,
        loadUnit: String? = "lb",
        initialReps: Int = 5
    ) -> (LogSetSheetModel, Recorder) {
        let rec = Recorder()
        let model = LogSetSheetModel(
            initialLoad: initialLoad,
            loadUnit: loadUnit,
            initialReps: initialReps
        ) { load, reps, rir in
            rec.receive(load: load, reps: reps, rir: rir)
        }
        model.prime()
        return (model, rec)
    }

    func testPrimeSeedsRowsWithoutOpeningKeypad() {
        let (model, _) = makePrimedModel(initialLoad: 102.5, loadUnit: "kg", initialReps: 8)

        XCTAssertEqual(model.loadBuffer, "102.5")
        XCTAssertEqual(model.loadDisplay, "102.5 kg")
        XCTAssertEqual(model.repsBuffer, "8")
        XCTAssertEqual(model.repsDisplay, "8")
        XCTAssertNil(model.pickedRir)
        XCTAssertNil(model.selectedField)
        XCTAssertFalse(model.showsKeypad)
    }

    func testCommitWithoutEditsFiresSeededLoadRepsAndNilRir() {
        let (model, rec) = makePrimedModel(initialLoad: 100, loadUnit: "lb", initialReps: 5)

        model.commit()

        XCTAssertEqual(rec.callCount, 1)
        XCTAssertEqual(rec.lastLoad, 100)
        XCTAssertEqual(rec.lastReps, 5)
        XCTAssertNil(rec.lastRir)
    }

    func testEditingRepsOnlyUpdatesReps() {
        let (model, rec) = makePrimedModel(initialLoad: 100, initialReps: 5)

        model.select(.reps)
        model.pressDelete()
        XCTAssertEqual(model.repsBuffer, "0")
        model.pressDigit(7)
        model.commit()

        XCTAssertEqual(rec.lastLoad, 100)
        XCTAssertEqual(rec.lastReps, 7)
    }

    func testFirstDigitAfterSelectingFieldReplacesPrefill() {
        let (model, rec) = makePrimedModel(initialLoad: 28, loadUnit: "kg", initialReps: 8)

        model.select(.load)
        model.pressDigit(3)
        model.pressDigit(0)
        model.select(.reps)
        model.pressDigit(6)
        model.commit()

        XCTAssertEqual(rec.lastLoad, 30)
        XCTAssertEqual(rec.lastReps, 6)
    }

    func testEditingLoadSupportsDecimalAndPreservesReps() {
        let (model, rec) = makePrimedModel(initialLoad: 100, loadUnit: "lb", initialReps: 5)

        model.select(.load)
        model.pressDelete()
        model.pressDelete()
        model.pressDelete()
        XCTAssertEqual(model.loadBuffer, "0")
        model.pressDigit(9)
        model.pressDecimal()
        model.pressDigit(5)
        model.commit()

        XCTAssertEqual(rec.lastLoad, 9.5)
        XCTAssertEqual(rec.lastReps, 5)
    }

    func testDecimalIsIgnoredForReps() {
        let (model, _) = makePrimedModel(initialReps: 5)

        model.select(.reps)
        model.pressDecimal()

        XCTAssertEqual(model.repsBuffer, "5")
        XCTAssertFalse(model.keypadAllowsDecimal)
    }

    func testRirSelectionCommitsWithLoadAndReps() {
        let (model, rec) = makePrimedModel(initialLoad: 100, initialReps: 5)

        model.pressRir(2)
        model.commit()

        XCTAssertEqual(rec.lastLoad, 100)
        XCTAssertEqual(rec.lastReps, 5)
        XCTAssertEqual(rec.lastRir, 2)
    }

    func testTappingSameRirClearsIt() {
        let (model, rec) = makePrimedModel()

        model.pressRir(3)
        XCTAssertEqual(model.pickedRir, 3)
        model.pressRir(3)
        XCTAssertNil(model.pickedRir)
        model.commit()

        XCTAssertNil(rec.lastRir)
    }

    func testBodyweightRowsDoNotExposeLoadEditing() {
        let (model, rec) = makePrimedModel(initialLoad: nil, loadUnit: nil, initialReps: 12)

        XCTAssertEqual(model.loadDisplay, "BW")
        model.select(.load)
        XCTAssertNil(model.selectedField)
        model.commit()

        XCTAssertNil(rec.lastLoad)
        XCTAssertEqual(rec.lastReps, 12)
    }

    func testPrimeIsIdempotent() {
        let (model, _) = makePrimedModel(initialLoad: 100, initialReps: 5)

        model.select(.reps)
        model.pressDigit(8)
        model.prime()

        XCTAssertEqual(model.repsBuffer, "8")
        XCTAssertEqual(model.loadBuffer, "100")
    }
}
