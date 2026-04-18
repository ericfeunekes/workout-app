// HistoryRow.swift
//
// Reusable row for the history list view. Mirrors the "Push A · MON"
// rows in docs/design/components/history-full.jsx (lines 12-28):
//   - top line: program name in body type ("Push A · MON" — we split
//     date out into its own leading-cap token)
//   - bottom line: meta chips — RIR, duration, optional body weight,
//     optional form-note dot.

import SwiftUI
import DesignSystem

struct HistoryRow: View {
    let row: HistoryViewModel.SessionRow

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(spacing: DSSpacing.md) {
                Text(row.programName)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.foreground)
                Text("·")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.foregroundDim)
                Text(row.shortDate)
                    .font(DSTypography.caption)
                    .tracking(0.5)
                    .foregroundStyle(DSColors.foregroundMuted)
                Spacer(minLength: 0)
                if row.hasNote {
                    Circle()
                        .fill(DSColors.accent)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel("has note")
                }
            }
            HStack(spacing: DSSpacing.md) {
                ForEach(metaParts, id: \.self) { part in
                    Text(part)
                        .font(DSTypography.caption)
                        .tracking(0.5)
                        .foregroundStyle(DSColors.foregroundDim)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, DSSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Meta line parts, separated by their own text cells. Joining with
    /// " · " would compress the divider character into the caption font;
    /// separate cells + a parent HStack spacing matches the design's
    /// airy mid-dots better. We render the actual separator between
    /// cells below.
    private var metaParts: [String] {
        var parts: [String] = []
        if let rir = row.avgRIR { parts.append(rir) }
        if let dur = row.duration { parts.append(dur) }
        if let bw = row.bodyweight { parts.append(bw) }
        return Array(interleave(parts, with: "·"))
    }

    /// Interleave a mid-dot separator between the meta parts so the
    /// single-line HStack renders "RIR 1.5 · 54 MIN · 82.1 KG BW".
    private func interleave<S: Sequence>(_ items: S, with sep: String) -> [String] where S.Element == String {
        var out: [String] = []
        var first = true
        for item in items {
            if !first { out.append(sep) }
            out.append(item)
            first = false
        }
        return out
    }
}
