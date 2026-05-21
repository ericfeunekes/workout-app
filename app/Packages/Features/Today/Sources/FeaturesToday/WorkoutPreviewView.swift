// WorkoutPreviewView.swift
//
// Dedicated Today preview sheet. This stays in FeaturesToday so preview,
// adjustment-copy, and start routing do not pull the execution package into
// the Today read surface.

import SwiftUI
import DesignSystem

enum TodaySheet: Identifiable {
    case workoutPreview(TodayViewModel.WorkoutDetail)

    var id: UUID {
        switch self {
        case .workoutPreview(let detail):
            return detail.id
        }
    }
}

struct WorkoutPreviewView: View {
    let detail: TodayViewModel.WorkoutDetail
    let adjustmentDraft: TodayViewModel.AdjustmentDraft
    let isCopied: Bool
    let isStartable: Bool
    let onClose: () -> Void
    let onCopyAdjustment: (String) -> Void
    let onScheduleWorkoutKit: () -> Void
    let onStart: () -> Void

    var body: some View {
        ZStack {
            DSColors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.xl) {
                    HStack {
                        Spacer()
                        Button("done") {
                            onClose()
                        }
                        .font(DSTypography.body)
                        .foregroundStyle(DSColors.accentInk)
                    }

                    detailHeader

                    if let preview = detail.preview {
                        previewCard(preview)
                    }

                    if let handoff = detail.workoutKitHandoff {
                        workoutKitHandoffCard(handoff)
                    }

                    ForEach(detail.blocks) { block in
                        blockDetailCard(block)
                    }

                    adjustmentCard
                }
                .padding(.horizontal, DSSpacing.xl)
                .padding(.top, DSSpacing.xl)
                .padding(.bottom, DSSpacing.xxl)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isStartable {
                DSButton(title: "start", style: .primary) {
                    onStart()
                }
                .accessibilityIdentifier("today.preview.start.\(detail.id.uuidString)")
                .padding(.horizontal, DSSpacing.xl)
                .padding(.bottom, DSSpacing.xl)
                .padding(.top, DSSpacing.md)
                .background(DSColors.background)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(detail.sectionTitle)
                .font(DSTypography.caption)
                .tracking(1.5)
                .foregroundStyle(DSColors.foregroundDim)

            Text(detail.name)
                .font(DSTypography.display)
                .foregroundStyle(DSColors.foreground)

            if let tagLine = detail.tagLine {
                Text(tagLine)
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.foregroundMuted)
            }

            if let notes = detail.notes, !notes.isEmpty {
                Text(notes)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.foregroundMuted)
                    .padding(.top, DSSpacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var adjustmentCard: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                Text("Need to change this?")
                    .font(DSTypography.subtitle)
                    .foregroundStyle(DSColors.foreground)

                Text(
                    "Copy a structured request for Claude. "
                    + "The app does not reorder, swap, or delete planned work locally."
                )
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.foregroundMuted)

                DSButton(
                    title: isCopied ? "copied" : "copy adjustment request",
                    style: .ghost
                ) {
                    onCopyAdjustment(adjustmentDraft.body)
                }

                if isCopied {
                    Text("Copied. Paste it into Claude to request changes.")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.accentInk)
                        .accessibilityIdentifier("today.adjustment.copied")
                }
            }
        }
    }

    private func workoutKitHandoffCard(
        _ handoff: TodayViewModel.WorkoutKitHandoffSummary
    ) -> some View {
        DSCard {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                Text(handoff.title)
                    .font(DSTypography.subtitle)
                    .foregroundStyle(DSColors.foreground)

                Text(handoff.message)
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.foregroundMuted)

                if handoff.isActionable {
                    workoutKitWatchButton
                }
            }
        }
    }

    private var workoutKitWatchButton: some View {
        Button {
            onScheduleWorkoutKit()
        } label: {
            Label("Watch", systemImage: "applewatch")
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(DSColors.accentInk)
                .padding(.horizontal, DSSpacing.lg)
                .frame(minHeight: 44)
                .background(DSColors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.button, style: .continuous)
                        .strokeBorder(DSColors.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Schedule on Watch")
        .accessibilityIdentifier("today.preview.workoutkit.schedule.\(detail.id.uuidString)")
    }

    private func previewCard(_ preview: TodayViewModel.PreviewSummary) -> some View {
        DSCard {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                Text("Current block")
                    .font(DSTypography.caption)
                    .tracking(1.2)
                    .foregroundStyle(DSColors.accentInk)

                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(preview.currentTitle)
                        .font(DSTypography.title)
                        .foregroundStyle(DSColors.foreground)

                    if let currentDetail = preview.currentDetail {
                        Text(currentDetail)
                            .font(DSTypography.mono)
                            .foregroundStyle(DSColors.foregroundDim)
                    }

                    if let blockIntent = preview.blockIntent {
                        Text(blockIntent)
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColors.foregroundMuted)
                    }

                    if let remainingLine = preview.remainingLine {
                        Text(remainingLine)
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColors.foregroundMuted)
                    }
                }

                if !preview.upcoming.isEmpty {
                    DSDivider()
                    VStack(alignment: .leading, spacing: DSSpacing.sm) {
                        ForEach(preview.upcoming) { row in
                            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.md) {
                                Text(row.title)
                                    .font(DSTypography.body)
                                    .foregroundStyle(DSColors.foreground)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if let detail = row.detail {
                                    Text(detail)
                                        .font(DSTypography.mono)
                                        .foregroundStyle(DSColors.foregroundDim)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func blockDetailCard(_ block: TodayViewModel.BlockDetail) -> some View {
        DSCard {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                HStack(alignment: .top, spacing: DSSpacing.md) {
                    DSExerciseIconView(
                        icon: todayBlockIcon(for: block.timingLabel),
                        size: 44,
                        showsTile: true
                    )

                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text(block.timingLabel.uppercased())
                            .font(DSTypography.caption)
                            .tracking(1.2)
                            .foregroundStyle(DSColors.accentInk)

                        Text(block.title)
                            .font(DSTypography.title)
                            .foregroundStyle(DSColors.foreground)

                        if let timingDetail = block.timingDetail {
                            Text(timingDetail)
                                .font(DSTypography.caption)
                                .foregroundStyle(DSColors.foregroundMuted)
                        }

                        if let notes = block.notes, !notes.isEmpty {
                            Text(notes)
                                .font(DSTypography.caption)
                                .foregroundStyle(DSColors.foregroundDim)
                        }
                    }
                }

                if !block.exercises.isEmpty {
                    DSDivider()
                    VStack(alignment: .leading, spacing: DSSpacing.sm) {
                        ForEach(block.exercises) { row in
                            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                                exerciseRow(row, muted: false)
                                if let lastTime = row.lastTime {
                                    Text("last time \(lastTime)")
                                        .font(DSTypography.caption)
                                        .foregroundStyle(DSColors.foregroundDim)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func exerciseRow(
        _ row: TodayViewModel.ExerciseSummary,
        muted: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.md) {
            Text(row.name)
                .font(DSTypography.body)
                .foregroundStyle(muted ? DSColors.foregroundMuted : DSColors.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.prescriptionLine)
                .font(DSTypography.mono)
                .monospacedDigit()
                .foregroundStyle(DSColors.foregroundDim)
        }
    }
}

func todayBlockIcon(for timingLabel: String) -> DSExerciseIcon {
    switch timingLabel {
    case "straight sets":
        return .strength
    case "amrap", "for time", "circuit", "superset":
        return .conditioning
    case "emom", "tabata", "intervals", "custom", "accumulate", "continuous":
        return .timer
    default:
        return .timer
    }
}
