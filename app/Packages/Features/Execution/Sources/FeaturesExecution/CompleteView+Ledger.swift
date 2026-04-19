// CompleteView+Ledger.swift
//
// Ledger row rendering + summary-string math extracted from
// `CompleteView.swift` so the main struct body stays under SwiftLint's
// `type_body_length` cap. The ledger is the visually heaviest part of
// the Complete screen (bug-028 padding rework + bug-027 font pairing)
// so its helpers naturally group into their own file.

import SwiftUI
import CoreSession
import DesignSystem
import WorkoutCoreFoundation

extension CompleteView {

    /// One rendered row in the per-item ledger.
    struct LedgerEntry {
        let name: String
        let summary: String
    }

    /// Split of a uniform summary string — e.g.
    /// "4×5 @ 102.5 kg · RIR 2" → `(prefix: "4×5 @",
    /// weightNumber: "102.5", weightUnit: "kg", suffix: "· RIR 2")`.
    /// Returns nil when the summary doesn't embed a weighted load
    /// (BW-only, "N sets"). `weightUnit` tracks the per-row unit so
    /// the DSWeightLabel suffix follows the SetPlan instead of
    /// hardcoding "kg" — R2.10 unit-thread.
    struct LedgerSplit {
        let prefix: String
        let weightNumber: String
        let weightUnit: String
        let suffix: String?
    }

    /// Collect the per-item ledger entries from the session state.
    func allLedgerEntries() -> [LedgerEntry] {
        var out: [LedgerEntry] = []
        for blockItems in viewModel.context.itemsByBlock {
            for item in blockItems {
                guard let log = viewModel.state.items.first(where: { $0.itemID == item.id }) else {
                    continue
                }
                let name = viewModel.context.exerciseName(
                    for: item,
                    performedExerciseID: log.performedExerciseID
                )
                out.append(LedgerEntry(name: name, summary: summary(for: log)))
            }
        }
        return out
    }

    /// Produce a "NxR @ load · rir N" style summary. Uses the most common
    /// load and reps across logged sets, with RIR from the first logged
    /// set. If no sets logged, returns "no sets logged".
    ///
    /// R2.10 unit-thread: the load suffix follows the SetPlan's unit
    /// (from `done.first.unit` — all sets on one item share a unit
    /// under the current data model), so an lb-prescribed item renders
    /// "3×5 @ 225 lb" instead of the hardcoded "225 kg" that leaked
    /// through before this fix.
    func summary(for log: SessionState.ItemLog) -> String {
        CompleteView.ledgerSummary(for: log)
    }

    /// Pure-swift entry point exposed for unit tests — no `self`
    /// dependency. Kept as a static so the R2.10 unit-thread contract
    /// can be pinned without building a SwiftUI view in-test.
    static func ledgerSummary(for log: SessionState.ItemLog) -> String {
        let done = log.sets.filter(\.done)
        guard !done.isEmpty else { return "no sets logged" }

        let loads = Set(done.map(\.loadKg))
        let reps = Set(done.map(\.reps))

        if loads.count == 1, reps.count == 1,
           let load = loads.first, let repCount = reps.first,
           let unit = done.first?.unit {
            let rirPart: String
            if let rir = done.first?.rir {
                rirPart = " · RIR \(rir)"
            } else {
                rirPart = ""
            }
            // `load` is `Double?` — only `nil` means bodyweight. A
            // numeric 0 is a legitimate logged value (e.g. 0 kg bar
            // during a mobility warm-up) and renders as "0 kg" / "0 lb"
            // so the ledger reflects what the user logged, not a
            // higher-level interpretation. Mirrors the `nil`-only BW
            // convention in `LoadFormatting.formatLoad`.
            let loadText = formatLoad(
                weight: load,
                unit: LoadUnit(setPlanUnit: unit)
            )
            return "\(done.count)×\(repCount) @ \(loadText)\(rirPart)"
        }

        return "\(done.count) sets"
    }

    /// Render a summary line. When the summary ends in a weight unit
    /// (the uniform "Nxr @ L {kg|lb}" case), the number + unit go through
    /// `DSWeightLabel` so the mono pairing stays coherent with the hero
    /// and banner (bug-027). Other shapes ("N sets", "BW") render plain.
    @ViewBuilder
    func ledgerSummaryView(entry: LedgerEntry) -> some View {
        if let split = splitLedgerSummary(entry.summary) {
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                Text(split.prefix)
                    .font(DSTypography.mono)
                    .monospacedDigit()
                    .foregroundStyle(DSColors.foregroundMuted)
                DSWeightLabel(
                    number: split.weightNumber,
                    unit: split.weightUnit,
                    size: 14,
                    weight: .regular,
                    color: DSColors.foregroundMuted
                )
                if let suffix = split.suffix {
                    Text(suffix)
                        .font(DSTypography.mono)
                        .monospacedDigit()
                        .foregroundStyle(DSColors.foregroundMuted)
                }
            }
        } else {
            Text(entry.summary)
                .font(DSTypography.mono)
                .monospacedDigit()
                .foregroundStyle(DSColors.foregroundMuted)
        }
    }

    /// Split "4×5 @ 102.5 kg · RIR 2" (or "... 225 lb · RIR 2") into
    /// its parts. Returns nil when the summary doesn't embed a
    /// recognised unit suffix (BW-only, "N sets"). Unit lookup scans
    /// every `LoadUnit` raw value so a future unit addition is covered
    /// without a new branch — R2.10 unit-thread.
    func splitLedgerSummary(_ s: String) -> LedgerSplit? {
        CompleteView.splitLedgerSummary(s)
    }

    /// Static entry point exposed for unit tests. See the instance
    /// method above for the contract.
    static func splitLedgerSummary(_ s: String) -> LedgerSplit? {
        guard let atRange = s.range(of: " @ ") else { return nil }
        let prefixRaw = String(s[..<atRange.lowerBound])
        let rest = String(s[atRange.upperBound...])
        // Try each known unit and take the earliest match. In practice
        // only one unit appears per summary (single-item unit), but
        // scanning all of them is the robust pattern.
        var earliest: (range: Range<String.Index>, unit: LoadUnit)?
        for unit in LoadUnit.allCases {
            guard let range = rest.range(of: " \(unit.rawValue)") else {
                continue
            }
            if let current = earliest, range.lowerBound >= current.range.lowerBound {
                continue
            }
            earliest = (range, unit)
        }
        guard let (unitRange, unit) = earliest else { return nil }
        let weightNumber = String(rest[..<unitRange.lowerBound])
        let after = String(rest[unitRange.upperBound...])
        let suffix = after.isEmpty ? nil : after
        return LedgerSplit(
            prefix: prefixRaw + " @",
            weightNumber: weightNumber,
            weightUnit: unit.rawValue,
            suffix: suffix
        )
    }
}
