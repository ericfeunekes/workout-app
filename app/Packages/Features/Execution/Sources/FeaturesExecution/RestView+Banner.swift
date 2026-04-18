// RestView+Banner.swift
//
// Autoreg banner rendering for `RestView`, extracted so the main struct
// body stays under SwiftLint's `type_body_length` cap. Reads
// `viewModel.currentProposal` and routes the number + unit through
// `DSWeightLabel` (bug-027) so the mono pairing matches the hero and
// ledger.

import SwiftUI
import CoreAutoreg
import DesignSystem
import WorkoutCoreFoundation

extension RestView {

    @ViewBuilder
    var autoregBannerView: some View {
        if let proposal = viewModel.currentProposal {
            HStack(alignment: .top, spacing: DSSpacing.md) {
                Text(proposal.direction == .up ? "↑" : "↓")
                    .font(DSTypography.monoLarge)
                    .foregroundStyle(DSColors.accentInk)
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    // "next set: 102.5 kg" — the number + unit pair
                    // routes through `DSWeightLabel` so "kg" shares
                    // the same mono family + weight as the digits
                    // (bug-027). The leading "next set:" stays sans.
                    HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
                        Text("next set:")
                            .font(DSTypography.body)
                            .foregroundStyle(DSColors.foreground)
                        DSWeightLabel(
                            number: formatKilograms(proposal.newLoadKg),
                            unit: "kg",
                            size: 15,
                            weight: .medium,
                            color: DSColors.foreground
                        )
                    }
                    Text(reasonText(proposal.reason))
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.foregroundMuted)
                }
                Spacer()
                Button(action: { viewModel.undoAutoreg() }, label: {
                    Text("undo")
                        .font(DSTypography.caption)
                        .tracking(0.5)
                        .foregroundStyle(DSColors.accentInk)
                        .padding(.vertical, DSSpacing.sm)
                        .padding(.horizontal, DSSpacing.lg)
                        .background(DSColors.surfaceElevated)
                        .clipShape(Capsule())
                })
                .buttonStyle(.plain)
            }
            .padding(DSSpacing.lg)
            .background(DSColors.accentMuted)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(DSColors.accent.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    func reasonText(_ reason: AutoregProposal.Reason) -> String {
        switch reason {
        case .overshoot(let rir, let target, _):
            return "rir \(rir) > target \(target)"
        case .undershootReps(let prescribed, let actual, _):
            return "missed \(prescribed - actual) reps"
        case .hitFailure(let target):
            return "hit failure · target rir \(target)"
        }
    }
}
