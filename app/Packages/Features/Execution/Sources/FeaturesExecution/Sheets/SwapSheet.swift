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
                    Spacer(minLength: 0)
                } else {
                    list
                }
            }
            .padding(DSSpacing.xl)
        }
        // Pin the cancel button as a bottom footer so the alternatives
        // list scrolls underneath it (with matching inset) instead of
        // the button overlaying the last rows in the `.medium` detent —
        // qa-022. `safeAreaInset` is the canonical SwiftUI pattern for
        // sticky footers and hands the ScrollView its inset for free.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DSButton(
                title: "cancel",
                style: .ghost,
                action: onCancel
            )
            .padding(.horizontal, DSSpacing.xl)
            .padding(.bottom, DSSpacing.xl)
            .padding(.top, DSSpacing.md)
            .background(DSColors.background)
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

// MARK: - Previews

#if DEBUG
/// Host wrapper so the sheet renders inside a real `.sheet` presentation —
/// the `.medium` detent + `safeAreaInset` footer only behave correctly
/// when presented as a sheet. Visually verifies qa-022: with 6
/// alternatives in the default `.medium` detent, the bottom rows must
/// remain tappable (i.e. the cancel footer must not occlude them).
private struct SwapSheetPreviewHost: View {
    let alternatives: [ExerciseAlternative]
    @State private var presenting: Bool = true

    var body: some View {
        ZStack {
            DSColors.background.ignoresSafeArea()
            Text("host — tap to re-present")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.foregroundMuted)
                .onTapGesture { presenting = true }
        }
        .sheet(isPresented: $presenting) {
            SwapSheet(
                itemID: UUID(),
                currentExerciseName: "back squat",
                alternatives: alternatives,
                exerciseName: { id in
                    Self.nameTable[id] ?? "exercise \(id.uuidString.prefix(4))"
                },
                lastPerformed: { _ in "7d ago · 3×5 @ 225" },
                onPick: { _ in presenting = false },
                onCancel: { presenting = false }
            )
        }
    }

    fileprivate static var nameTable: [UUID: String] = [:]
}

private func makeSixAlternatives() -> [ExerciseAlternative] {
    let names = [
        "front squat",
        "goblet squat",
        "split squat",
        "bulgarian split squat",
        "hack squat",
        "leg press",
    ]
    var out: [ExerciseAlternative] = []
    let itemID = UUID()
    for name in names {
        let exerciseID = UUID()
        SwapSheetPreviewHost.nameTable[exerciseID] = name
        out.append(ExerciseAlternative(
            id: UUID(),
            workoutItemID: itemID,
            exerciseID: exerciseID,
            reason: "knee-friendly variant"
        ))
    }
    return out
}

#Preview("Swap — 6 alternatives, medium detent") {
    SwapSheetPreviewHost(alternatives: makeSixAlternatives())
        .preferredColorScheme(.dark)
}
#endif
