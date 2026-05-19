// ExecutionViewModel+MetconResult.swift

import Foundation
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation

extension ExecutionViewModel {
    @discardableResult
    func logAMRAPStation(reps: Int) -> Bool {
        guard currentTimingMode == .amrap,
              !isAMRAPCapExpired else {
            return false
        }
        if let set = activeSetPlan,
           activeKind(for: set) == .cardio {
            let elapsed = state.workStartedAt.map { clock.now.timeIntervalSince($0) }
            logCardioSet(CardioLogInput(
                durationSec: canonicalDurationForLog(set: set, elapsed: elapsed),
                distanceM: canonicalDistanceForLog(set: set),
                startedAt: state.workStartedAt
            ))
            return true
        }
        logSet(loadKg: activeSetPlan?.loadKg, reps: reps, rir: nil)
        return true
    }

    func amrapPartialResultItems() -> [AMRAPPartialResultItem] {
        let cursor = state.cursor
        guard cursor.blockIndex >= 0,
              cursor.blockIndex < context.itemsByBlock.count else {
            return []
        }
        let parser = PrescriptionParser()
        return context.itemsByBlock[cursor.blockIndex].enumerated().map { offset, item in
            let state: AMRAPPartialResultItem.State
            if offset < cursor.itemIndex {
                state = .completed
            } else if offset == cursor.itemIndex {
                state = .current
            } else {
                state = .locked
            }
            return AMRAPPartialResultItem(
                id: item.id,
                name: context.exerciseName(for: item),
                prescription: amrapPrescriptionSummary(item: item, parser: parser),
                resultLabel: amrapResultLabel(itemOffset: offset),
                state: state
            )
        }
    }

    func logAMRAPPartialResult(extraReps: Int) {
        logAMRAPPartialResult(value: Double(max(0, extraReps)))
    }

    func logAMRAPPartialResult(value: Double) {
        guard currentTimingMode == .amrap else { return }
        let cursor = state.cursor
        let safeValue = max(0, value)
        let currentItem = context.item(at: cursor.blockIndex, itemIndex: cursor.itemIndex)
        let currentName = currentItem.map { context.exerciseName(for: $0) } ?? "current station"
        let metric = currentPrimitiveSlot()?.resultInputContract?.metric ?? .reps
        let score = amrapScoreSummary(cursor: cursor, currentExtraValue: safeValue, metric: metric)
        let partial = safeValue > 0
            ? "partial: \(currentName) \(formatPrimitiveResultValue(safeValue, metric: metric))"
            : "partial: no extra \(primitiveResultNoun(metric))"
        let note = "AMRAP result: \(score). \(partial)"
        let now = clock.now
        let completedAt = boundedBlockCompletionAt(now: now)

        if safeValue > 0, let item = currentItem {
            applyPrimitivePartialResult(
                item: item,
                setIndex: cursor.setIndex,
                value: safeValue,
                metric: metric,
                note: note,
                now: now
            )
        } else {
            apply([.appendNote(note)])
        }

        recordPrimitiveAMRAPResult(
            cursor: cursor,
            partialValue: safeValue,
            partialMetric: metric,
            completedAt: completedAt
        )
        finishCurrentTimedBlockFromResult()
    }

    public func logForTimeResult() {
        guard currentTimingMode == .forTime else { return }
        let cursor = state.cursor
        let elapsed = state.workStartedAt.map { max(0, clock.now.timeIntervalSince($0)) } ?? 0
        let now = clock.now
        apply([.appendNote("For Time result: \(formatDuration(seconds: elapsed))")])
        recordPrimitiveForTimeResult(
            blockIndex: cursor.blockIndex,
            durationSec: elapsed,
            completedAt: now
        )
        finishCurrentTimedBlockFromResult()
    }

    private func recordPrimitiveAMRAPResult(
        cursor: SessionState.Cursor,
        partialValue: Double,
        partialMetric: PrimitiveResultMetric,
        completedAt: Date
    ) {
        guard let plan = context.primitiveExecutionPlan,
              cursor.blockIndex >= 0,
              cursor.blockIndex < plan.blocks.count else {
            return
        }
        let block = plan.blocks[cursor.blockIndex]
        guard let setIndex = currentPrimitiveAMRAPSetIndex(block: block, cursor: cursor) else {
            return
        }
        let primitiveSet = block.sets[setIndex]
        let duration = state.workStartedAt.map { max(0, completedAt.timeIntervalSince($0)) }
            ?? primitiveSet.timing.capSec.map(Double.init)
        let totalMetricValue = amrapPrimitiveMetricTotalThroughPartial(
            cursor: cursor,
            metric: partialMetric,
            partialValue: partialValue
        ) ?? partialValue
        if partialMetric != .rounds {
            recordPrimitivePartialSlotResult(
                cursor: cursor,
                value: partialValue,
                metric: partialMetric,
                completedAt: completedAt
            )
        }
        recordPrimitiveSetResult(
            blockIndex: cursor.blockIndex,
            setIndexInBlock: setIndex,
            reps: partialMetric == .reps ? Int(totalMetricValue.rounded()) : nil,
            rounds: partialMetric == .rounds
                ? Int(totalMetricValue.rounded())
                : max(0, cursor.setIndex - 1),
            durationSec: duration,
            distanceM: partialMetric == .distance ? totalMetricValue : nil,
            weight: partialMetric == .loadCarried ? totalMetricValue : nil,
            weightUnit: partialMetric == .loadCarried ? currentPrimitiveSlot()?.loadUnit : nil,
            completedAt: completedAt
        )
    }

    private func recordPrimitiveForTimeResult(
        blockIndex: Int,
        durationSec: Double,
        completedAt: Date
    ) {
        guard let plan = context.primitiveExecutionPlan,
              blockIndex >= 0,
              blockIndex < plan.blocks.count else {
            return
        }
        let block = plan.blocks[blockIndex]
        if block.hasObservationTarget(.duration) {
            recordPrimitiveBlockResult(
                blockIndex: blockIndex,
                durationSec: durationSec,
                completedAt: completedAt
            )
        }
        for (setIndex, set) in block.sets.enumerated() where set.hasObservationTarget(.duration) {
            recordPrimitiveSetResult(
                blockIndex: blockIndex,
                setIndexInBlock: setIndex,
                durationSec: durationSec,
                completedAt: completedAt
            )
        }
    }

    private func amrapPrescriptionSummary(
        item: WorkoutItem,
        parser: PrescriptionParser
    ) -> String {
        let plan = SessionSeeder.itemPlan(for: item, parser: parser)
        var parts: [String] = []
        if let target = plan.workTarget {
            parts.append(displayText(for: target))
        } else if plan.reps > 0 {
            parts.append("\(plan.reps) reps")
        }
        if let loadKg = plan.loadKg {
            parts.append(formatLoad(weight: loadKg, unit: LoadUnit(setPlanUnit: plan.unit)))
        }
        return parts.joined(separator: " · ")
    }

    private func amrapResultLabel(itemOffset: Int) -> String {
        guard let block = context.primitiveExecutionPlan?.blocks[safe: state.cursor.blockIndex] else {
            return "reps"
        }
        if let item = context.item(at: state.cursor.blockIndex, itemIndex: itemOffset) {
            let exerciseMatches = block.sets
                .flatMap(\.slots)
                .filter { $0.exerciseID == item.exerciseID }
            if exerciseMatches.count == 1,
               let metric = exerciseMatches[0].resultInputContract?.metric {
                return primitiveResultNoun(metric)
            }
        }
        for set in block.sets {
            if let metric = set.slots[safe: itemOffset]?.resultInputContract?.metric {
                return primitiveResultNoun(metric)
            }
        }
        return "reps"
    }

    private var currentTimingMode: TimingMode? {
        context.block(at: state.cursor.blockIndex)?.timingMode
    }

    private var isAMRAPCapExpired: Bool {
        guard currentTimingMode == .amrap,
              let blockEndsAt = state.blockEndsAt else {
            return false
        }
        return clock.now >= blockEndsAt
    }

    private func boundedBlockCompletionAt(now: Date) -> Date {
        guard let blockEndsAt = state.blockEndsAt, now > blockEndsAt else {
            return now
        }
        return blockEndsAt
    }

    private func amrapScoreSummary(
        cursor: SessionState.Cursor,
        currentExtraValue: Double,
        metric: PrimitiveResultMetric
    ) -> String {
        let completedRounds = max(0, cursor.setIndex - 1)
        if metric == .reps {
            let priorStationReps = amrapPrescribedRepsBeforeCurrentStation(cursor: cursor)
            let extraReps = priorStationReps + Int(currentExtraValue.rounded())
            return "\(completedRounds) rounds + \(extraReps) reps"
        }
        let totalValue = amrapPrimitiveMetricTotalThroughPartial(
            cursor: cursor,
            metric: metric,
            partialValue: currentExtraValue
        ) ?? currentExtraValue
        return "\(completedRounds) rounds + \(formatPrimitiveResultValue(totalValue, metric: metric))"
    }

    private func amrapPrescribedRepsBeforeCurrentStation(
        cursor: SessionState.Cursor
    ) -> Int {
        guard cursor.blockIndex >= 0,
              cursor.blockIndex < context.itemsByBlock.count,
              cursor.itemIndex > 0 else {
            return 0
        }
        let parser = PrescriptionParser()
        return context.itemsByBlock[cursor.blockIndex]
            .prefix(cursor.itemIndex)
            .reduce(0) { total, item in
                let (reps, _, _) = SessionSeeder.itemRepsAndLoad(for: item, parser: parser)
                return total + max(0, reps)
            }
    }

    private func amrapPrimitiveMetricTotalThroughPartial(
        cursor: SessionState.Cursor,
        metric: PrimitiveResultMetric,
        partialValue: Double
    ) -> Double? {
        if metric == .reps {
            return Double(amrapPrescribedRepsBeforeCurrentStation(cursor: cursor))
                + partialValue
        }
        guard cursor.blockIndex >= 0,
              let block = context.primitiveExecutionPlan?.blocks[safe: cursor.blockIndex],
              let setIndex = currentPrimitiveAMRAPSetIndex(block: block, cursor: cursor)
        else {
            return nil
        }
        let set = block.sets[setIndex]
        let completedRounds = max(0, cursor.setIndex - 1)
        let perRound = set.slots.reduce(0.0) { total, slot in
            total + slot.primitiveCompletionValue(for: metric)
        }
        let priorThisRound = set.slots
            .prefix(max(0, cursor.itemIndex))
            .reduce(0.0) { total, slot in
                total + slot.primitiveCompletionValue(for: metric)
            }
        return (Double(completedRounds) * perRound) + priorThisRound + partialValue
    }

    private func applyPrimitivePartialResult(
        item: WorkoutItem,
        setIndex: Int,
        value: Double,
        metric: PrimitiveResultMetric,
        note: String,
        now: Date
    ) {
        switch metric {
        case .rounds:
            apply([.appendNote(note)])
        case .reps:
            let reps = Int(value.rounded())
            apply([
                .logSet(itemID: item.id, setIndex: setIndex, loggedReps: reps, loggedRir: nil, now: now),
                .appendNote(note),
            ])
            emitSessionMutation("logSet")
            enqueueLoggedSet(item: item, setIndex: setIndex, reps: reps, rir: nil)
        case .distance:
            apply([
                .logCardioSet(
                    itemID: item.id,
                    setIndex: setIndex,
                    durationSec: nil,
                    distanceM: value,
                    hrAvgBpm: nil,
                    cadenceAvgSpm: nil,
                    startedAt: state.workStartedAt,
                    now: now
                ),
                .appendNote(note),
            ])
            emitSessionMutation("logCardioSet")
            enqueueLoggedCardioSet(
                item: item,
                setIndex: setIndex,
                input: CardioLogInput(distanceM: value, startedAt: state.workStartedAt)
            )
        case .duration:
            apply([
                .logCardioSet(
                    itemID: item.id,
                    setIndex: setIndex,
                    durationSec: value,
                    distanceM: nil,
                    hrAvgBpm: nil,
                    cadenceAvgSpm: nil,
                    startedAt: state.workStartedAt,
                    now: now
                ),
                .appendNote(note),
            ])
            emitSessionMutation("logCardioSet")
            enqueueLoggedCardioSet(
                item: item,
                setIndex: setIndex,
                input: CardioLogInput(durationSec: value, startedAt: state.workStartedAt)
            )
        case .loadCarried, .completion:
            apply([.appendNote(note)])
        }
    }

    private func recordPrimitivePartialSlotResult(
        cursor: SessionState.Cursor,
        value: Double,
        metric: PrimitiveResultMetric,
        completedAt: Date
    ) {
        guard value > 0,
              let plan = context.primitiveExecutionPlan,
              let position = currentPrimitiveSlotPosition() else {
            return
        }
        let coordinate = primitivePartialSlotCoordinate(position: position, cursor: cursor)
        let log = position.slot.slotLog(
            workoutID: plan.workoutID,
            blockRepeatIndex: coordinate.blockRepeatIndex,
            setRepeatIndex: coordinate.setRepeatIndex,
            setIndex: coordinate.setIndex,
            reps: metric == .reps ? Int(value.rounded()) : nil,
            weight: metric == .loadCarried ? value : nil,
            weightUnit: metric == .loadCarried ? position.slot.loadUnit : nil,
            durationSec: metric == .duration ? value : nil,
            distanceM: metric == .distance ? value : nil,
            rir: nil,
            completedAt: completedAt
        )
        primitiveSetLogs.append(log)
        persist()
    }

    private func currentPrimitiveSlot() -> ExecutionSlot? {
        currentPrimitiveSlotPosition()?.slot
    }

    private struct PrimitiveSlotPosition {
        var slot: ExecutionSlot
        var set: ExecutionSet
        var slotIndex: Int
    }

    private struct PrimitiveSlotCommitCoordinate {
        var blockRepeatIndex: Int
        var setRepeatIndex: Int
        var setIndex: Int
    }

    private func primitivePartialSlotCoordinate(
        position: PrimitiveSlotPosition,
        cursor: SessionState.Cursor
    ) -> PrimitiveSlotCommitCoordinate {
        let zeroBasedLegacySetIndex = max(0, cursor.setIndex - 1)
        if position.set.traversal == .amrap {
            return PrimitiveSlotCommitCoordinate(
                blockRepeatIndex: 0,
                setRepeatIndex: 0,
                setIndex: zeroBasedLegacySetIndex * max(1, position.set.slots.count) + position.slotIndex
            )
        }
        if position.set.timing.mode == .timeBounded,
           position.set.timing.rounds != nil,
           position.set.setRepeat == 1 {
            return PrimitiveSlotCommitCoordinate(
                blockRepeatIndex: 0,
                setRepeatIndex: 0,
                setIndex: zeroBasedLegacySetIndex
            )
        }
        return PrimitiveSlotCommitCoordinate(
            blockRepeatIndex: 0,
            setRepeatIndex: zeroBasedLegacySetIndex,
            setIndex: position.slotIndex
        )
    }

    private func currentPrimitiveSlotPosition() -> PrimitiveSlotPosition? {
        let cursor = state.cursor
        guard let block = context.primitiveExecutionPlan?.blocks[safe: cursor.blockIndex],
              let currentItem = context.item(at: cursor.blockIndex, itemIndex: cursor.itemIndex) else {
            return nil
        }
        let itemCount = context.itemsByBlock[safe: cursor.blockIndex]?.count ?? 0
        guard let slot = block.slotForLegacyCursor(
            itemIndex: cursor.itemIndex,
            exerciseID: currentItem.exerciseID,
            itemCount: itemCount
        ) else {
            return nil
        }
        for set in block.sets {
            if let slotIndex = set.slots.firstIndex(where: { $0.slotID == slot.slotID }) {
                return PrimitiveSlotPosition(slot: slot, set: set, slotIndex: slotIndex)
            }
        }
        return nil
    }

    private func currentPrimitiveAMRAPSetIndex(
        block: ExecutionBlock,
        cursor: SessionState.Cursor
    ) -> Int? {
        let currentSlotID = currentPrimitiveSlot()?.slotID
        if let currentSlotID,
           let index = block.sets.firstIndex(where: { set in
               set.traversal == .amrap
                   && set.hasObservationTarget(.rounds)
                   && set.slots.contains(where: { $0.slotID == currentSlotID })
           }) {
            return index
        }
        return block.sets.firstIndex(where: { set in
            set.traversal == .amrap && set.hasObservationTarget(.rounds)
        })
    }

    private func formatPrimitiveResultValue(_ value: Double, metric: PrimitiveResultMetric) -> String {
        let formatted = value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
        switch metric {
        case .rounds:
            return "\(formatted) rounds"
        case .reps:
            return "\(formatted) reps"
        case .distance:
            return value >= 1000 ? "\(String(format: "%.2f", value / 1000.0)) km" : "\(formatted) m"
        case .duration:
            return formatDuration(seconds: value)
        case .loadCarried:
            return "\(formatted) load carried"
        case .completion:
            return "complete"
        }
    }

    private func primitiveResultNoun(_ metric: PrimitiveResultMetric) -> String {
        switch metric {
        case .rounds: "rounds"
        case .reps: "reps"
        case .distance: "distance"
        case .duration: "time"
        case .loadCarried: "load"
        case .completion: "work"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}

private extension ExecutionBlock {
    func hasObservationTarget(_ metric: PrimitiveMetric) -> Bool {
        workTargets.contains { $0.metric == metric && $0.role == .observation }
    }
}

private extension ExecutionSet {
    func hasObservationTarget(_ metric: PrimitiveMetric) -> Bool {
        workTargets.contains { $0.metric == metric && $0.role == .observation }
    }
}

private extension ExecutionSlot {
    func primitiveCompletionValue(for metric: PrimitiveResultMetric) -> Double {
        workTargets
            .first { $0.metric == metric.primitiveMetric && $0.role == .completion }
            .flatMap(\.value) ?? 0
    }
}
