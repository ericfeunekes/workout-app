// ExecutionViewModel+CompositeSet.swift
//
// Runtime helpers for composed strength sets (cluster/rest-pause). The
// top-level SetPlan remains the authoritative log row; these helpers drive
// slot transitions inside that set before the final log commits.

import Foundation
import CoreDomain
import CoreSession

extension ExecutionViewModel {

    var activeCompositeSet: SessionState.CompositeSetProgress? {
        let c = state.cursor
        guard let item = context.item(at: c.blockIndex, itemIndex: c.itemIndex) else {
            return nil
        }
        return state.compositeSets.first {
            $0.itemID == item.id && $0.setIndex == c.setIndex
        }
    }

    var isCurrentCompositeSet: Bool {
        activeCompositeSet != nil
    }

    var currentCompositeSlotIndex: Int? {
        guard let progress = activeCompositeSet else { return nil }
        switch progress.phase {
        case .ready(let slotIndex):
            return slotIndex
        case .working(let slotIndex, _):
            return slotIndex
        case .intraRest(let afterSlotIndex, _):
            return min(afterSlotIndex + 1, progress.slotCount)
        case .completePendingLog:
            return progress.slotCount
        }
    }

    var isCurrentCompositeSlotFinal: Bool {
        guard let progress = activeCompositeSet,
              let slotIndex = currentCompositeSlotIndex else {
            return false
        }
        return slotIndex >= progress.slotCount
    }

    var isCurrentCompositeIntraRest: Bool {
        guard let progress = activeCompositeSet else { return false }
        if case .intraRest = progress.phase { return true }
        return false
    }

    var currentCompositeButtonTitle: String {
        guard let progress = activeCompositeSet,
              let slotIndex = currentCompositeSlotIndex else {
            return "set start"
        }
        let unit = compositeUnitLabel(for: progress)
        if isCurrentCompositeIntraRest {
            return "start \(unit) \(slotIndex)"
        }
        if state.workStartedAt == nil {
            return slotIndex == 1 ? "set start" : "start \(unit) \(slotIndex)"
        }
        return slotIndex >= progress.slotCount ? "done" : "done \(unit) \(slotIndex)"
    }

    var currentCompositeRepsDisplay: String? {
        guard let progress = activeCompositeSet,
              let slotIndex = currentCompositeSlotIndex else { return nil }
        let unit = compositeUnitLabel(for: progress)
        return "\(progress.targetRepsPerSlot) reps · \(unit) \(slotIndex)/\(progress.slotCount)"
    }

    func startCurrentCompositeSlot() {
        guard let progress = activeCompositeSet,
              let slotIndex = currentCompositeSlotIndex,
              state.workStartedAt == nil else {
            return
        }
        emitSessionMutation("start_composite_slot")
        apply([.startCompositeSlot(
            itemID: progress.itemID,
            setIndex: progress.setIndex,
            slotIndex: slotIndex,
            startedAt: clock.now
        )])
    }

    func completeCurrentCompositeSlot() {
        guard let progress = activeCompositeSet,
              state.workStartedAt != nil,
              !isCurrentCompositeSlotFinal else {
            return
        }
        emitSessionMutation("complete_composite_slot")
        apply([.completeCompositeSlot(
            itemID: progress.itemID,
            setIndex: progress.setIndex,
            now: clock.now
        )])
    }

    func logCompositeSet(item: WorkoutItem, reps: Int, rir: Int?) {
        let c = state.cursor
        let previousBlockIndex = c.blockIndex
        let event = SetLogEvent(
            itemID: item.id,
            setIndex: c.setIndex,
            loggedReps: reps,
            loggedRir: rir
        )
        let logMutation: SessionMutation = .finalizeCompositeSet(
            itemID: item.id,
            setIndex: c.setIndex,
            loggedReps: reps,
            loggedRir: rir,
            now: clock.now
        )
        let prescribedLoadKg = prescribedLoadForLog(itemID: item.id, setIndex: c.setIndex)
        let outcome = driver.onSetLogged(state: state, context: context, event: event)
        let postLogState = SessionReducer.reduce(state, logMutation)
        apply(buildLogMutations(
            logMutation: logMutation,
            outcome: outcome,
            item: item,
            postLogState: postLogState
        ))
        if !enterBlockTransitionIfNeeded(from: previousBlockIndex) {
            prepareExplicitSetStartIfNeeded()
        }
        handleLogSetSideEffects(
            item: item,
            event: event,
            outcome: outcome,
            prescribedLoadKg: prescribedLoadKg
        )
    }

    func compositeUnitLabel(for progress: SessionState.CompositeSetProgress) -> String {
        switch progress.kind {
        case .cluster:
            return "cluster"
        }
    }
}
