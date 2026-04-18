// SwapSheet.swift
//
// Long-press on the active exercise opens this sheet. Renders the
// pre-computed `ExerciseAlternative` rows for the current item (with
// reason + optional "last performed" summary). Tapping a row commits
// the swap through `ExecutionViewModel.swap(itemID:, alternativeID:)`
// and dismisses. An explicit "cancel" ghost button and drag-down /
// tap-outside (SwiftUI default on `.sheet`) both dismiss without
// swapping.
//
// Visual: matches the RIR / past-set sheets — dark background, DSCard
// row containers, DSButton for the dismiss action, DSTypography tokens
// throughout. See `docs/design/RULES.md` for the copywriting tone
// (lowercase imperative).

import SwiftUI
import CoreDomain
import DesignSystem

struct SwapSheet: View {
    let itemID: UUID
    let currentExerciseName: String
    let alternatives: [ExerciseAlternative]
    let exerciseName: (UUID) -> String
    let lastPerformed: (UUID) -> String?
    let onPick: (_ alternativeID: UUID) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            DSColors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                header
                if alternatives.isEmpty {
                    emptyState
                } else {
                    list
                }
                Spacer(minLength: DSSpacing.md)
                DSButton(
                    title: "cancel",
                    style: .ghost,
                    action: onCancel
                )
            }
            .padding(DSSpacing.xl)
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("swap exercise")
                .font(DSTypography.title)
                .foregroundStyle(DSColors.foreground)
            Text("for \(currentExerciseName.lowercased()) · remaining sets only")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.foregroundDim)
        }
    }

    private var emptyState: some View {
        DSCard {
            Text("no alternatives authored for this item.")
                .font(DSTypography.body)
                .foregroundStyle(DSColors.foregroundMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: DSSpacing.md) {
                ForEach(alternatives, id: \.id) { alt in
                    row(for: alt)
                }
            }
        }
    }

    private func row(for alt: ExerciseAlternative) -> some View {
        Button(
            action: { onPick(alt.id) },
            label: {
                DSCard {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text(exerciseName(alt.exerciseID))
                            .font(DSTypography.body)
                            .foregroundStyle(DSColors.foreground)
                        if !alt.reason.isEmpty {
                            Text(alt.reason)
                                .font(DSTypography.caption)
                                .foregroundStyle(DSColors.foregroundMuted)
                                .multilineTextAlignment(.leading)
                        }
                        if let last = lastPerformed(alt.exerciseID) {
                            Text("LAST · \(last)")
                                .font(DSTypography.caption)
                                .tracking(0.5)
                                .foregroundStyle(DSColors.foregroundDim)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        )
        .buttonStyle(.plain)
        .accessibilityLabel(Text("swap to \(exerciseName(alt.exerciseID))"))
    }
}
