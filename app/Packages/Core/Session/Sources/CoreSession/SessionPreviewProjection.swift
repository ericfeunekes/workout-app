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
        let cursorBlockIndex = max(0, cursor.blockIndex)
        let rows = plan.previewWorks()
        let currentIndex = rows.firstIndex { row in
            row.blockIndex == cursorBlockIndex
                && row.setIndexInBlock >= max(0, cursor.setIndex - 1)
        } ?? rows.firstIndex { $0.blockIndex >= cursorBlockIndex }
        let activeBlockIndex = currentIndex.map { rows[$0].blockIndex } ?? cursorBlockIndex
        let block = plan.blocks[safe: activeBlockIndex]
        let completedSets = activeBlockIndex == cursorBlockIndex ? max(0, cursor.setIndex - 1) : 0

        self.current = currentIndex.map { rows[$0] }
        self.currentBlock = block.map {
            SessionPreviewBlock(
                blockIndex: activeBlockIndex,
                blockID: $0.blockID,
                blockCount: plan.blocks.count,
                title: nil,
                repeatCount: $0.blockRepeat,
                workTargets: $0.workTargets
            )
        }
        self.remaining = block.map { SessionPreviewRemaining(block: $0, completedSets: completedSets) }
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
    public var slotID: PrimitiveSlotID?
    public var slotIndex: Int
    public var exerciseID: ExerciseID?
    public var primaryDisplayTarget: PrimitiveWorkTarget?
    public var secondaryDisplayTargets: [PrimitiveWorkTarget]
    public var loadKg: Double?
    public var loadUnit: WeightUnit?
    public var loadDisplayValue: Double?
    public var isWarmup: Bool
    public var timing: PrimitiveTiming

    public init(
        blockIndex: Int,
        blockID: BlockID,
        setID: PrimitiveSetID,
        setIndexInBlock: Int,
        setRepeatIndex: Int,
        slotID: PrimitiveSlotID?,
        slotIndex: Int,
        exerciseID: ExerciseID?,
        primaryDisplayTarget: PrimitiveWorkTarget?,
        secondaryDisplayTargets: [PrimitiveWorkTarget],
        loadKg: Double?,
        loadUnit: WeightUnit?,
        loadDisplayValue: Double?,
        isWarmup: Bool,
        timing: PrimitiveTiming
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
        self.timing = timing
    }
}

public struct SessionPreviewMetrics: Equatable, Sendable {
    public var primary: String?
    public var secondary: String?

    public var detail: String? {
        [primary, secondary]
            .compactMap { $0 }
            .removingAdjacentDuplicates()
            .joined(separator: " · ")
            .nilIfEmpty
    }

    public init(primary: String?, secondary: String?) {
        self.primary = primary
        self.secondary = secondary
    }
}

public extension SessionPreviewWork {
    var metrics: SessionPreviewMetrics {
        SessionPreviewMetrics(
            primary: primaryMetricText,
            secondary: secondaryMetricText
        )
    }

    var isTimerOnly: Bool {
        exerciseID == nil
    }

    private var primaryMetricText: String? {
        guard let target = primaryDisplayTarget else {
            return loadDisplayText ?? timingDisplayText
        }
        if target.metric == .reps || target.metric == .completion {
            return loadDisplayText ?? timingDisplayText
        }
        return displayText(for: target, loadUnit: loadUnit)
    }

    private var secondaryMetricText: String? {
        guard let primary = primaryDisplayTarget else { return nil }
        var parts: [String] = []
        if primary.metric == .reps || primary.metric == .completion {
            if let text = displayText(for: primary, loadUnit: loadUnit) {
                parts.append(text)
            }
        } else if let loadDisplayText {
            parts.append(loadDisplayText)
        }
        parts.append(contentsOf: secondaryDisplayTargets.compactMap {
            displayText(for: $0, loadUnit: loadUnit)
        })
        return parts.removingAdjacentDuplicates().joined(separator: " · ").nilIfEmpty
    }

    private var loadDisplayText: String? {
        guard let weightUnit = loadUnit,
              let unit = LoadUnit(rawValue: weightUnit.rawValue) else { return nil }
        return formatLoad(weight: loadDisplayValue ?? loadKg, unit: unit)
    }

    private var timingDisplayText: String? {
        switch timing.mode {
        case .timeBounded:
            if let intervalSec = timing.intervalSec, let rounds = timing.rounds {
                return "\(rounds) x \(formatDuration(seconds: intervalSec))"
            }
            if let intervalSec = timing.intervalSec {
                return formatDuration(seconds: intervalSec)
            }
            return nil
        case .capBounded:
            return timing.capSec.map { "cap \(formatDuration(seconds: $0))" }
        case .setBounded, .targetBounded:
            return nil
        }
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
                    if set.slots.isEmpty {
                        return [
                            SessionPreviewWork(
                                blockIndex: blockIndex,
                                blockID: block.blockID,
                                setID: set.setID,
                                setIndexInBlock: setIndex,
                                setRepeatIndex: setRepeatIndex,
                                slotID: nil,
                                slotIndex: 0,
                                exerciseID: nil,
                                primaryDisplayTarget: set.workTargets.first,
                                secondaryDisplayTargets: Array(set.workTargets.dropFirst()),
                                loadKg: nil,
                                loadUnit: nil,
                                loadDisplayValue: nil,
                                isWarmup: false,
                                timing: set.timing
                            ),
                        ]
                    }
                    return set.slots.enumerated().map { slotIndex, slot in
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
                            isWarmup: slot.isWarmup,
                            timing: set.timing
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

private extension Array where Element == String {
    func removingAdjacentDuplicates() -> [String] {
        reduce(into: []) { result, value in
            if result.last != value {
                result.append(value)
            }
        }
    }
}

private func displayText(for target: PrimitiveWorkTarget, loadUnit: WeightUnit?) -> String? {
    switch target.metric {
    case .reps:
        return target.value.map { "\(formatDecimal($0)) reps" }
    case .duration:
        return target.value.map { formatDuration(seconds: $0) } ?? "duration"
    case .distance:
        return target.value.map(distanceLabel)
    case .rounds:
        return target.value.map { "\(formatDecimal($0)) rounds" } ?? "rounds"
    case .completion:
        return nil
    case .loadCarried:
        guard let value = target.value else { return "load carried" }
        return "\(formatDecimal(value)) \(loadUnit?.rawValue ?? "load")"
    }
}

private func distanceLabel(_ metres: Double) -> String {
    if metres >= 1000 {
        return "\(formatDecimal(metres / 1000)) km"
    }
    return "\(formatDecimal(metres)) m"
}

private func formatDecimal(_ value: Double) -> String {
    if value.rounded() == value {
        return String(Int(value))
    }
    return String(format: "%.1f", value)
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
