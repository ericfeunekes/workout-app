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
                state: state
            )
        }
    }

    func logAMRAPPartialResult(extraReps: Int) {
        guard currentTimingMode == .amrap else { return }
        let cursor = state.cursor
        let safeExtra = max(0, extraReps)
        let currentItem = context.item(at: cursor.blockIndex, itemIndex: cursor.itemIndex)
        let currentName = currentItem.map { context.exerciseName(for: $0) } ?? "current station"
        let score = amrapScoreSummary(cursor: cursor, currentExtraReps: safeExtra)
        let partial = safeExtra > 0
            ? "partial: \(currentName) \(safeExtra) reps"
            : "partial: no extra reps"
        let note = "AMRAP result: \(score). \(partial)"
        let now = clock.now
        let completedAt = boundedBlockCompletionAt(now: now)

        if safeExtra > 0, let item = currentItem {
            apply([
                .logSet(itemID: item.id, setIndex: cursor.setIndex, loggedReps: safeExtra, loggedRir: nil, now: now),
                .appendNote(note),
            ])
            emitSessionMutation("logSet")
            enqueueLoggedSet(item: item, setIndex: cursor.setIndex, reps: safeExtra, rir: nil)
        } else {
            apply([.appendNote(note)])
        }

        recordPrimitiveAMRAPResult(
            cursor: cursor,
            partialReps: safeExtra,
            completedAt: completedAt
        )
        finishCurrentTimedBlockFromResult()
    }

    public func logForTimeResult() {
        guard currentTimingMode == .forTime else { return }
        let cursor = state.cursor
        guard let item = context.item(at: cursor.blockIndex, itemIndex: 0) else {
            return
        }
        let elapsed = state.workStartedAt.map { max(0, clock.now.timeIntervalSince($0)) } ?? 0
        let input = CardioLogInput(durationSec: elapsed, startedAt: state.workStartedAt)
        let now = clock.now
        apply([
            .logCardioSet(
                itemID: item.id,
                setIndex: 1,
                durationSec: input.durationSec,
                distanceM: input.distanceM,
                hrAvgBpm: input.hrAvgBpm,
                cadenceAvgSpm: input.cadenceAvgSpm,
                startedAt: input.startedAt,
                now: now
            ),
            .appendNote("For Time result: \(formatDuration(seconds: elapsed))"),
        ])
        emitSessionMutation("logCardioSet")
        enqueueLoggedCardioSet(item: item, setIndex: 1, input: input)
        recordPrimitiveForTimeResult(
            blockIndex: cursor.blockIndex,
            durationSec: elapsed,
            completedAt: now
        )
        finishCurrentTimedBlockFromResult()
    }

    private func recordPrimitiveAMRAPResult(
        cursor: SessionState.Cursor,
        partialReps: Int,
        completedAt: Date
    ) {
        guard let plan = context.primitiveExecutionPlan,
              cursor.blockIndex >= 0,
              cursor.blockIndex < plan.blocks.count else {
            return
        }
        let block = plan.blocks[cursor.blockIndex]
        guard let setIndex = block.sets.firstIndex(where: { set in
            set.traversal == .amrap && set.hasObservationTarget(.rounds)
        }) else {
            return
        }
        let primitiveSet = block.sets[setIndex]
        let duration = state.workStartedAt.map { max(0, completedAt.timeIntervalSince($0)) }
            ?? primitiveSet.timing.capSec.map(Double.init)
        recordPrimitiveSetResult(
            blockIndex: cursor.blockIndex,
            setIndexInBlock: setIndex,
            reps: partialReps,
            rounds: max(0, cursor.setIndex - 1),
            durationSec: duration,
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
        currentExtraReps: Int
    ) -> String {
        let completedRounds = max(0, cursor.setIndex - 1)
        let priorStationReps = amrapPrescribedRepsBeforeCurrentStation(cursor: cursor)
        let extraReps = priorStationReps + currentExtraReps
        return "\(completedRounds) rounds + \(extraReps) reps"
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
