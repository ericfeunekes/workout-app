// ActiveViewMetaLineTests.swift
//
// View-level contract for the bug-037 fix. ActiveView exposes two
// pure-swift helpers (internal, made visible by `@testable import`):
//
//   - `ActiveView.formattedMetaLine(content:timingMode:)` — renders
//     mode-native metadata ("SET", "ROUND", "INTERVAL", etc.) while
//     preserving the unbounded AMRAP contract.
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
        let line = ActiveView.formattedMetaLine(content: content)
        XCTAssertEqual(line, "SET 2 OF 4")
    }

    func testMetaLineRendersContinuousForContinuousMode() {
        let content = makeContent(setIndex: 1, totalSets: 1)
        let line = ActiveView.formattedMetaLine(content: content, timingMode: .continuous)
        XCTAssertEqual(line, "CONTINUOUS")
    }

    func testMetaLineRendersIntervalForIntervalModes() {
        let content = makeContent(setIndex: 2, totalSets: 6)

        XCTAssertEqual(
            ActiveView.formattedMetaLine(content: content, timingMode: .emom),
            "INTERVAL 2 OF 6"
        )
        XCTAssertEqual(
            ActiveView.formattedMetaLine(content: content, timingMode: .intervals),
            "INTERVAL 2 OF 6"
        )
    }

    func testMetaLineRendersRoundForRoundBasedModes() {
        let content = makeContent(setIndex: 2, totalSets: 8)

        XCTAssertEqual(
            ActiveView.formattedMetaLine(content: content, timingMode: .tabata),
            "ROUND 2 OF 8"
        )
        XCTAssertEqual(
            ActiveView.formattedMetaLine(content: content, timingMode: .forTime),
            "ROUND 2 OF 8"
        )
    }

    // MARK: - metaLine — unbounded (AMRAP)

    func testMetaLineCollapsesDenominatorWhenTotalSetsIsZero() {
        // Bug-037 contract: totalSets == 0 → no "OF M", render "ROUND N".
        let content = makeContent(setIndex: 1, totalSets: 0)
        let line = ActiveView.formattedMetaLine(content: content)
        XCTAssertEqual(line, "ROUND 1")
    }

    func testMetaLineAdvancesRoundCounterAcrossRounds() {
        let content = makeContent(setIndex: 7, totalSets: 0)
        let line = ActiveView.formattedMetaLine(content: content)
        XCTAssertEqual(line, "ROUND 7")
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

    // MARK: - block progress strip

    func testBlockProgressStripRendersOnlyWhenBounded() {
        let bounded = BlockProgressPresentation(
            blockIndex: 0,
            blockCount: 2,
            blockName: "Upper",
            blockIntent: nil,
            completedSets: 1,
            totalSets: 6
        )
        let unbounded = BlockProgressPresentation(
            blockIndex: 0,
            blockCount: 2,
            blockName: "AMRAP",
            blockIntent: nil,
            completedSets: 0,
            totalSets: 0
        )

        XCTAssertTrue(ActiveView.shouldRenderBlockProgress(bounded))
        XCTAssertFalse(ActiveView.shouldRenderBlockProgress(unbounded))
        XCTAssertFalse(ActiveView.shouldRenderBlockProgress(nil))
    }

    func testBlockProgressSummaryUsesCompletedOverTotal() {
        let progress = BlockProgressPresentation(
            blockIndex: 0,
            blockCount: 1,
            blockName: nil,
            blockIntent: nil,
            completedSets: 2,
            totalSets: 8
        )
        let malformed = BlockProgressPresentation(
            blockIndex: 0,
            blockCount: 1,
            blockName: nil,
            blockIntent: nil,
            completedSets: -1,
            totalSets: -8
        )

        XCTAssertEqual(ActiveView.blockProgressSummary(progress), "2 / 8 DONE")
        XCTAssertEqual(ActiveView.blockProgressSummary(malformed), "0 / 0 DONE")
    }

    // MARK: - block timer ticking

    func testTimerTicksWhenAnyBlockTimerIsRunning() {
        let now = Date()

        XCTAssertTrue(ActiveView.shouldTickBlockTimer(
            blockEndsAt: now.addingTimeInterval(30),
            workEndsAt: nil,
            isMetconResultSheetPresented: false
        ))
        XCTAssertTrue(ActiveView.shouldTickBlockTimer(
            blockEndsAt: nil,
            workEndsAt: now.addingTimeInterval(20),
            isMetconResultSheetPresented: false
        ))
    }

    func testMetconResultSheetSuppressesCapTickWhileScoreIsBeingEntered() {
        let now = Date()

        XCTAssertFalse(ActiveView.shouldTickBlockTimer(
            blockEndsAt: now.addingTimeInterval(-1),
            workEndsAt: nil,
            isMetconResultSheetPresented: true
        ))
    }

    func testTimerProgressionIsNotPausedByUnrelatedPresentation() {
        let now = Date()

        XCTAssertTrue(ActiveView.shouldTickBlockTimer(
            blockEndsAt: now.addingTimeInterval(-1),
            workEndsAt: nil,
            isMetconResultSheetPresented: false
        ))
        XCTAssertTrue(ActiveView.shouldPresentAMRAPResultSheet(
            timingMode: .amrap,
            blockEndsAt: now.addingTimeInterval(-1),
            now: now,
            isMetconResultSheetPresented: false
        ))
    }

    func testAMRAPCapPresentsResultSheetInsteadOfAutoCompleting() {
        let now = Date()

        XCTAssertTrue(ActiveView.shouldPresentAMRAPResultSheet(
            timingMode: .amrap,
            blockEndsAt: now.addingTimeInterval(-1),
            now: now,
            isMetconResultSheetPresented: false
        ))
        XCTAssertFalse(ActiveView.shouldPresentAMRAPResultSheet(
            timingMode: .forTime,
            blockEndsAt: now.addingTimeInterval(-1),
            now: now,
            isMetconResultSheetPresented: false
        ))
        XCTAssertFalse(ActiveView.shouldPresentAMRAPResultSheet(
            timingMode: .amrap,
            blockEndsAt: now.addingTimeInterval(1),
            now: now,
            isMetconResultSheetPresented: false
        ))
    }
}
