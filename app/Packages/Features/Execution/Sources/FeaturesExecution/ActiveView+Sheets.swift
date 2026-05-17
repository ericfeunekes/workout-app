// ActiveView+Sheets.swift
//
// Modal route definitions for ActiveView. Keeping every Active sheet behind
// one enum makes new correction/edit surfaces explicit instead of adding more
// independent booleans to the execution screen.

import SwiftUI

enum ActiveSheet: String, Identifiable {
    case logSet
    case swap
    case metconResult
    case nextUp

    var id: String { rawValue }
}

extension ActiveView {
    @ViewBuilder
    func activeSheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .logSet:
            logSetSheet
        case .swap:
            swapSheet
        case .metconResult:
            metconResultSheet
        case .nextUp:
            nextUpSheet
        }
    }

    @ViewBuilder
    private var logSetSheet: some View {
        // Combined reps + RIR entry — single sheet, one commit
        // (bug-023 fix). Prescribed reps pre-fill the numpad; RIR
        // is untouched = nil on commit, matching the prior "skip"
        // semantics. The NumPad + Rir individual sheets still ship
        // for past-set edits on the Rest screen where only one
        // field changes at a time.
        //
        // Sheet is strength-only — cardio blocks never present it
        // (they dispatch `logCurrentSet` directly from the button
        // tap). So the sheet's commit fires the strength-specific
        // `logSet(reps:rir:)` rather than the mode-branching
        // `logCurrentSet(...)`.
        if let content = viewModel.activeContent {
            LogSetSheet(
                title: logSheetTitle(content: content),
                initialLoad: viewModel.activeSetPlan?.loadKg,
                loadUnit: viewModel.activeSetPlan?.unit.rawValue,
                initialReps: content.reps,
                onCommit: { loadKg, reps, rir in
                    activeSheet = nil
                    viewModel.logSet(loadKg: loadKg, reps: reps, rir: rir)
                }
            )
        }
    }

    private var metconResultSheet: some View {
        MetconResultSheet(
            timingMode: currentTimingMode,
            elapsed: currentWorkElapsedSeconds,
            amrapItems: viewModel.amrapPartialResultItems(),
            onAMRAPCommit: { extraReps in
                activeSheet = nil
                viewModel.logAMRAPPartialResult(extraReps: extraReps)
            },
            onForTimeCommit: {
                activeSheet = nil
                viewModel.logForTimeResult()
            }
        )
    }

    @ViewBuilder
    private var nextUpSheet: some View {
        if let nextUp = viewModel.nextUpPresentation {
            NextUpSheet(
                nextUp: nextUp,
                workQueue: viewModel.executionProjection(now: Date()).workQueue
            )
        }
    }
}
