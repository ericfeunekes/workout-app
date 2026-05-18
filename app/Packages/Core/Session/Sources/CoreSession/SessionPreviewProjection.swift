// SessionPreviewProjection.swift
//
// Feature-neutral preview semantics for a pre-start executable session plan.
// Features turn these facts into copy and layout; CoreSession owns the cursor,
// primitive target ordering, visible progress, and future-work semantics.

import Foundation
import CoreDomain
import WorkoutCoreFoundation

public struct SessionPreviewProjection: Equatable, Sendable {
    public var current: SessionPreviewWork?
    public var currentBlock: SessionPreviewBlock?
    public var remaining: SessionPreviewRemaining
    public var upcoming: [SessionPreviewWork]

    public init(
        current: SessionPreviewWork?,
        currentBlock: SessionPreviewBlock?,
        remaining: SessionPreviewRemaining,
        upcoming: [SessionPreviewWork]
    ) {
        self.current = current
        self.currentBlock = currentBlock
        self.remaining = remaining
        self.upcoming = upcoming
    }

    public init(
        plan: ExecutionPlan,
        cursor: SessionState.Cursor = SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
        upcomingLimit: Int = 3
    ) {
        let blockIndex = max(0, cursor.blockIndex)
        let block = plan.blocks[safe: blockIndex]
        let rows = plan.previewWorks()
        let currentIndex = rows.firstIndex { row in
            row.blockIndex == blockIndex
                && row.setIndexInBlock >= max(0, cursor.setIndex - 1)
        } ?? rows.firstIndex { $0.blockIndex >= blockIndex }

        self.current = currentIndex.map { rows[$0] }
        self.currentBlock = block.map {
            SessionPreviewBlock(
                blockIndex: blockIndex,
                blockID: $0.blockID,
                blockCount: plan.blocks.count,
                title: nil,
                repeatCount: $0.blockRepeat,
                workTargets: $0.workTargets
            )
        }
        self.remaining = block.map { SessionPreviewRemaining(block: $0, completedSets: 0) }
            ?? .bounded(completed: 0, total: 0)
        if let currentIndex {
            self.upcoming = Array(rows.dropFirst(currentIndex + 1).prefix(max(0, upcomingLimit)))
        } else {
            self.upcoming = Array(rows.prefix(max(0, upcomingLimit)))
        }
    }
}

public struct SessionPreviewBlock: Equatable, Sendable {
    public var blockIndex: Int
    public var blockID: BlockID
    public var blockCount: Int
    public var title: String?
    public var repeatCount: Int
    public var workTargets: [PrimitiveWorkTarget]

    public init(
        blockIndex: Int,
        blockID: BlockID,
        blockCount: Int,
        title: String?,
        repeatCount: Int,
        workTargets: [PrimitiveWorkTarget]
    ) {
        self.blockIndex = blockIndex
        self.blockID = blockID
        self.blockCount = blockCount
        self.title = title
        self.repeatCount = repeatCount
        self.workTargets = workTargets
    }
}

public struct SessionPreviewWork: Equatable, Sendable {
    public var blockIndex: Int
    public var blockID: BlockID
    public var setID: PrimitiveSetID
    public var setIndexInBlock: Int
    public var setRepeatIndex: Int
    public var slotID: PrimitiveSlotID
    public var slotIndex: Int
    public var exerciseID: ExerciseID
    public var primaryDisplayTarget: PrimitiveWorkTarget?
    public var secondaryDisplayTargets: [PrimitiveWorkTarget]
    public var loadKg: Double?
    public var loadUnit: WeightUnit?
    public var loadDisplayValue: Double?
    public var isWarmup: Bool

    public init(
        blockIndex: Int,
        blockID: BlockID,
        setID: PrimitiveSetID,
        setIndexInBlock: Int,
        setRepeatIndex: Int,
        slotID: PrimitiveSlotID,
        slotIndex: Int,
        exerciseID: ExerciseID,
        primaryDisplayTarget: PrimitiveWorkTarget?,
        secondaryDisplayTargets: [PrimitiveWorkTarget],
        loadKg: Double?,
        loadUnit: WeightUnit?,
        loadDisplayValue: Double?,
        isWarmup: Bool
    ) {
        self.blockIndex = blockIndex
        self.blockID = blockID
        self.setID = setID
        self.setIndexInBlock = setIndexInBlock
        self.setRepeatIndex = setRepeatIndex
        self.slotID = slotID
        self.slotIndex = slotIndex
        self.exerciseID = exerciseID
        self.primaryDisplayTarget = primaryDisplayTarget
        self.secondaryDisplayTargets = secondaryDisplayTargets
        self.loadKg = loadKg
        self.loadUnit = loadUnit
        self.loadDisplayValue = loadDisplayValue
        self.isWarmup = isWarmup
    }
}

public enum SessionPreviewRemaining: Equatable, Sendable {
    case bounded(completed: Int, total: Int)
    case unbounded

    public var remaining: Int? {
        switch self {
        case .bounded(let completed, let total):
            max(0, total - completed)
        case .unbounded:
            nil
        }
    }

    init(block: ExecutionBlock, completedSets: Int) {
        guard block.sets.allSatisfy(\.allowsVisibleSetProgressTotal) else {
            self = .unbounded
            return
        }
        let total = block.sets.reduce(0) { $0 + max(0, $1.setRepeat) }
        self = .bounded(completed: min(max(0, completedSets), total), total: total)
    }
}

private extension ExecutionPlan {
    func previewWorks() -> [SessionPreviewWork] {
        blocks.enumerated().flatMap { blockIndex, block in
            block.sets.enumerated().flatMap { setIndex, set in
                (0..<max(1, set.setRepeat)).flatMap { setRepeatIndex in
                    set.slots.enumerated().map { slotIndex, slot in
                        SessionPreviewWork(
                            blockIndex: blockIndex,
                            blockID: block.blockID,
                            setID: set.setID,
                            setIndexInBlock: setIndex,
                            setRepeatIndex: setRepeatIndex,
                            slotID: slot.slotID,
                            slotIndex: slotIndex,
                            exerciseID: slot.exerciseID,
                            primaryDisplayTarget: slot.primaryDisplayTarget,
                            secondaryDisplayTargets: slot.secondaryDisplayTargets,
                            loadKg: slot.loadKg,
                            loadUnit: slot.loadUnit,
                            loadDisplayValue: slot.loadDisplayValue,
                            isWarmup: slot.isWarmup
                        )
                    }
                }
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
