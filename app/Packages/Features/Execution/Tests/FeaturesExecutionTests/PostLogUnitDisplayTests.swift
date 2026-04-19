// PostLogUnitDisplayTests.swift
//
// R2.10 unit-thread fix-it. Before this fix the post-log UI surfaces —
// RestView's "just logged" pill row, RestView's autoreg banner,
// RestView's past-set load sheet, and CompleteView's per-item ledger —
// hardcoded "kg" as the weight suffix. A user logging in lb saw
// "225 lb" on the Active hero (unit-aware via driver.loadDisplay) but
// "225 kg" on every screen after the log. This file pins the contract
// that each surface now reads the unit from its data source
// (SetPlan.unit for pill + sheet; lastLoggedSet.unit for the autoreg
// banner, since AutoregProposal has no unit field; done.first.unit
// for the ledger summary).
//
// Tests target the pure-swift helpers exposed on the view types
// (`RestView.loadPillCaption(for:)`, `RestView.proposalBannerUnit(for:)`,
// `CompleteView.ledgerSummary(for:)`, `CompleteView.splitLedgerSummary(_:)`)
// plus a source-inspection regression that greps the four view source
// files for any remaining hardcoded " kg" / "kg" literal. Pattern
// mirrors `ActiveViewMetaLineTests` — pure statics, no SwiftUI
// snapshotting.

import XCTest
import CoreAutoreg
import CoreDomain
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class PostLogUnitDisplayTests: XCTestCase {

    // MARK: - Fixtures

    /// Build a `SetPlan` whose `loadKg` scalar is interpreted in `unit`.
    /// `done=true` is the "just logged" shape that populates the rest
    /// screen's pill row and the ledger's filter. `load: nil` is the
    /// BW shape (loadless row); `load: 0` is a legitimate zero-load
    /// entry distinct from BW.
    private func makeSet(
        index: Int = 1,
        load: Double?,
        unit: WeightUnit,
        reps: Int = 5,
        done: Bool = true,
        rir: Int? = 2
    ) -> SetPlan {
        SetPlan(
            setIndex: index,
            loadKg: load,
            unit: unit,
            reps: reps,
            done: done,
            adjust: nil,
            rir: rir
        )
    }

    private func makeLog(sets: [SetPlan]) -> SessionState.ItemLog {
        SessionState.ItemLog(itemID: UUID(), sets: sets)
    }

    // MARK: - 1) RestView "just logged" pill caption

    func testRestViewRendersLbUnitForLbSetPlan() {
        // Bug: user logs set on an lb-unit SetPlan; the DSPill caption
        // was hardcoded "KG". Contract: caption reads `set.unit.rawValue`
        // uppercased, so lb renders "LB".
        let set = makeSet(load: 225, unit: .lb)
        XCTAssertEqual(RestView.loadPillCaption(for: set), "LB")
    }

    func testRestViewRendersKgUnitForKgSetPlan() {
        // Symmetry check — kg SetPlans still render "KG".
        let set = makeSet(load: 102.5, unit: .kg)
        XCTAssertEqual(RestView.loadPillCaption(for: set), "KG")
    }

    func testRestViewPillCaptionFallsBackWhenNoLoggedSet() {
        // No set logged → pill value is "—", caption is cosmetic.
        // Fallback must still render uppercase "KG" (not crash, not
        // empty). Pinning the fallback so a future refactor doesn't
        // silently change the dash-state caption.
        XCTAssertEqual(RestView.loadPillCaption(for: nil), "KG")
    }

    // MARK: - 2) Autoreg banner unit inheritance

    func testRestBannerAutoregRendersUnitFromProposal() {
        // `AutoregProposal` has no unit field — the banner inherits
        // from the SetPlan the proposal targets (last logged on the
        // item). Contract: `proposalBannerUnit` reads
        // `lastLoggedSet.unit.rawValue` so an lb-prescribed item's
        // autoreg banner reads "next set: 230 lb", not "... 230 kg".
        let lbSet = makeSet(load: 225, unit: .lb)
        XCTAssertEqual(RestView.proposalBannerUnit(for: lbSet), "lb")

        let kgSet = makeSet(load: 102.5, unit: .kg)
        XCTAssertEqual(RestView.proposalBannerUnit(for: kgSet), "kg")
    }

    func testRestBannerAutoregFallsBackToKgWhenNoLastLoggedSet() {
        // Defensive — proposals can only fire post-log, so the nil
        // branch is unreachable in production. Pin the fallback anyway
        // so a regression doesn't render an empty unit.
        XCTAssertEqual(RestView.proposalBannerUnit(for: nil), "kg")
    }

    // MARK: - 3) Complete ledger summary per-set unit

    func testCompleteLedgerRendersLbSummaryForLbSetLogs() {
        // Contract: `ledgerSummary` uses `done.first.unit` so the
        // per-item summary carries the SetPlan's unit. Seeded with
        // three lb sets @ 225 × 5 rir 2 → "3×5 @ 225 lb · RIR 2".
        let log = makeLog(sets: [
            makeSet(index: 1, load: 225, unit: .lb, reps: 5, rir: 2),
            makeSet(index: 2, load: 225, unit: .lb, reps: 5, rir: 2),
            makeSet(index: 3, load: 225, unit: .lb, reps: 5, rir: 2)
        ])
        XCTAssertEqual(
            CompleteView.ledgerSummary(for: log),
            "3×5 @ 225 lb · RIR 2"
        )
    }

    func testCompleteLedgerRendersKgSummaryForKgSetLogs() {
        // Symmetry — kg SetPlans still render "kg".
        let log = makeLog(sets: [
            makeSet(index: 1, load: 102.5, unit: .kg, reps: 5, rir: 2),
            makeSet(index: 2, load: 102.5, unit: .kg, reps: 5, rir: 2)
        ])
        XCTAssertEqual(
            CompleteView.ledgerSummary(for: log),
            "2×5 @ 102.5 kg · RIR 2"
        )
    }

    func testCompleteLedgerPreservesBodyweightSummary() {
        // BW-only rows still render "BW" (no unit in the loadText),
        // regardless of the SetPlan's unit field. Contract: ONLY
        // `load: nil` is bodyweight — a numeric value (including 0)
        // is a logged load and must not be silently coerced to "BW".
        let log = makeLog(sets: [
            makeSet(index: 1, load: nil, unit: .kg, reps: 10, rir: nil),
            makeSet(index: 2, load: nil, unit: .kg, reps: 10, rir: nil)
        ])
        XCTAssertEqual(
            CompleteView.ledgerSummary(for: log),
            "2×10 @ BW"
        )
    }

    func testCompleteLedgerRendersZeroLoadAsZero() {
        // Regression guard: a legitimate 0-load set (user explicitly
        // logs an empty 0 kg bar during a warm-up, or 0 lb resistance)
        // must render as "0 kg" / "0 lb", NOT "BW". `nil` is the only
        // bodyweight signal — mirrors `LoadFormatting.formatLoad`'s
        // `nil`-only BW convention. The prior `load == nil || load == 0`
        // guard in this helper lied about the logged bytes.
        let kgLog = makeLog(sets: [
            makeSet(index: 1, load: 0, unit: .kg, reps: 5, rir: 2),
            makeSet(index: 2, load: 0, unit: .kg, reps: 5, rir: 2)
        ])
        XCTAssertEqual(
            CompleteView.ledgerSummary(for: kgLog),
            "2×5 @ 0 kg · RIR 2"
        )

        let lbLog = makeLog(sets: [
            makeSet(index: 1, load: 0, unit: .lb, reps: 5, rir: 2),
            makeSet(index: 2, load: 0, unit: .lb, reps: 5, rir: 2)
        ])
        XCTAssertEqual(
            CompleteView.ledgerSummary(for: lbLog),
            "2×5 @ 0 lb · RIR 2"
        )
    }

    // MARK: - 3b) Split of the summary string routes the unit through

    func testCompleteLedgerSplitCarriesLbUnit() throws {
        // The view-side DSWeightLabel gets its unit from LedgerSplit.
        // Contract: when the summary ends in " lb", the split returns
        // `.weightUnit == "lb"` so the rendered label matches the
        // SetPlan. Previously the splitter only matched " kg".
        let split = try XCTUnwrap(
            CompleteView.splitLedgerSummary("3×5 @ 225 lb · RIR 2")
        )
        XCTAssertEqual(split.weightNumber, "225")
        XCTAssertEqual(split.weightUnit, "lb")
        XCTAssertEqual(split.suffix, " · RIR 2")
    }

    func testCompleteLedgerSplitCarriesKgUnit() throws {
        let split = try XCTUnwrap(
            CompleteView.splitLedgerSummary("4×5 @ 102.5 kg · RIR 2")
        )
        XCTAssertEqual(split.weightNumber, "102.5")
        XCTAssertEqual(split.weightUnit, "kg")
        XCTAssertEqual(split.suffix, " · RIR 2")
    }

    func testCompleteLedgerSplitReturnsNilForBodyweight() {
        // BW and "N sets" fall through to the plain-text branch —
        // splitLedgerSummary must return nil so the ViewBuilder
        // skips the DSWeightLabel path.
        XCTAssertNil(CompleteView.splitLedgerSummary("3×10 @ BW"))
        XCTAssertNil(CompleteView.splitLedgerSummary("5 sets"))
    }

    // MARK: - 4) Source-inspection regression — no hardcoded kg left

    func testNoHardcodedKgRemainsInExecutionViews() throws {
        // Scan the four post-log view source files for any remaining
        // hardcoded `" kg"` literal or `formatLoad(kg:)` call. A hit
        // means the R2.10 unit-thread regressed — the file still
        // renders "kg" for lb-prescribed workouts.
        //
        // Comments are allowed to reference "kg" in prose (the existing
        // doc strings explain the bug-027 history). The regex below
        // ignores `//` line comments so those don't fire false
        // positives.
        let viewFiles = [
            "RestView.swift",
            "RestView+Banner.swift",
            "RestView+Sheets.swift",
            "CompleteView.swift",
            "CompleteView+Ledger.swift"
        ]
        let sourceDir = try sourceDirectoryForExecutionViews()

        for filename in viewFiles {
            let url = sourceDir.appendingPathComponent(filename)
            let contents = try String(contentsOf: url, encoding: .utf8)
            let lines = contents.components(separatedBy: "\n")
            for (idx, line) in lines.enumerated() {
                // Strip the line's `//` comment before scanning so
                // doc comments don't count.
                let codeOnly: String
                if let range = line.range(of: "//") {
                    codeOnly = String(line[..<range.lowerBound])
                } else {
                    codeOnly = line
                }
                XCTAssertFalse(
                    codeOnly.contains("\" kg\""),
                    "\(filename):\(idx + 1) — hardcoded \" kg\" literal: \(line)"
                )
                XCTAssertFalse(
                    codeOnly.contains("formatLoad(kg:"),
                    "\(filename):\(idx + 1) — legacy formatLoad(kg:) call: \(line)"
                )
            }
        }
    }

    /// Resolve the absolute path to the FeaturesExecution sources
    /// directory from the test binary's location. The test package and
    /// source package sit side by side under `Features/Execution`, so
    /// walking up to `Execution/` and down into `Sources/
    /// FeaturesExecution/` gets us there. We use `#filePath` (the test
    /// file's own location) rather than `Bundle` since Swift Package
    /// test bundles don't ship the sources as resources.
    private func sourceDirectoryForExecutionViews() throws -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        // …/Execution/Tests/FeaturesExecutionTests/<thisFile>
        let sourcesDir = testFile
            .deletingLastPathComponent()          // FeaturesExecutionTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // Execution
            .appendingPathComponent("Sources")
            .appendingPathComponent("FeaturesExecution")
        return sourcesDir
    }
}
