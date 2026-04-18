// ActiveViewMetaLineTests.swift
//
// View-level contract for the bug-037 fix. ActiveView exposes two
// pure-swift helpers (internal, made visible by `@testable import`):
//
//   - `ActiveView.formattedMetaLine(content:restSeconds:)` — renders
//     "SET N OF M · REST …" for bounded modes and "ROUND N · REST …"
//     for unbounded modes (AMRAP passes `totalSets == 0`).
//   - `ActiveView.shouldRenderProgressPips(content:)` — gates the
//     progress-dot row on `totalSets > 0`.
//
// Swapping these into pure statics lets the bug-037 contract be
// pinned without SwiftUI snapshotting, which the repo doesn't have.
//
// Prior bug: AMRAPDriver returned `totalSets = 999` as a sentinel;
// ActiveView rendered "SET 1 OF 999" + 999 progress dots, blowing
// the layout off-screen at x = -5797. The fix: AMRAPDriver passes
// `totalSets = 0`, the view gates both the pip row and the "OF M"
// suffix on `totalSets > 0`.

import XCTest
import CoreDomain
@testable import FeaturesExecution

@MainActor
final class ActiveViewMetaLineTests: XCTestCase {

    // MARK: - Fixtures

    /// Build an `ActiveContent` with the given (setIndex, totalSets).
    /// Other fields aren't load-bearing for these tests.
    private func makeContent(
        setIndex: Int,
        totalSets: Int
    ) -> ActiveContent {
        ActiveContent(
            exerciseName: "Burpee",
            setIndex: setIndex,
            totalSets: totalSets,
            loadDisplay: "BW",
            repsDisplay: "5",
            loadKg: nil,
            reps: 5,
            adjustGlyph: nil,
            lastTime: nil
        )
    }

    // MARK: - metaLine — bounded modes

    func testMetaLineRendersSetOfTotalForBoundedModes() {
        let content = makeContent(setIndex: 2, totalSets: 4)
        let line = ActiveView.formattedMetaLine(content: content, restSeconds: 90)
        XCTAssertEqual(line, "SET 2 OF 4 · REST 1:30")
    }

    func testMetaLineRendersSetOfTotalForSingleSetItem() {
        // ContinuousDriver reports totalSets = 1 — still bounded, still
        // uses the "SET 1 OF 1" shape.
        let content = makeContent(setIndex: 1, totalSets: 1)
        let line = ActiveView.formattedMetaLine(content: content, restSeconds: 0)
        XCTAssertEqual(line, "SET 1 OF 1 · REST 0:00")
    }

    // MARK: - metaLine — unbounded (AMRAP)

    func testMetaLineCollapsesDenominatorWhenTotalSetsIsZero() {
        // Bug-037 contract: totalSets == 0 → no "OF M", render "ROUND N".
        let content = makeContent(setIndex: 1, totalSets: 0)
        let line = ActiveView.formattedMetaLine(content: content, restSeconds: 0)
        XCTAssertEqual(line, "ROUND 1 · REST 0:00")
    }

    func testMetaLineAdvancesRoundCounterAcrossRounds() {
        let content = makeContent(setIndex: 7, totalSets: 0)
        let line = ActiveView.formattedMetaLine(content: content, restSeconds: 0)
        XCTAssertEqual(line, "ROUND 7 · REST 0:00")
    }

    // MARK: - progress pips gating

    func testProgressPipsRenderForBoundedModes() {
        XCTAssertTrue(ActiveView.shouldRenderProgressPips(
            content: makeContent(setIndex: 1, totalSets: 1)
        ))
        XCTAssertTrue(ActiveView.shouldRenderProgressPips(
            content: makeContent(setIndex: 2, totalSets: 8)
        ))
        // Even a large-but-bounded count stays on the render path —
        // EMOM with total_minutes = 60 (60 rounds) is in range and the
        // layout tolerates it. Bug-037 was specifically about the
        // unbounded case.
        XCTAssertTrue(ActiveView.shouldRenderProgressPips(
            content: makeContent(setIndex: 1, totalSets: 60)
        ))
    }

    func testProgressPipsHiddenForUnboundedModes() {
        // AMRAPDriver's contract: totalSets == 0.
        XCTAssertFalse(ActiveView.shouldRenderProgressPips(
            content: makeContent(setIndex: 1, totalSets: 0)
        ))
        XCTAssertFalse(ActiveView.shouldRenderProgressPips(
            content: makeContent(setIndex: 47, totalSets: 0)
        ))
    }

    func testProgressPipsHiddenForNegativeTotalSetsDefensive() {
        // Nothing in the codebase sends negative totals, but the guard
        // is `> 0`, not `!= 0`. Pin that to keep the contract crisp.
        XCTAssertFalse(ActiveView.shouldRenderProgressPips(
            content: makeContent(setIndex: 1, totalSets: -1)
        ))
    }
}
