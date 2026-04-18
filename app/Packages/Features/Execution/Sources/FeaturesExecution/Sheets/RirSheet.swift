// RirSheet.swift
//
// RIR picker — 0 through 5 as a horizontal row of large tappable
// buttons. Matches `RirSheet` in `docs/design/src/hifi.jsx` (six
// options with a short-form label).
//
// "Skip" returns without committing a RIR value — the Active-screen
// log flow calls this at the end of the chain; the reducer stores
// `rir = nil` when we pass `nil` along.

import SwiftUI
import DesignSystem

struct RirSheet: View {
    let initialValue: Int?
    let onPick: (Int) -> Void
    let onSkip: () -> Void

    private let options: [(value: Int, label: String)] = [
        (0, "failure"),
        (1, "grinder"),
        (2, "hard"),
        (3, "moderate"),
        (4, "easy"),
        (5, "very easy"),
    ]

    var body: some View {
        ZStack {
            DSColors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                header
                picker
                Spacer()
                DSButton(
                    title: "skip",
                    style: .ghost,
                    action: onSkip
                )
            }
            .padding(DSSpacing.xl)
        }
        .presentationDetents([.medium])
        // Single-direction transition avoids the composite fade-plus-
        // translate that caused a visible frame drop on first present
        // (bug-025). The system-owned backdrop stays on its default
        // animation; the sheet body transition is explicit so SwiftUI
        // doesn't re-run geometry on the first frame.
        .transition(.move(edge: .bottom))
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("how hard?")
                .font(DSTypography.title)
                .foregroundStyle(DSColors.foreground)
            Text("reps in reserve · tap to log")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.foregroundDim)
        }
    }

    private var picker: some View {
        HStack(spacing: DSSpacing.md) {
            ForEach(options, id: \.value) { opt in
                Button(action: { onPick(opt.value) }, label: {
                    VStack(spacing: DSSpacing.xs) {
                        Text("\(opt.value)")
                            .font(.system(size: 28, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(
                                initialValue == opt.value
                                    ? DSColors.accentInk
                                    : DSColors.foreground
                            )
                        Text(opt.label)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(DSColors.foregroundDim)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DSSpacing.lg)
                    .background(
                        initialValue == opt.value
                            ? DSColors.accentMuted
                            : DSColors.surfaceElevated
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                initialValue == opt.value
                                    ? DSColors.accent
                                    : DSColors.border,
                                lineWidth: 1
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                })
                .buttonStyle(.plain)
                .accessibilityLabel("RIR \(opt.value) \(opt.label)")
            }
        }
    }
}
