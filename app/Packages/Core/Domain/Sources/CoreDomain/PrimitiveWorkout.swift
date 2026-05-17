// PrimitiveWorkout.swift
//
// Domain values for the target primitive Block > Set > Slot authoring shape.
// These are plain validated values after Sync mapping; wire DTOs stay in Sync.

import Foundation
import WorkoutCoreFoundation

public struct PrimitiveWorkout: Sendable, Hashable, Codable {
    public var id: WorkoutID
    public var name: String
    public var blocks: [PrimitiveBlock]

    public init(id: WorkoutID, name: String, blocks: [PrimitiveBlock]) {
        self.id = id
        self.name = name
        self.blocks = blocks
    }
}

public struct PrimitiveBlock: Sendable, Hashable, Codable {
    public var id: BlockID
    public var title: String?
    public var repeatCount: Int
    public var workTargets: [PrimitiveWorkTarget]
    public var sets: [PrimitiveSet]

    public init(
        id: BlockID,
        title: String? = nil,
        repeatCount: Int = 1,
        workTargets: [PrimitiveWorkTarget] = [],
        sets: [PrimitiveSet]
    ) {
        self.id = id
        self.title = title
        self.repeatCount = repeatCount
        self.workTargets = workTargets
        self.sets = sets
    }
}

public struct PrimitiveSet: Sendable, Hashable, Codable {
    public var id: PrimitiveSetID
    public var title: String?
    public var timing: PrimitiveTiming
    public var traversal: PrimitiveTraversal
    public var repeatCount: Int
    public var workTargets: [PrimitiveWorkTarget]
    public var slots: [PrimitiveSlot]

    public init(
        id: PrimitiveSetID,
        title: String? = nil,
        timing: PrimitiveTiming,
        traversal: PrimitiveTraversal = .sequential,
        repeatCount: Int = 1,
        workTargets: [PrimitiveWorkTarget] = [],
        slots: [PrimitiveSlot]
    ) {
        self.id = id
        self.title = title
        self.timing = timing
        self.traversal = traversal
        self.repeatCount = repeatCount
        self.workTargets = workTargets
        self.slots = slots
    }
}

public struct PrimitiveSlot: Sendable, Hashable, Codable {
    public var id: PrimitiveSlotID
    public var exerciseID: ExerciseID
    public var workTargets: [PrimitiveWorkTarget]
    public var load: PrimitiveLoad?
    public var stimuli: [PrimitiveStimulus]
    public var postRestSec: Int
    public var isWarmup: Bool

    public init(
        id: PrimitiveSlotID,
        exerciseID: ExerciseID,
        workTargets: [PrimitiveWorkTarget],
        load: PrimitiveLoad? = nil,
        stimuli: [PrimitiveStimulus] = [],
        postRestSec: Int = 0,
        isWarmup: Bool = false
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.workTargets = workTargets
        self.load = load
        self.stimuli = stimuli
        self.postRestSec = postRestSec
        self.isWarmup = isWarmup
    }
}

public enum PrimitiveTimingMode: String, Sendable, Hashable, CaseIterable, Codable {
    case setBounded = "set_bounded"
    case timeBounded = "time_bounded"
    case capBounded = "cap_bounded"
    case targetBounded = "target_bounded"
}

public enum PrimitiveTraversal: String, Sendable, Hashable, CaseIterable, Codable {
    case sequential
    case roundRobin = "round_robin"
    case amrap
}

public struct PrimitiveTiming: Sendable, Hashable, Codable {
    public var mode: PrimitiveTimingMode
    public var intervalSec: Int?
    public var rounds: Int?
    public var capSec: Int?

    public init(
        mode: PrimitiveTimingMode,
        intervalSec: Int? = nil,
        rounds: Int? = nil,
        capSec: Int? = nil
    ) {
        self.mode = mode
        self.intervalSec = intervalSec
        self.rounds = rounds
        self.capSec = capSec
    }
}

public enum PrimitiveMetric: String, Sendable, Hashable, CaseIterable, Codable {
    case reps
    case duration
    case distance
    case rounds
    case completion
    case loadCarried = "load_carried"
}

public enum PrimitiveValueForm: String, Sendable, Hashable, CaseIterable, Codable {
    case single
    case range
    case open
}

public enum PrimitiveWorkRole: String, Sendable, Hashable, CaseIterable, Codable {
    case completion
    case observation
}

public struct PrimitiveWorkTarget: Sendable, Hashable, Codable {
    public var metric: PrimitiveMetric
    public var valueForm: PrimitiveValueForm
    public var value: Double?
    public var role: PrimitiveWorkRole

    public init(
        metric: PrimitiveMetric,
        valueForm: PrimitiveValueForm,
        value: Double? = nil,
        role: PrimitiveWorkRole
    ) {
        self.metric = metric
        self.valueForm = valueForm
        self.value = value
        self.role = role
    }
}

public enum PrimitiveLoadUnit: String, Sendable, Hashable, CaseIterable, Codable {
    case kg
    case lb
    case oneRepMax = "1rm"
    case bodyweight
}

public enum PrimitiveLoadUnitType: String, Sendable, Hashable, CaseIterable, Codable {
    case absolute
    case relative
    case implicitBodyweight = "implicit_bodyweight"
}

public struct PrimitiveLoad: Sendable, Hashable, Codable {
    public var value: Double?
    public var unit: PrimitiveLoadUnit
    public var unitType: PrimitiveLoadUnitType

    public init(value: Double? = nil, unit: PrimitiveLoadUnit, unitType: PrimitiveLoadUnitType) {
        self.value = value
        self.unit = unit
        self.unitType = unitType
    }
}

public enum PrimitiveStimulusType: String, Sendable, Hashable, CaseIterable, Codable {
    case rir
    case hrZone = "hr_zone"
}

public struct PrimitiveStimulus: Sendable, Hashable, Codable {
    public var type: PrimitiveStimulusType
    public var target: Double?

    public init(type: PrimitiveStimulusType, target: Double? = nil) {
        self.type = type
        self.target = target
    }
}

public enum PrimitiveLogRole: String, Sendable, Hashable, CaseIterable, Codable {
    case slot
    case setResult = "set_result"
    case blockResult = "block_result"
}

public struct PrimitiveSetLog: Sendable, Hashable {
    public var id: SetLogID
    public var role: PrimitiveLogRole
    public var slotID: PrimitiveSlotID?
    public var setID: PrimitiveSetID?
    public var blockID: BlockID?
    public var workoutID: WorkoutID?
    public var plannedExerciseID: ExerciseID?
    public var performedExerciseID: ExerciseID?
    public var setIndex: Int
    public var setRepeatIndex: Int
    public var blockRepeatIndex: Int
    public var reps: Int?
    public var weight: Double?
    public var weightUnit: WeightUnit?
    public var durationSec: Double?
    public var rounds: Int?
    public var rir: Int?
    public var isWarmup: Bool
    public var completedAt: Date

    public init(
        id: SetLogID,
        role: PrimitiveLogRole,
        slotID: PrimitiveSlotID? = nil,
        setID: PrimitiveSetID? = nil,
        blockID: BlockID? = nil,
        workoutID: WorkoutID? = nil,
        plannedExerciseID: ExerciseID? = nil,
        performedExerciseID: ExerciseID? = nil,
        setIndex: Int,
        setRepeatIndex: Int = 0,
        blockRepeatIndex: Int = 0,
        reps: Int? = nil,
        weight: Double? = nil,
        weightUnit: WeightUnit? = nil,
        durationSec: Double? = nil,
        rounds: Int? = nil,
        rir: Int? = nil,
        isWarmup: Bool = false,
        completedAt: Date
    ) {
        self.id = id
        self.role = role
        self.slotID = slotID
        self.setID = setID
        self.blockID = blockID
        self.workoutID = workoutID
        self.plannedExerciseID = plannedExerciseID
        self.performedExerciseID = performedExerciseID
        self.setIndex = setIndex
        self.setRepeatIndex = setRepeatIndex
        self.blockRepeatIndex = blockRepeatIndex
        self.reps = reps
        self.weight = weight
        self.weightUnit = weightUnit
        self.durationSec = durationSec
        self.rounds = rounds
        self.rir = rir
        self.isWarmup = isWarmup
        self.completedAt = completedAt
    }
}
