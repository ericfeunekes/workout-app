// ExecutionViewModel+Skip.swift
//
// Deliberate skip support. A skipped row is still a completed session row
// for cursor/progress, but push/history receive `skipped=true` and no
// performance metrics.

import Foundation
import CoreDomain
import CoreSession

extension ExecutionViewModel {

    public var canSkipCurrentSet: Bool {
        guard state.route == .active,
              let set = activeSetPlan,
              !set.done else {
            return false
        }
        guard let block = context.block(at: state.cursor.blockIndex) else {
            return false
        }
        switch block.timingMode {
        case .amrap, .forTime, .rest:
            return false
        case .straightSets, .superset, .circuit, .emom, .intervals, .tabata,
             .continuous, .custom:
            return !isCurrentRoundRobinBatchMode
        case .accumulate:
            return false
        }
    }

    public func skipCurrentSet() {
        guard canSkipCurrentSet else { return }
        let cursor = state.cursor
        let previousBlockIndex = cursor.blockIndex
        guard let item = context.item(at: cursor.blockIndex, itemIndex: cursor.itemIndex) else {
            return
        }
        let skipMutation: SessionMutation = .skipSet(
            itemID: item.id,
            setIndex: cursor.setIndex,
            now: clock.now
        )
        let postLogState = SessionReducer.reduce(state, skipMutation)
        apply(buildLogMutations(
            logMutation: skipMutation,
            outcome: DriverLogOutcome(),
            item: item,
            postLogState: postLogState
        ))
        currentProposal = nil
        currentProposalItemID = nil
        emitSessionMutation("skip_set")
        enqueueEditedSet(item: item, setIndex: cursor.setIndex)
        if enterBlockTransitionIfNeeded(from: previousBlockIndex) {
            return
        }
        enterRestIfZeroItemBlock()
        enterTabataWorkWindowIfNeeded()
        enterBlockTimerIfNeeded()
        prepareExplicitSetStartIfNeeded()
    }
}
