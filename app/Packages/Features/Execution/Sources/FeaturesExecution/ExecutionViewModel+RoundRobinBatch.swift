// ExecutionViewModel+RoundRobinBatch.swift
//
// Batch logging for round-robin strength work. Supersets default here:
// the athlete moves station-to-station, then edits/logs the whole round
// during the shared rest instead of being forced through a sheet between
// exercises.

import Foundation
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation

public struct RoundRobinBatchSetRow: Identifiable, Equatable {
    public let itemID: UUID
    public let setIndex: Int
    public let exerciseName: String
    public let loadKg: Double?
    public let unit: WeightUnit
    public let reps: Int
    public let rir: Int?
    public let done: Bool

    public var id: String {
        "\(itemID.uuidString)-\(setIndex)"
    }
}

extension ExecutionViewModel {

    public var isCurrentRoundRobinBatchMode: Bool {
        roundRobinLoggingModeForCurrentBlock() == .batchAtRoundRest
    }

    public var isRoundRobinBatchRoundRest: Bool {
        guard state.route == .rest,
              isCurrentRoundRobinBatchMode else {
            return false
        }
        return isLastRoundRobinItem
    }

    public var isFinalRoundRobinBatchRoundRest: Bool {
        isRoundRobinBatchRoundRest && isLastRoundRobinRound
    }

    public func roundRobinBatchRows() -> [RoundRobinBatchSetRow] {
        guard isCurrentRoundRobinBatchMode else { return [] }
        let cursor = state.cursor
        guard context.block(at: cursor.blockIndex) != nil else { return [] }
        return context.itemsByBlock[cursor.blockIndex].compactMap { item in
            guard let itemLog = state.items.first(where: { $0.itemID == item.id }),
                  let set = itemLog.sets.first(where: { $0.setIndex == cursor.setIndex }) else {
                return nil
            }
            return RoundRobinBatchSetRow(
                itemID: item.id,
                setIndex: cursor.setIndex,
                exerciseName: context.exerciseName(
                    for: item,
                    performedExerciseID: itemLog.performedExerciseID
                ),
                loadKg: set.loadKg,
                unit: set.unit,
                reps: set.reps,
                rir: set.rir,
                done: set.done
            )
        }
    }

    public func advanceRoundRobinBatchStation() {
        guard state.route == .active,
              isCurrentRoundRobinBatchMode else {
            return
        }
        completeCurrentCompositeSetForBatchAdvanceIfNeeded()
        markCurrentRoundRobinBatchStationStarted()
        if isLastRoundRobinItem {
            apply([.enterRest(durationSec: driver.restDuration(state: state, context: context), now: clock.now)])
            return
        }

        emitSessionMutation("advance_batch_station")
        apply([.advanceFromRest])
        enterRestIfZeroItemBlock()
        enterTabataWorkWindowIfNeeded()
        enterBlockTimerIfNeeded()
        prepareExplicitSetStartIfNeeded()
    }

    public func commitRoundRobinBatchRoundIfNeeded() {
        guard isCurrentRoundRobinBatchMode else { return }
        let rows = roundRobinBatchRows().filter { !$0.done }
        guard !rows.isEmpty else { return }

        let itemsByID = Dictionary(
            uniqueKeysWithValues: context.itemsByBlock[state.cursor.blockIndex].map { ($0.id, $0) }
        )
        let logInputs: [(WorkoutItem, SetLogEvent, Double?)] = rows.compactMap { row in
            guard let item = itemsByID[row.itemID] else { return nil }
            let prescribedLoad = prescribedLoadForLog(itemID: row.itemID, setIndex: row.setIndex)
            let event = SetLogEvent(
                itemID: row.itemID,
                setIndex: row.setIndex,
                loggedReps: row.reps,
                loggedRir: row.rir
            )
            return (item, event, prescribedLoad)
        }
        let mutations = logInputs.map { input in
            if isCompositeSetCompletePendingLog(itemID: input.1.itemID, setIndex: input.1.setIndex) {
                return SessionMutation.finalizeCompositeSet(
                    itemID: input.1.itemID,
                    setIndex: input.1.setIndex,
                    loggedReps: input.1.loggedReps,
                    loggedRir: input.1.loggedRir,
                    now: clock.now
                )
            }
            return SessionMutation.logSet(
                itemID: input.1.itemID,
                setIndex: input.1.setIndex,
                loggedReps: input.1.loggedReps,
                loggedRir: input.1.loggedRir,
                now: clock.now
            )
        }
        state.workStartedAt = nil
        apply(mutations)
        for (item, event, prescribedLoad) in logInputs {
            handleLogSetSideEffects(
                item: item,
                event: event,
                outcome: DriverLogOutcome(),
                prescribedLoadKg: prescribedLoad
            )
        }
    }

    private func completeCurrentCompositeSetForBatchAdvanceIfNeeded() {
        guard let progress = activeCompositeSet,
              isCurrentCompositeSlotFinal,
              state.workStartedAt != nil else {
            return
        }
        apply([.completeCompositeSlot(
            itemID: progress.itemID,
            setIndex: progress.setIndex,
            now: clock.now
        )])
    }

    private func isCompositeSetCompletePendingLog(itemID: UUID, setIndex: Int) -> Bool {
        guard let progress = state.compositeSets.first(where: {
            $0.itemID == itemID && $0.setIndex == setIndex
        }) else {
            return false
        }
        if case .completePendingLog = progress.phase {
            return true
        }
        return false
    }

    public func editRoundRobinBatchSet(
        itemID: UUID,
        setIndex: Int,
        loadKg: Double?,
        reps: Int?,
        rir: Int?
    ) {
        let row = roundRobinBatchRows().first {
            $0.itemID == itemID && $0.setIndex == setIndex
        }
        if row?.done == true {
            editPastSet(itemID: itemID, setIndex: setIndex, loadKg: loadKg, reps: reps, rir: rir)
        } else {
            editPendingSet(itemID: itemID, setIndex: setIndex, loadKg: loadKg, reps: reps, rir: rir)
        }
    }

    private func markCurrentRoundRobinBatchStationStarted() {
        let cursor = state.cursor
        guard let item = context.item(at: cursor.blockIndex, itemIndex: cursor.itemIndex) else {
            return
        }
        let startedAt = state.workStartedAt ?? clock.now
        apply([.markPendingSetStarted(
            itemID: item.id,
            setIndex: cursor.setIndex,
            startedAt: startedAt
        )])
    }

    func roundRobinLoggingModeForCurrentBlock() -> RoundRobinLoggingMode? {
        let cursor = state.cursor
        guard let block = context.block(at: cursor.blockIndex) else { return nil }
        let parser = PrescriptionParser()
        switch parser.parseTimingConfig(
            timingMode: block.timingMode.rawValue,
            configJSON: block.timingConfigJSON
        ) {
        case .success(.superset(_, let loggingMode)):
            return loggingMode
        case .success(.circuit(_, _, let loggingMode)):
            return loggingMode
        case .success, .failure:
            return nil
        }
    }

    private var isLastRoundRobinItem: Bool {
        let cursor = state.cursor
        guard cursor.blockIndex < state.structure.itemsPerBlock.count else { return false }
        return cursor.itemIndex + 1 >= state.structure.itemsPerBlock[cursor.blockIndex]
    }

    private var isLastRoundRobinRound: Bool {
        let cursor = state.cursor
        guard cursor.blockIndex < state.structure.setsPerItem.count,
              cursor.itemIndex < state.structure.setsPerItem[cursor.blockIndex].count else {
            return false
        }
        return cursor.setIndex >= state.structure.setsPerItem[cursor.blockIndex][cursor.itemIndex]
    }
}
