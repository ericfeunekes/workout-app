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
    case reps
    case distance
    case duration
    case loadCarried
    case completion

    public var primitiveMetric: PrimitiveMetric {
        switch self {
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

public enum PrimitiveSemantics {
    public static func validate(_ workout: PrimitiveWorkout) throws {
        for block in workout.blocks {
            for set in block.sets {
                try validate(set)
            }
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
        if set.slots.isEmpty && set.timing.mode != .timeBounded && set.timing.mode != .capBounded {
            throw PrimitiveSemanticError.invalidTiming(setID: set.id)
        }
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
        if observationTarget(.rounds) != nil { return .reps }
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
