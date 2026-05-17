// ExecutionProjection.swift
//
// Shared read-model seam for execution surfaces. Preview, Active/Rest,
// History correction, and Watch mapping should ask this layer what the
// current workout state means instead of re-deriving cursor/progress rules.

import Foundation
import CoreDomain
import CoreSession

public struct CurrentTaskPresentation: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case today
        case active
        case transition
        case rest
        case complete
    }

    public let kind: Kind
    public let blockIndex: Int?
    public let blockCount: Int
    public let blockName: String?
    public let blockIntent: String?
    public let exerciseName: String?
    public let title: String
    public let detail: String?
    public let primaryMetric: String?
    public let secondaryMetric: String?
    public let side: SetLogSide
    public let skipped: Bool

    public init(
        kind: Kind,
        blockIndex: Int?,
        blockCount: Int,
        blockName: String?,
        blockIntent: String?,
        exerciseName: String?,
        title: String,
        detail: String?,
        primaryMetric: String?,
        secondaryMetric: String?,
        side: SetLogSide,
        skipped: Bool
    ) {
        self.kind = kind
        self.blockIndex = blockIndex
        self.blockCount = blockCount
        self.blockName = blockName
        self.blockIntent = blockIntent
        self.exerciseName = exerciseName
        self.title = title
        self.detail = detail
        self.primaryMetric = primaryMetric
        self.secondaryMetric = secondaryMetric
        self.side = side
        self.skipped = skipped
    }
}

public struct RemainingWorkPresentation: Equatable, Sendable {
    public let completedSets: Int
    public let totalSets: Int
    public let remainingSets: Int

    public init(completedSets: Int, totalSets: Int, remainingSets: Int) {
        self.completedSets = completedSets
        self.totalSets = totalSets
        self.remainingSets = remainingSets
    }
}

public struct UpcomingWorkPresentation: Equatable, Sendable {
    public let label: String
    public let title: String
    public let detail: String?

    public init(label: String, title: String, detail: String?) {
        self.label = label
        self.title = title
        self.detail = detail
    }
}

public struct BlockProgressPresentation: Equatable, Sendable {
    public let blockIndex: Int
    public let blockCount: Int
    public let blockName: String?
    public let blockIntent: String?
    public let completedSets: Int
    public let totalSets: Int

    public var remainingSets: Int {
        max(0, totalSets - completedSets)
    }

    public init(
        blockIndex: Int,
        blockCount: Int,
        blockName: String?,
        blockIntent: String?,
        completedSets: Int,
        totalSets: Int
    ) {
        self.blockIndex = blockIndex
        self.blockCount = blockCount
        self.blockName = blockName
        self.blockIntent = blockIntent
        self.completedSets = completedSets
        self.totalSets = totalSets
    }
}

public struct ExecutionEditability: Equatable, Sendable {
    public let canStartCurrentSet: Bool
    public let canLogCurrentWork: Bool
    public let canAdvance: Bool
    public let canExtendRest: Bool
    public let canEditPendingSet: Bool
    public let canEditLoggedSet: Bool
    public let canSwapExercise: Bool
    public let canCompleteWorkout: Bool

    public init(
        canStartCurrentSet: Bool,
        canLogCurrentWork: Bool,
        canAdvance: Bool,
        canExtendRest: Bool,
        canEditPendingSet: Bool,
        canEditLoggedSet: Bool,
        canSwapExercise: Bool,
        canCompleteWorkout: Bool
    ) {
        self.canStartCurrentSet = canStartCurrentSet
        self.canLogCurrentWork = canLogCurrentWork
        self.canAdvance = canAdvance
        self.canExtendRest = canExtendRest
        self.canEditPendingSet = canEditPendingSet
        self.canEditLoggedSet = canEditLoggedSet
        self.canSwapExercise = canSwapExercise
        self.canCompleteWorkout = canCompleteWorkout
    }
}

public struct ExecutionProjection: Equatable, Sendable {
    public let currentTask: CurrentTaskPresentation
    public let remainingWork: RemainingWorkPresentation
    public let upcomingWork: UpcomingWorkPresentation?
    public let workQueue: [UpcomingWorkPresentation]
    public let blockProgress: BlockProgressPresentation?
    public let editability: ExecutionEditability
    public let timer: ExecutionTimerPresentation?

    public init(
        currentTask: CurrentTaskPresentation,
        remainingWork: RemainingWorkPresentation,
        upcomingWork: UpcomingWorkPresentation?,
        workQueue: [UpcomingWorkPresentation] = [],
        blockProgress: BlockProgressPresentation?,
        editability: ExecutionEditability,
        timer: ExecutionTimerPresentation?
    ) {
        self.currentTask = currentTask
        self.remainingWork = remainingWork
        self.upcomingWork = upcomingWork
        self.workQueue = workQueue
        self.blockProgress = blockProgress
        self.editability = editability
        self.timer = timer
    }
}

extension ExecutionViewModel {
    public func executionProjection(now: Date) -> ExecutionProjection {
        ExecutionProjection(
            currentTask: currentTaskPresentation(),
            remainingWork: remainingWorkPresentation(),
            upcomingWork: upcomingWorkPresentation(),
            workQueue: workQueuePresentation(),
            blockProgress: blockProgressPresentation(),
            editability: executionEditability(),
            timer: timerPresentation(now: now)
        )
    }

    private func currentTaskPresentation() -> CurrentTaskPresentation {
        let block = context.block(at: state.cursor.blockIndex)
        let content = activeContent

        switch state.route {
        case .today:
            return todayTaskPresentation(block: block, content: content)
        case .complete:
            return CurrentTaskPresentation(
                kind: .complete,
                blockIndex: nil,
                blockCount: context.blocks.count,
                blockName: nil,
                blockIntent: nil,
                exerciseName: nil,
                title: "Complete",
                detail: context.workout.name,
                primaryMetric: nil,
                secondaryMetric: nil,
                side: .bilateral,
                skipped: false
            )
        case .rest:
            return CurrentTaskPresentation(
                kind: .rest,
                blockIndex: validBlockIndex(),
                blockCount: context.blocks.count,
                blockName: block?.name,
                blockIntent: block?.intent,
                exerciseName: content?.exerciseName,
                title: "Rest",
                detail: content?.exerciseName,
                primaryMetric: nil,
                secondaryMetric: nil,
                side: .bilateral,
                skipped: false
            )
        case .transition:
            return CurrentTaskPresentation(
                kind: .transition,
                blockIndex: validBlockIndex(),
                blockCount: context.blocks.count,
                blockName: block?.name,
                blockIntent: block?.intent,
                exerciseName: content?.exerciseName,
                title: "Transition",
                detail: block?.name,
                primaryMetric: nil,
                secondaryMetric: nil,
                side: .bilateral,
                skipped: false
            )
        case .active:
            return activeTaskPresentation(block: block, content: content)
        }
    }

    private func activeTaskPresentation(
        kind: CurrentTaskPresentation.Kind = .active,
        block: Block?,
        content: ActiveContent?
    ) -> CurrentTaskPresentation {
        guard let content else {
            return CurrentTaskPresentation(
                kind: kind,
                blockIndex: validBlockIndex(),
                blockCount: context.blocks.count,
                blockName: block?.name,
                blockIntent: block?.intent,
                exerciseName: nil,
                title: "Work",
                detail: nil,
                primaryMetric: nil,
                secondaryMetric: nil,
                side: .bilateral,
                skipped: false
            )
        }

        return CurrentTaskPresentation(
            kind: kind,
            blockIndex: validBlockIndex(),
            blockCount: context.blocks.count,
            blockName: block?.name,
            blockIntent: block?.intent,
            exerciseName: content.exerciseName,
            title: content.exerciseName,
            detail: detail(for: content, block: block),
            primaryMetric: primaryMetric(for: content),
            secondaryMetric: secondaryMetric(for: content),
            side: .bilateral,
            skipped: false
        )
    }

    private func todayTaskPresentation(
        block: Block?,
        content: ActiveContent?
    ) -> CurrentTaskPresentation {
        if isZeroItemBlock(at: state.cursor.blockIndex) {
            return CurrentTaskPresentation(
                kind: .today,
                blockIndex: validBlockIndex(),
                blockCount: context.blocks.count,
                blockName: block?.name,
                blockIntent: block?.intent,
                exerciseName: nil,
                title: "Rest",
                detail: block?.name,
                primaryMetric: nil,
                secondaryMetric: nil,
                side: .bilateral,
                skipped: false
            )
        }
        guard content != nil else {
            return CurrentTaskPresentation(
                kind: .today,
                blockIndex: nil,
                blockCount: context.blocks.count,
                blockName: nil,
                blockIntent: nil,
                exerciseName: nil,
                title: context.workout.name,
                detail: "Not started",
                primaryMetric: nil,
                secondaryMetric: nil,
                side: .bilateral,
                skipped: false
            )
        }
        return activeTaskPresentation(kind: .today, block: block, content: content)
    }

    private func remainingWorkPresentation() -> RemainingWorkPresentation {
        let counts = context.itemsByBlock.enumerated().reduce((completed: 0, total: 0)) { partial, entry in
            let blockIndex = entry.offset
            guard let block = context.block(at: blockIndex),
                  !usesUnboundedSetCount(block) else {
                return partial
            }
            let itemIDs = Set(entry.element.map(\.id))
            let logs = state.items.filter { itemIDs.contains($0.itemID) }
            return (
                completed: partial.completed + logs.reduce(0) { $0 + $1.sets.filter(\.done).count },
                total: partial.total + logs.reduce(0) { $0 + $1.sets.count }
            )
        }
        return RemainingWorkPresentation(
            completedSets: counts.completed,
            totalSets: counts.total,
            remainingSets: max(0, counts.total - counts.completed)
        )
    }

    private func upcomingWorkPresentation() -> UpcomingWorkPresentation? {
        nextUpPresentation.map {
            UpcomingWorkPresentation(
                label: $0.label,
                title: $0.title,
                detail: $0.detail
            )
        }
    }

    private func workQueuePresentation() -> [UpcomingWorkPresentation] {
        guard state.route == .today || state.route == .active || state.route == .rest else {
            return []
        }

        var rows: [UpcomingWorkPresentation] = []
        if let blockProgress = blockProgressPresentation(),
           blockProgress.remainingSets > 0 {
            rows.append(UpcomingWorkPresentation(
                label: "current block",
                title: blockProgress.blockName ?? "Current block",
                detail: "\(blockProgress.remainingSets) \(blockProgress.remainingSets == 1 ? "set" : "sets") left"
            ))
        }

        let upcoming = upcomingWorkPresentation()
        if let upcoming {
            rows.append(upcoming)
        }

        if let future = firstFutureBlockPresentation(),
           upcoming?.label != "next block" {
            rows.append(future)
        }
        return rows
    }

    private func firstFutureBlockPresentation() -> UpcomingWorkPresentation? {
        let nextBlockIndex = state.cursor.blockIndex + 1
        guard nextBlockIndex < state.structure.itemsPerBlock.count else {
            return nil
        }
        let futureCursor = SessionState.Cursor(
            blockIndex: nextBlockIndex,
            itemIndex: 0,
            setIndex: 1
        )
        return previewPresentation(for: futureCursor, label: "future block")
    }

    private func previewPresentation(
        for cursor: SessionState.Cursor,
        label: String
    ) -> UpcomingWorkPresentation? {
        if isZeroItemBlock(at: cursor.blockIndex) {
            return UpcomingWorkPresentation(
                label: label,
                title: context.block(at: cursor.blockIndex)?.name ?? "Rest block",
                detail: nil
            )
        }
        var previewState = state
        previewState.cursor = cursor
        guard let block = context.block(at: cursor.blockIndex),
              let content = driverRegistry
                .driver(for: block.timingMode)
                .activeContent(state: previewState, context: context) else {
            return nil
        }
        let nextUp = ExecutionNextUpPresentation(
            label: label,
            title: content.exerciseName,
            detail: previewDetail(for: content)
        )
        return UpcomingWorkPresentation(
            label: nextUp.label,
            title: nextUp.title,
            detail: nextUp.detail
        )
    }

    private func previewDetail(for content: ActiveContent) -> String {
        switch content.kind {
        case .strength:
            return "\(content.loadDisplay) · \(content.repsDisplay) reps"
        case .cardio:
            return "\(content.repsDisplay) · \(content.loadDisplay)"
        }
    }

    private func blockProgressPresentation() -> BlockProgressPresentation? {
        guard let blockIndex = validBlockIndex(),
              let block = context.block(at: blockIndex) else {
            return nil
        }
        let itemIDs = Set(context.itemsByBlock[safe: blockIndex]?.map(\.id) ?? [])
        let itemLogs = state.items.filter { itemIDs.contains($0.itemID) }
        let total = usesUnboundedSetCount(block)
            ? 0
            : itemLogs.reduce(0) { $0 + $1.sets.count }
        let completed = usesUnboundedSetCount(block)
            ? 0
            : itemLogs.reduce(0) { partial, item in
                partial + item.sets.filter(\.done).count
            }
        return BlockProgressPresentation(
            blockIndex: blockIndex,
            blockCount: context.blocks.count,
            blockName: block.name,
            blockIntent: block.intent,
            completedSets: completed,
            totalSets: total
        )
    }

    private func executionEditability() -> ExecutionEditability {
        ExecutionEditability(
            canStartCurrentSet: state.route == .active
                && requiresExplicitSetStartForCurrentWork
                && state.workStartedAt == nil,
            canLogCurrentWork: state.route == .active && canLogCurrentWork(),
            canAdvance: state.route == .rest,
            canExtendRest: state.route == .rest && !currentRestShouldAutoAdvance,
            canEditPendingSet: activeSetPlan.map { !$0.done } ?? false,
            canEditLoggedSet: lastLoggedSet != nil,
            canSwapExercise: canSwapCurrentExercise(),
            canCompleteWorkout: state.route == .active || state.route == .rest || state.route == .transition
        )
    }

    private func canSwapCurrentExercise() -> Bool {
        guard state.route == .active,
              let item = context.item(
                at: state.cursor.blockIndex,
                itemIndex: state.cursor.itemIndex
              ) else {
            return false
        }
        return !context.alternatives(for: item.id).isEmpty
    }

    private func primaryMetric(for content: ActiveContent) -> String? {
        switch content.kind {
        case .strength:
            return content.loadDisplay
        case .cardio:
            return content.repsDisplay
        }
    }

    private func secondaryMetric(for content: ActiveContent) -> String? {
        switch content.kind {
        case .strength:
            return "\(content.repsDisplay) reps"
        case .cardio:
            return content.loadDisplay
        }
    }

    private func detail(for content: ActiveContent, block: Block?) -> String? {
        guard let block else {
            return boundedDetail(label: "Set", index: content.setIndex, total: content.totalSets)
        }
        switch block.timingMode {
        case .continuous:
            return "Continuous"
        case .emom, .intervals:
            return boundedDetail(label: "Interval", index: content.setIndex, total: content.totalSets)
        case .amrap, .forTime, .tabata:
            return boundedDetail(label: "Round", index: content.setIndex, total: content.totalSets)
        case .straightSets, .superset, .circuit, .accumulate, .custom, .rest:
            return boundedDetail(label: "Set", index: content.setIndex, total: content.totalSets)
        }
    }

    private func boundedDetail(label: String, index: Int, total: Int) -> String {
        guard total > 0 else { return "\(label) \(index)" }
        return "\(label) \(index) of \(total)"
    }

    private func usesUnboundedSetCount(_ block: Block) -> Bool {
        block.timingMode == .amrap || block.timingMode == .emom || block.timingMode == .accumulate
    }

    private func isZeroItemBlock(at blockIndex: Int) -> Bool {
        guard blockIndex >= 0, blockIndex < state.structure.itemsPerBlock.count else {
            return false
        }
        return state.structure.itemsPerBlock[blockIndex] == 0
    }

    private func validBlockIndex() -> Int? {
        let index = state.cursor.blockIndex
        guard index >= 0, index < context.blocks.count else { return nil }
        return index
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
