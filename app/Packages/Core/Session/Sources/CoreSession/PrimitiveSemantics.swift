// PrimitiveSemantics.swift
//
// Computed semantics for the primitive execution plan. These helpers keep
// primitive meaning in CoreSession so feature surfaces do not rediscover
// timing legality, result roles, metric order, or sentinel progress policy.

import Foundation
import CoreDomain
import WorkoutCoreFoundation

public enum PrimitiveSemanticError: Error, Equatable, Sendable {
    case illegalRuntimeCell(setID: PrimitiveSetID)
    case invalidTiming(setID: PrimitiveSetID)
}

public enum PrimitiveResultMetric: Equatable, Sendable {
    case rounds
    case reps
    case distance
    case duration
    case loadCarried
    case completion

    public var primitiveMetric: PrimitiveMetric {
        switch self {
        case .rounds: .rounds
        case .reps: .reps
        case .distance: .distance
        case .duration: .duration
        case .loadCarried: .loadCarried
        case .completion: .completion
        }
    }
}

public struct PrimitiveResultInputContract: Equatable, Sendable {
    public var metric: PrimitiveResultMetric
    public var target: PrimitiveWorkTarget?

    public init(metric: PrimitiveResultMetric, target: PrimitiveWorkTarget?) {
        self.metric = metric
        self.target = target
    }
}

public enum PrimitiveResultScope: Equatable, Sendable {
    case exercise
    case setAggregate
    case blockAggregate
}

public struct PrimitiveResultLogSemantics: Equatable, Sendable {
    public let role: PrimitiveLogRole
    public let scope: PrimitiveResultScope
    public let isByExerciseEligible: Bool
    public let isAggregate: Bool
    public let isSkipped: Bool
    public let primaryMetric: PrimitiveResultMetric?
    public let secondaryMetrics: [PrimitiveResultMetric]
    public let isSentinel: Bool

    public init(
        role: PrimitiveLogRole,
        scope: PrimitiveResultScope,
        isByExerciseEligible: Bool,
        isAggregate: Bool,
        isSkipped: Bool,
        primaryMetric: PrimitiveResultMetric?,
        secondaryMetrics: [PrimitiveResultMetric],
        isSentinel: Bool
    ) {
        self.role = role
        self.scope = scope
        self.isByExerciseEligible = isByExerciseEligible
        self.isAggregate = isAggregate
        self.isSkipped = isSkipped
        self.primaryMetric = primaryMetric
        self.secondaryMetrics = secondaryMetrics
        self.isSentinel = isSentinel
    }
}

public enum PrimitiveSemantics {
    public static func validate(_ workout: PrimitiveWorkout) throws {
        guard workout.blocks.contains(where: { block in
            block.sets.contains(where: { !$0.slots.isEmpty })
        }) else {
            throw PrimitiveSemanticError.invalidTiming(setID: workout.id)
        }
        for block in workout.blocks {
            try validate(block)
        }
    }

    public static func validate(_ block: PrimitiveBlock) throws {
        guard block.sets.contains(where: { !$0.slots.isEmpty }) else {
            throw PrimitiveSemanticError.invalidTiming(setID: block.id)
        }
        for set in block.sets {
            try validate(set)
        }
    }

    public static func validate(_ set: PrimitiveSet) throws {
        for slot in set.slots {
            if slot.workTargets.filter({ $0.role == .completion }).count > 1 {
                throw PrimitiveSemanticError.invalidTiming(setID: set.id)
            }
        }
        if set.traversal == .amrap && (set.timing.mode == .setBounded || set.timing.mode == .targetBounded) {
            throw PrimitiveSemanticError.illegalRuntimeCell(setID: set.id)
        }
        if set.timing.mode == .timeBounded,
           (set.timing.intervalSec == nil || set.timing.rounds == nil) {
            throw PrimitiveSemanticError.invalidTiming(setID: set.id)
        }
        if set.timing.mode == .capBounded, set.timing.capSec == nil {
            throw PrimitiveSemanticError.invalidTiming(setID: set.id)
        }
        if set.slots.isEmpty {
            throw PrimitiveSemanticError.invalidTiming(setID: set.id)
        }
        if set.timing.mode == .capBounded,
           set.traversal == .amrap,
           !set.workTargets.hasObservation(.rounds) {
            throw PrimitiveSemanticError.invalidTiming(setID: set.id)
        }
        if set.timing.mode == .capBounded,
           set.traversal != .amrap,
           !set.slots.isEmpty,
           !set.workTargets.hasObservation(.duration) {
            throw PrimitiveSemanticError.invalidTiming(setID: set.id)
        }
    }
}

public extension PrimitiveSetLog {
    var resultSemantics: PrimitiveResultLogSemantics {
        let scope: PrimitiveResultScope
        let isByExerciseEligible: Bool
        switch role {
        case .slot:
            scope = .exercise
            isByExerciseEligible = !skipped
        case .setResult:
            scope = .setAggregate
            isByExerciseEligible = false
        case .blockResult:
            scope = .blockAggregate
            isByExerciseEligible = false
        }

        let metrics = primitiveResultMetrics
        return PrimitiveResultLogSemantics(
            role: role,
            scope: scope,
            isByExerciseEligible: isByExerciseEligible,
            isAggregate: role != .slot,
            isSkipped: skipped,
            primaryMetric: metrics.first,
            secondaryMetrics: Array(metrics.dropFirst()),
            isSentinel: role != .slot && metrics.isEmpty
        )
    }

    var primitiveResultMetrics: [PrimitiveResultMetric] {
        var metrics: [PrimitiveResultMetric] = []
        if rounds != nil { metrics.append(.rounds) }
        if reps != nil { metrics.append(.reps) }
        if distanceM != nil { metrics.append(.distance) }
        if durationSec != nil { metrics.append(.duration) }
        if weight != nil { metrics.append(.loadCarried) }
        if metrics.isEmpty, role == .slot, !skipped { metrics.append(.completion) }
        return metrics
    }
}

public extension ExecutionPlan {
    static func validated(
        workout: PrimitiveWorkout,
        loadResolver: (@Sendable (PrimitiveSlot) -> ResolvedPrimitiveLoad?)? = nil
    ) throws -> ExecutionPlan {
        try PrimitiveSemantics.validate(workout)
        if let loadResolver {
            return ExecutionPlan(workout: workout, loadResolver: loadResolver)
        }
        return ExecutionPlan(workout: workout)
    }
}

public extension ExecutionSet {
    var allowsVisibleSetProgressTotal: Bool {
        traversal != .amrap && timing.mode != .timeBounded
    }

    var completionTargets: [PrimitiveWorkTarget] {
        workTargets.completionTargets
    }

    var observationTargets: [PrimitiveWorkTarget] {
        workTargets.observationTargets
    }

    func observationTarget(_ metric: PrimitiveMetric) -> PrimitiveWorkTarget? {
        workTargets.observationTarget(metric)
    }

    var aggregateResultMetric: PrimitiveResultMetric? {
        if observationTarget(.rounds) != nil { return .rounds }
        if observationTarget(.duration) != nil { return .duration }
        if observationTarget(.distance) != nil { return .distance }
        if observationTarget(.loadCarried) != nil { return .loadCarried }
        return nil
    }
}

public extension ExecutionBlock {
    var observationTargets: [PrimitiveWorkTarget] {
        workTargets.observationTargets
    }

    func observationTarget(_ metric: PrimitiveMetric) -> PrimitiveWorkTarget? {
        workTargets.observationTarget(metric)
    }

    func slotForLegacyCursor(
        itemIndex: Int,
        exerciseID: ExerciseID,
        itemCount: Int
    ) -> ExecutionSlot? {
        let flattenedSlots = sets.flatMap(\.slots)
        if flattenedSlots.count == itemCount {
            return flattenedSlots[safe: itemIndex]
        }

        let exerciseMatches = flattenedSlots.filter { $0.exerciseID == exerciseID }
        if exerciseMatches.count == 1 {
            return exerciseMatches[0]
        }

        for set in sets {
            if let slot = set.slots[safe: itemIndex] {
                return slot
            }
        }
        return nil
    }
}

public extension ExecutionSlot {
    var completionTargets: [PrimitiveWorkTarget] {
        workTargets.completionTargets
    }

    var observationTargets: [PrimitiveWorkTarget] {
        workTargets.observationTargets
    }

    var resultInputContract: PrimitiveResultInputContract? {
        for target in completionTargets {
            if let metric = PrimitiveResultMetric(target.metric) {
                return PrimitiveResultInputContract(metric: metric, target: target)
            }
        }
        return nil
    }

    var primaryDisplayTarget: PrimitiveWorkTarget? {
        completionTargets.first ?? observationTargets.first
    }

    var secondaryDisplayTargets: [PrimitiveWorkTarget] {
        workTargets.filter { $0 != primaryDisplayTarget }
    }
}

private extension PrimitiveResultMetric {
    init?(_ metric: PrimitiveMetric) {
        switch metric {
        case .reps:
            self = .reps
        case .distance:
            self = .distance
        case .duration:
            self = .duration
        case .loadCarried:
            self = .loadCarried
        case .completion:
            self = .completion
        case .rounds:
            return nil
        }
    }
}

private extension [PrimitiveWorkTarget] {
    var completionTargets: [PrimitiveWorkTarget] {
        filter { $0.role == .completion }
    }

    var observationTargets: [PrimitiveWorkTarget] {
        filter { $0.role == .observation }
    }

    func hasObservation(_ metric: PrimitiveMetric) -> Bool {
        observationTarget(metric) != nil
    }

    func observationTarget(_ metric: PrimitiveMetric) -> PrimitiveWorkTarget? {
        first { $0.metric == metric && $0.role == .observation }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
