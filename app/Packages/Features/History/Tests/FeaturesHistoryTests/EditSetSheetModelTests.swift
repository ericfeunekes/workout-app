// EditSetSheetModelTests.swift
//
// Unit tests for the History corrective-edit sheet model. Drives the
// model directly rather than through ViewInspector — the commit
// contract (what `onCommit` emits for reps / rir / load given the user's
// taps) is where the hazards live. The view is a thin wrapper over
// these hooks.
//
// Coverage (one test per bug):
//   • testEditSheetLabelMatchesWeightUnit — load tile label flips
//     between "LOAD KG" and "LOAD LB" based on the prefilled SetLog's
//     `weightUnit`. Prevents the original bug where every row labeled
//     "LOAD KG" regardless of the row's actual unit.
//   • testEditPreservesWeightUnit — committing a load edit returns a
//     `LoadCommit` that carries the original unit. The sheet never
//     silently converts or stamps `.kg`.
//   • testEditSheetOmitsSideFromCommitWhileStillEmittingOtherFields —
//     History no longer authors `set_log.side` from this sheet.
//   • testEditSheetCanClearRir — the "clear" affordance zeroes out the
//     RIR selection and commits as `.clear`, distinct from "untouched".
//   • testEditSheetCapsRepsAt999 — typing "1000" leaves the buffer at
//     "999" (the fourth digit is rejected silently).

import XCTest
import CoreDomain
import DesignSystem
@testable import FeaturesHistory

@MainActor
final class EditSetSheetModelTests: XCTestCase {

    // MARK: - Weight unit labeling

    func testEditSheetLabelMatchesWeightUnit() {
        // Seeded in lb → the tile label must read "LOAD LB", not
        // "LOAD KG". The original bug hardcoded "LOAD KG" everywhere,
        // so a lb-stored row would mislabel its own content.
        let lbModel = makeModel(weightUnit: .lb)
        XCTAssertEqual(lbModel.loadLabel, "LOAD LB")

        // Seeded in kg → "LOAD KG".
        let kgModel = makeModel(weightUnit: .kg)
        XCTAssertEqual(kgModel.loadLabel, "LOAD KG")
    }

    // MARK: - Weight-unit preservation on commit

    func testEditPreservesWeightUnit() {
        // Seed a SetLog recorded in lb. The user edits the load to 100
        // and commits. The emitted LoadCommit MUST carry `.lb` as the
        // unit — not `.kg`. Downstream, HistoryViewModel.editPastSet
        // writes `weightUnit = commit.unit` verbatim onto the SetLog,
        // so this is the only safety net between the user's intent and
        // the persisted row.
        var captured: SetEditIntent?
        let model = EditSetSheetModel(
            setIndex: 1,
            initialReps: 5,
            initialRir: 2,
            initialLoad: 45,
            initialDurationSec: nil,
            initialDistanceM: nil,
            initialSkipped: false,
            initialSide: .bilateral,
            initialNotes: nil,
            weightUnit: .lb,
            onCommit: { intent in captured = intent }
        )
        model.selectField(.load)
        // User clears the prefill and types "100".
        model.pressDelete() // "4"
        model.pressDelete() // ""
        model.pressDigit(1)
        model.pressDigit(0)
        model.pressDigit(0)
        model.commit()

        let commit = try? XCTUnwrap(captured)
        XCTAssertEqual(commit?.load, 100)
        XCTAssertEqual(commit?.loadUnit, "lb",
                       "commit must preserve the unit the SetLog was recorded in")
    }

    // MARK: - RIR clear

    func testEditSheetCanClearRir() {
        // Seed a SetLog that already has RIR = 3. The user taps the
        // clear affordance. The commit must emit `.clear`, not
        // `.preserve` (which would leave the existing 3 intact) and not
        // `.set(nil)` (which the enum doesn't allow). Ensures the
        // edit sheet can zero out a stale RIR value.
        var captured: SetEditIntent?
        let model = EditSetSheetModel(
            setIndex: 1,
            initialReps: 5,
            initialRir: 3,
            initialLoad: 100,
            initialDurationSec: nil,
            initialDistanceM: nil,
            initialSkipped: false,
            initialSide: .bilateral,
            initialNotes: nil,
            weightUnit: .kg,
            onCommit: { intent in captured = intent }
        )
        model.clearRir()
        model.commit()

        XCTAssertEqual(captured?.rir, .clear,
                       "clearRir + commit must emit .clear so editPastSet writes nil")
    }

    func testEditSheetRirUntouchedStaysPreserve() {
        // Belt-and-braces companion: if the user never touches the RIR
        // row, the commit must emit `.preserve`. Otherwise every edit
        // would overwrite RIR with nil, destroying data.
        var captured: SetEditIntent?
        let model = EditSetSheetModel(
            setIndex: 1,
            initialReps: 5,
            initialRir: 3,
            initialLoad: 100,
            initialDurationSec: nil,
            initialDistanceM: nil,
            initialSkipped: false,
            initialSide: .bilateral,
            initialNotes: nil,
            weightUnit: .kg,
            onCommit: { intent in captured = intent }
        )
        model.commit()
        XCTAssertEqual(captured?.rir, .preserve)
    }

    // MARK: - Reps cap

    func testEditSheetCapsRepsAt999() {
        // Typing "1000" on the reps field must leave the buffer at
        // "999" — the fourth digit is rejected silently so the buffer
        // doesn't visually mislead the user. Cap matches
        // `EditSetSheetModel.maxReps`.
        let model = makeModel(weightUnit: .kg)
        model.selectField(.reps)
        // Buffer starts empty, prefill shows placeholder.
        model.pressDigit(1)
        model.pressDigit(0)
        model.pressDigit(0)
        model.pressDigit(0) // this one must be rejected
        XCTAssertEqual(model.repsBuffer, "100",
                       "fourth digit '0' would make 1000 — rejected, buffer stays at '100'")

        // Type directly the largest legal 3-digit: 999.
        model.pressDelete()
        model.pressDelete()
        model.pressDelete()
        XCTAssertEqual(model.repsBuffer, "")
        model.pressDigit(9)
        model.pressDigit(9)
        model.pressDigit(9)
        XCTAssertEqual(model.repsBuffer, "999")
        // One more digit is rejected.
        model.pressDigit(0)
        XCTAssertEqual(model.repsBuffer, "999",
                       "digits past the 999 cap must be no-ops")
    }

    func testEditSheetOmitsSideFromCommitWhileStillEmittingOtherFields() {
        var captured: SetEditIntent?
        let model = EditSetSheetModel(
            setIndex: 1,
            initialReps: nil,
            initialRir: nil,
            initialLoad: nil,
            initialDurationSec: nil,
            initialDistanceM: nil,
            initialSkipped: false,
            initialSide: .bilateral,
            initialNotes: nil,
            weightUnit: .kg,
            onCommit: { intent in captured = intent }
        )

        model.selectField(.duration)
        model.pressDigit(7)
        model.pressDigit(5)
        model.selectField(.distance)
        model.pressDigit(4)
        model.pressDigit(0)
        model.pressDigit(0)
        model.setSkipped(true)
        model.setNotes("missed by watch")
        model.commit()

        XCTAssertEqual(captured?.durationSeconds, 75)
        XCTAssertEqual(captured?.distance, 400)
        XCTAssertEqual(captured?.distanceUnit, "m")
        XCTAssertEqual(captured?.skipped, true)
        XCTAssertNil(captured?.side)
        XCTAssertEqual(captured?.notes, .set("missed by watch"))
    }

    func testUnskipWithoutMetricsShowsValidationErrorAndDoesNotCommit() {
        var captured: SetEditIntent?
        let model = EditSetSheetModel(
            setIndex: 1,
            initialReps: nil,
            initialRir: nil,
            initialLoad: nil,
            initialDurationSec: nil,
            initialDistanceM: nil,
            initialSkipped: true,
            initialSide: .bilateral,
            initialNotes: nil,
            weightUnit: .lb,
            onCommit: { intent in captured = intent }
        )

        model.setSkipped(false)
        model.commit()

        XCTAssertNil(captured)
        XCTAssertEqual(
            model.validationMessage,
            "add at least one metric before marking performed"
        )
    }

    // MARK: - Helpers

    private func makeModel(weightUnit: WeightUnit) -> EditSetSheetModel {
        EditSetSheetModel(
            setIndex: 1,
            initialReps: 5,
            initialRir: nil,
            initialLoad: 100,
            initialDurationSec: nil,
            initialDistanceM: nil,
            initialSkipped: false,
            initialSide: .bilateral,
            initialNotes: nil,
            weightUnit: weightUnit,
            onCommit: { _ in }
        )
    }
}
