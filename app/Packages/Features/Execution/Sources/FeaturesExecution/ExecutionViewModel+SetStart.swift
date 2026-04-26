// ExecutionViewModel+SetStart.swift
//
// Explicit work-boundary helpers. Straight sets require the athlete to
// tap "Set Start" before a log can commit, so ready/prep time stays
// separate from actual working-set duration.

import Foundation
import CoreDomain

extension ExecutionViewModel {

    var requiresExplicitSetStartForCurrentWork: Bool {
        guard state.route == .active else { return false }
        if isCurrentCompositeSet { return true }
        guard let block = context.block(at: state.cursor.blockIndex) else {
            return false
        }
        switch block.timingMode {
        case .straightSets:
            return true
        case .emom:
            return activeContent?.kind != .cardio
        case .accumulate:
            return true
        case .superset, .circuit, .amrap, .forTime, .intervals, .tabata,
             .continuous, .custom, .rest:
            return false
        }
    }

    var isCurrentWorkStarted: Bool {
        guard requiresExplicitSetStartForCurrentWork else { return true }
        return state.workStartedAt != nil
    }

    public func startCurrentSet() {
        guard requiresExplicitSetStartForCurrentWork,
              state.workStartedAt == nil else {
            return
        }
        if isCurrentCompositeSet {
            startCurrentCompositeSlot()
            return
        }
        emitSessionMutation("start_set")
        state.workStartedAt = clock.now
        state.workReadyAt = nil
        persist()
    }

    func prepareExplicitSetStartIfNeeded() {
        guard requiresExplicitSetStartForCurrentWork,
              state.workStartedAt != nil else {
            return
        }
        state.workStartedAt = nil
        state.workReadyAt = clock.now
        persist()
    }

    func canLogCurrentWork() -> Bool {
        !requiresExplicitSetStartForCurrentWork || state.workStartedAt != nil
    }
}
