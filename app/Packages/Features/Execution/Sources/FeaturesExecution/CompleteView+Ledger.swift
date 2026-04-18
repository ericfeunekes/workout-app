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
    /// weightNumber: "102.5", suffix: "· RIR 2")`. Returns nil when
    /// the summary doesn't embed a kg load (BW-only, "N sets").
    struct LedgerSplit {
        let prefix: String
        let weightNumber: String
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

    /// Produce a "NxR @ kg · rir N" style summary. Uses the most common
    /// load and reps across logged sets, with RIR from the first logged
    /// set. If no sets logged, returns "no sets logged".
    func summary(for log: SessionState.ItemLog) -> String {
        let done = log.sets.filter(\.done)
        guard !done.isEmpty else { return "no sets logged" }

        let loads = Set(done.map(\.loadKg))
        let reps = Set(done.map(\.reps))

        if loads.count == 1, reps.count == 1,
           let load = loads.first, let repCount = reps.first {
            let rirPart: String
            if let rir = done.first?.rir {
                rirPart = " · RIR \(rir)"
            } else {
                rirPart = ""
            }
            let loadText = load == 0 ? "BW" : "\(formatKilograms(load)) kg"
            return "\(done.count)×\(repCount) @ \(loadText)\(rirPart)"
        }

        return "\(done.count) sets"
    }

    /// Render a summary line. When the summary ends in "kg" (the uniform
    /// "Nxr @ L kg" case), the number + unit go through `DSWeightLabel`
    /// so the mono pairing stays coherent with the hero and banner
    /// (bug-027). Other shapes ("N sets", "BW") render plain.
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
                    unit: "kg",
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

    /// Split "4×5 @ 102.5 kg · RIR 2" into its three parts. Returns nil
    /// when the summary doesn't embed a " kg" token (BW-only, "N sets").
    func splitLedgerSummary(_ s: String) -> LedgerSplit? {
        guard let atRange = s.range(of: " @ ") else { return nil }
        let prefixRaw = String(s[..<atRange.lowerBound])
        let rest = s[atRange.upperBound...]
        guard let kgRange = rest.range(of: " kg") else { return nil }
        let weightNumber = String(rest[..<kgRange.lowerBound])
        let after = String(rest[kgRange.upperBound...])
        let suffix = after.isEmpty ? nil : after
        return LedgerSplit(
            prefix: prefixRaw + " @",
            weightNumber: weightNumber,
            suffix: suffix
        )
    }
}
