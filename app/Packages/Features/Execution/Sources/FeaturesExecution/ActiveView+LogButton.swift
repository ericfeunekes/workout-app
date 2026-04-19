// ActiveView+LogButton.swift
//
// Log-button affordance for the Active screen, split out of
// `ActiveView.swift` so the struct body stays under SwiftLint's
// `type_body_length` cap.
//
// The button branches on the current block's timing mode:
//   * Strength modes open `LogSetSheet` (reps + RIR numpad) on tap. The
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
        if viewModel.isCurrentBlockCardio {
            DSButton(
                title: cardioLogTitle(content: content),
                style: .primary,
                action: { viewModel.logCurrentSet() }
            )
        } else {
            DSButton(
                title: "log set \(content.setIndex)",
                style: .primary,
                action: { showLogSheet = true }
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
            return "end"
        case .intervals:
            return "log interval \(content.setIndex)"
        default:
            return "log set \(content.setIndex)"
        }
    }
}
