// NextUpSheet.swift
//
// Read-only detail for the compact "next up" cards in Active and Rest.
// It intentionally does not offer plan editing: reordering/removing work is
// a conversation/planning concern, not an in-execution mutation.

import SwiftUI
import DesignSystem

struct NextUpSheet: View {
    @Environment(\.dismiss) private var dismiss

    let nextUp: ExecutionNextUpPresentation
    let workQueue: [UpcomingWorkPresentation]

    init(
        nextUp: ExecutionNextUpPresentation,
        workQueue: [UpcomingWorkPresentation] = []
    ) {
        self.nextUp = nextUp
        self.workQueue = workQueue
    }

    var body: some View {
        ZStack {
            DSColors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                header
                if !workQueue.isEmpty {
                    queueRows
                }
                if workQueue.isEmpty {
                    nextUpFallbackCard
                }
                explainer
                Spacer(minLength: 0)
            }
            .padding(DSSpacing.xl)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DSButton(
                title: "done",
                style: .ghost,
                action: { dismiss() }
            )
            .padding(.horizontal, DSSpacing.xl)
            .padding(.bottom, DSSpacing.xl)
            .padding(.top, DSSpacing.md)
            .background(DSColors.background)
        }
        .presentationDetents([.medium])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("coming up")
                .font(DSTypography.title)
                .foregroundStyle(DSColors.foreground)
            Text("quick preview before you move")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.foregroundDim)
        }
    }

    private var explainer: some View {
        Text("This is a read-only workout preview. Plan changes stay out of the execution loop for now.")
            .font(DSTypography.body)
            .foregroundStyle(DSColors.foregroundMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var nextUpFallbackCard: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text(nextUp.label.uppercased())
                    .font(DSTypography.subLabel)
                    .tracking(1.2)
                    .foregroundStyle(DSColors.foregroundDim)
                Text(nextUp.title)
                    .font(DSTypography.title)
                    .foregroundStyle(DSColors.foreground)
                if let detail = nextUp.detail {
                    Text(detail)
                        .font(DSTypography.monoLarge)
                        .foregroundStyle(DSColors.accentInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var queueRows: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            ForEach(Array(workQueue.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(row.label.uppercased())
                        .font(DSTypography.subLabel)
                        .tracking(1.2)
                        .foregroundStyle(DSColors.foregroundDim)
                    Text(row.title)
                        .font(DSTypography.subtitle)
                        .foregroundStyle(DSColors.foreground)
                    if let detail = row.detail {
                        Text(detail)
                            .font(DSTypography.mono)
                            .foregroundStyle(DSColors.foregroundMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DSSpacing.md)
                .background(DSColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.card, style: .continuous))
            }
        }
    }
}
