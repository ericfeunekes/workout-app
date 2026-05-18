// MetconResultSheet.swift

import SwiftUI
import CoreDomain
import DesignSystem
import WorkoutCoreFoundation

struct AMRAPPartialResultItem: Identifiable, Equatable {
    enum State: Equatable {
        case completed
        case current
        case locked
    }

    let id: UUID
    let name: String
    let prescription: String
    let resultLabel: String
    let state: State
}

struct MetconResultSheet: View {
    let timingMode: TimingMode
    let elapsed: TimeInterval
    let amrapItems: [AMRAPPartialResultItem]
    let onAMRAPCommit: (Int) -> Void
    let onForTimeCommit: () -> Void

    @State private var extraReps = 0

    var body: some View {
        ZStack {
            DSColors.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                Text(title)
                    .font(DSTypography.title)
                    .foregroundStyle(DSColors.foreground)
                Text("record the block result")
                    .font(DSTypography.subtitle)
                    .foregroundStyle(DSColors.foregroundMuted)

                if timingMode == .amrap {
                    amrapControls
                    DSButton(
                        title: "save result",
                        style: .primary,
                        action: { onAMRAPCommit(extraReps) }
                    )
                } else {
                    elapsedCard
                    DSButton(
                        title: "save finish",
                        style: .primary,
                        action: onForTimeCommit
                    )
                }
            }
            .padding(DSSpacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var title: String {
        timingMode == .amrap ? "AMRAP result" : "For Time result"
    }

    private var amrapControls: some View {
        VStack(spacing: DSSpacing.md) {
            ForEach(amrapItems) { item in
                amrapRow(item)
            }
            Text("Result note: partial round captured at the current station")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.foregroundMuted)
        }
        .padding(DSSpacing.lg)
        .background(DSColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func amrapRow(_ item: AMRAPPartialResultItem) -> some View {
        let row = HStack(spacing: DSSpacing.md) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(item.name)
                    .font(DSTypography.subtitle)
                    .foregroundStyle(DSColors.foreground)
                if !item.prescription.isEmpty {
                    Text(item.prescription)
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.foregroundMuted)
                }
            }
            Spacer()
            switch item.state {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(DSColors.accentInk)
                    .accessibilityLabel("\(item.name) completed")
            case .current:
                counterControls(label: item.name, resultLabel: item.resultLabel)
            case .locked:
                Text("—")
                    .font(.system(size: 32, weight: .light, design: .monospaced))
                    .foregroundStyle(DSColors.foregroundFaint)
                    .accessibilityLabel("\(item.name) not reached")
            }
        }

        switch item.state {
        case .current:
            row.accessibilityElement(children: .contain)
        case .completed, .locked:
            row.accessibilityElement(children: .combine)
        }
    }

    private func counterControls(label: String, resultLabel: String) -> some View {
        HStack(spacing: DSSpacing.md) {
            Button {
                extraReps = max(0, extraReps - 1)
            } label: {
                Text("-")
                    .font(DSTypography.title)
                    .foregroundStyle(DSColors.foreground)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("decrease \(label) \(resultLabel)")

            Text("\(extraReps)")
                .font(.system(size: 36, weight: .light, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(DSColors.accentInk)
                .frame(minWidth: 56)

            Button {
                extraReps += 1
            } label: {
                Text("+")
                    .font(DSTypography.title)
                    .foregroundStyle(DSColors.foreground)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("increase \(label) \(resultLabel)")
        }
    }

    private var elapsedCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("elapsed")
                .font(DSTypography.subLabel)
                .tracking(1.2)
                .foregroundStyle(DSColors.foregroundDim)
            Text(formatDuration(seconds: elapsed))
                .font(.system(size: 56, weight: .light, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(DSColors.accentInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.lg)
        .background(DSColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

}
