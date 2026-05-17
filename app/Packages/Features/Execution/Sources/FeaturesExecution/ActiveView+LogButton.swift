// ActiveView+LogButton.swift
//
// Log-button affordance for the Active screen, split out of
// `ActiveView.swift` so the struct body stays under SwiftLint's
// `type_body_length` cap.
//
// The button branches on the current block's timing mode:
//   * Strength modes open `LogSetSheet` (load + reps + RIR) on tap. The
//     sheet's commit fires the strength `logSet` entry point directly
//     — no mode branching needed there because cardio never presents it.
//   * Cardio modes (`.intervals` / `.continuous`) have no reps / RIR to
//     enter. The tap fires `viewModel.logCurrentSet()` directly, which
//     routes through `logCardioSet(...)` internally with duration /
//     startedAt derived from `SessionState.workStartedAt` + the block's
//     parsed timing config.
//
// This is the call-site fix for R2.12: pre-fix, `ActiveView` opened
// `LogSetSheet` unconditionally, so cardio sessions landed SetLog rows
// through the strength path (reps=0, durationSec=nil).

import SwiftUI
import CoreDomain
import DesignSystem

extension ActiveView {

    /// Primary "log" affordance at the bottom of Active. See the file
    /// header for the cardio / strength branch rationale.
    @ViewBuilder
    func logButton(content: ActiveContent) -> some View {
        VStack(spacing: DSSpacing.md) {
            primaryLogButton(content: content)
            if viewModel.canSkipCurrentSet {
                DSButton(
                    title: "skip",
                    style: .ghost,
                    action: { viewModel.skipCurrentSet() }
                )
            }
        }
    }

    @ViewBuilder
    private func primaryLogButton(content: ActiveContent) -> some View {
        let mode = viewModel.context.block(at: viewModel.state.cursor.blockIndex)?.timingMode
        if viewModel.requiresExplicitSetStartForCurrentWork,
           !viewModel.isCurrentWorkStarted {
            DSButton(
                title: viewModel.currentCompositeButtonTitle,
                style: .primary,
                action: { viewModel.startCurrentSet() }
            )
        } else if mode == .forTime {
            DSButton(
                title: "finish",
                style: .primary,
                action: { viewModel.logForTimeResult() }
            )
        } else if mode == .amrap {
            DSButton(
                title: "next",
                style: .primary,
                action: {
                    if !viewModel.logAMRAPStation(reps: content.reps) {
                        activeSheet = .metconResult
                    }
                }
            )
        } else if viewModel.isCurrentRoundRobinBatchMode {
            roundRobinBatchButton()
        } else if viewModel.isCurrentBlockCardio {
            cardioLogButtons(content: content)
        } else if viewModel.isCurrentCompositeSet && !viewModel.isCurrentCompositeSlotFinal {
            DSButton(
                title: viewModel.currentCompositeButtonTitle,
                style: .primary,
                action: { viewModel.completeCurrentCompositeSlot() }
            )
        } else if viewModel.isCurrentCompositeSet {
            DSButton(
                title: strengthLogTitle(content: content),
                style: .primary,
                action: { activeSheet = .logSet }
            )
        } else {
            DSButton(
                title: strengthLogTitle(content: content),
                style: .primary,
                action: { activeSheet = .logSet }
            )
        }
    }

    @ViewBuilder
    private func roundRobinBatchButton() -> some View {
        if viewModel.isCurrentCompositeSet && !viewModel.isCurrentCompositeSlotFinal {
            DSButton(
                title: viewModel.currentCompositeButtonTitle,
                style: .primary,
                action: { viewModel.completeCurrentCompositeSlot() }
            )
        } else {
            DSButton(
                title: roundRobinBatchTitle(),
                style: .primary,
                action: { viewModel.advanceRoundRobinBatchStation() }
            )
        }
    }

    @ViewBuilder
    private func cardioLogButtons(content: ActiveContent) -> some View {
        if viewModel.continuousTargetReached {
            VStack(spacing: DSSpacing.md) {
                DSButton(
                    title: cardioLogTitle(content: content),
                    style: .primary,
                    action: { viewModel.logCurrentSet() }
                )
                DSButton(
                    title: "continue",
                    style: .ghost,
                    action: { viewModel.continueContinuousPastTarget() }
                )
            }
        } else {
            DSButton(
                title: cardioLogTitle(content: content),
                style: .primary,
                action: { viewModel.logCurrentSet() }
            )
        }
    }

    /// Button title for cardio blocks. `.continuous` is one unbroken
    /// effort — "end" reads more naturally than "log set 1". `.intervals`
    /// reads as "log interval N" so the counter is still visible.
    /// Anything else that lands here (defensive — `isCurrentBlockCardio`
    /// has already narrowed the mode) falls back to strength phrasing.
    func cardioLogTitle(content: ActiveContent) -> String {
        let bi = viewModel.state.cursor.blockIndex
        switch viewModel.context.block(at: bi)?.timingMode {
        case .continuous:
            return viewModel.continuousTargetReached ? "complete" : "end"
        case .intervals:
            return "log interval \(content.setIndex)"
        case .custom:
            return "log segment \(content.setIndex)"
        case .accumulate:
            return "break"
        case .tabata:
            return "log round \(content.setIndex)"
        default:
            return "log set \(content.setIndex)"
        }
    }

    /// Button title for strength-shaped logging. The data path is still
    /// `LogSetSheet`, but the user's mental model changes by timing mode.
    func strengthLogTitle(content: ActiveContent) -> String {
        let bi = viewModel.state.cursor.blockIndex
        switch viewModel.context.block(at: bi)?.timingMode {
        case .emom:
            return "log interval \(content.setIndex)"
        case .forTime, .tabata:
            return "log round \(content.setIndex)"
        case .custom:
            return "log segment \(content.setIndex)"
        case .accumulate:
            return "log chunk"
        case .superset, .circuit, .amrap:
            return "log station"
        case .straightSets:
            return "done"
        case .rest, .intervals, .continuous, nil:
            return "log set \(content.setIndex)"
        }
    }

    func roundRobinBatchTitle() -> String {
        let cursor = viewModel.state.cursor
        let itemsInBlock = cursor.blockIndex < viewModel.state.structure.itemsPerBlock.count
            ? viewModel.state.structure.itemsPerBlock[cursor.blockIndex]
            : 0
        let isLastStation = cursor.itemIndex + 1 >= itemsInBlock
        return isLastStation ? "finish round" : "next station"
    }
}
