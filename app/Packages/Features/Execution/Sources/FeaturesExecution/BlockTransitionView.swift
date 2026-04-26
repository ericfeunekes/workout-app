// BlockTransitionView.swift
//
// Purposeful between-block setup surface: what just finished, what is next,
// what to set up, and the single action that enters the next block.

import SwiftUI
import DesignSystem

struct BlockTransitionView: View {
    @Bindable var viewModel: ExecutionViewModel

    var body: some View {
        ZStack {
            DSColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DSSpacing.xl) {
                        if let content = viewModel.blockTransitionPresentation {
                            header(content)
                            nextBlock(content)
                            setup(content)
                        }
                    }
                    .padding(.horizontal, DSSpacing.xl)
                    .padding(.top, DSSpacing.xxl)
                    .padding(.bottom, DSSpacing.xxl)
                }

                DSButton(
                    title: "start block",
                    style: .primary,
                    action: { viewModel.beginBlockTransition() }
                )
                .padding(.horizontal, DSSpacing.xl)
                .padding(.top, DSSpacing.lg)
                .padding(.bottom, DSSpacing.xl)
            }
        }
    }

    private func header(_ content: BlockTransitionPresentation) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("transition")
                .font(DSTypography.title)
                .foregroundStyle(DSColors.foreground)
            Text("FINISHED \(content.finishedTitle.uppercased())")
                .font(DSTypography.subtitle)
                .tracking(0.5)
                .foregroundStyle(DSColors.foregroundMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nextBlock(_ content: BlockTransitionPresentation) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text("NEXT BLOCK")
                .font(DSTypography.subLabel)
                .tracking(1.2)
                .foregroundStyle(DSColors.foregroundDim)
            Text(content.nextTitle)
                .font(DSTypography.title)
                .foregroundStyle(DSColors.foreground)
            Text(content.timingMode.uppercased())
                .font(DSTypography.caption)
                .tracking(1.2)
                .foregroundStyle(DSColors.foregroundMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setup(_ content: BlockTransitionPresentation) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            setupRow(label: "FIRST", value: content.firstTask)
            if let setup = content.setup {
                setupRow(label: "SETUP", value: setup)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setupRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(label)
                .font(DSTypography.subLabel)
                .tracking(1.2)
                .foregroundStyle(DSColors.foregroundDim)
            Text(value)
                .font(DSTypography.mono)
                .foregroundStyle(DSColors.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
