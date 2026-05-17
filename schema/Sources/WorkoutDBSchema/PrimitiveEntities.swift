// PrimitiveEntities.swift
//
// Wire DTOs for the primitive Block > Set > Slot contract.

import Foundation

public enum PrimitiveTimingMode: String, Codable, Sendable, CaseIterable {
    case setBounded = "set_bounded"
    case timeBounded = "time_bounded"
    case capBounded = "cap_bounded"
    case targetBounded = "target_bounded"
}

public enum PrimitiveTraversal: String, Codable, Sendable, CaseIterable {
    case sequential
    case roundRobin = "round_robin"
    case amrap
}

public enum PrimitiveMetric: String, Codable, Sendable, CaseIterable {
    case reps
    case duration
    case distance
    case rounds
    case completion
    case loadCarried = "load_carried"
}

public enum PrimitiveValueForm: String, Codable, Sendable, CaseIterable {
    case single
    case range
    case open
}

public enum PrimitiveWorkRole: String, Codable, Sendable, CaseIterable {
    case completion
    case observation
}

public struct PrimitiveWorkTarget: Codable, Sendable, Equatable {
    public let metric: PrimitiveMetric
    public let valueForm: PrimitiveValueForm
    public let value: Double?
    public let role: PrimitiveWorkRole

    enum CodingKeys: String, CodingKey {
        case metric
        case valueForm = "value_form"
        case value
        case role
    }

    public init(metric: PrimitiveMetric, valueForm: PrimitiveValueForm, value: Double? = nil, role: PrimitiveWorkRole) {
        self.metric = metric
        self.valueForm = valueForm
        self.value = value
        self.role = role
    }
}

public enum PrimitiveLoadUnit: String, Codable, Sendable, CaseIterable {
    case kg
    case lb
}

public enum PrimitiveLoadUnitType: String, Codable, Sendable, CaseIterable {
    case absolute
}

public struct PrimitiveLoad: Codable, Sendable, Equatable {
    public let value: Double?
    public let unit: PrimitiveLoadUnit
    public let unitType: PrimitiveLoadUnitType

    enum CodingKeys: String, CodingKey {
        case value
        case unit
        case unitType = "unit_type"
    }

    public init(value: Double? = nil, unit: PrimitiveLoadUnit, unitType: PrimitiveLoadUnitType) {
        self.value = value
        self.unit = unit
        self.unitType = unitType
    }
}

public enum PrimitiveStimulusType: String, Codable, Sendable, CaseIterable {
    case rir
    case hrZone = "hr_zone"
}

public struct PrimitiveStimulus: Codable, Sendable, Equatable {
    public let type: PrimitiveStimulusType
    public let target: Double?

    public init(type: PrimitiveStimulusType, target: Double? = nil) {
        self.type = type
        self.target = target
    }
}

public struct PrimitiveTiming: Codable, Sendable, Equatable {
    public let mode: PrimitiveTimingMode
    public let intervalSec: Int?
    public let rounds: Int?
    public let capSec: Int?

    enum CodingKeys: String, CodingKey {
        case mode
        case intervalSec = "interval_sec"
        case rounds
        case capSec = "cap_sec"
    }

    public init(mode: PrimitiveTimingMode, intervalSec: Int? = nil, rounds: Int? = nil, capSec: Int? = nil) {
        self.mode = mode
        self.intervalSec = intervalSec
        self.rounds = rounds
        self.capSec = capSec
    }
}

public struct PrimitiveSlot: Codable, Sendable, Equatable {
    public let id: String
    public let exerciseId: String
    public let workTarget: [PrimitiveWorkTarget]
    public let load: PrimitiveLoad?
    public let stimuli: [PrimitiveStimulus]
    public let postRestSec: Int
    public let isWarmup: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case exerciseId = "exercise_id"
        case workTarget = "work_target"
        case load
        case stimuli
        case postRestSec = "post_rest_sec"
        case isWarmup = "is_warmup"
    }

    public init(
        id: String,
        exerciseId: String,
        workTarget: [PrimitiveWorkTarget],
        load: PrimitiveLoad? = nil,
        stimuli: [PrimitiveStimulus] = [],
        postRestSec: Int = 0,
        isWarmup: Bool = false
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.workTarget = workTarget
        self.load = load
        self.stimuli = stimuli
        self.postRestSec = postRestSec
        self.isWarmup = isWarmup
    }
}

public struct PrimitiveSet: Codable, Sendable, Equatable {
    public let id: String
    public let title: String?
    public let timing: PrimitiveTiming
    public let traversal: PrimitiveTraversal
    public let repeatCount: Int
    public let workTarget: [PrimitiveWorkTarget]
    public let slots: [PrimitiveSlot]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case timing
        case traversal
        case repeatCount = "repeat"
        case workTarget = "work_target"
        case slots
    }

    public init(
        id: String,
        title: String? = nil,
        timing: PrimitiveTiming,
        traversal: PrimitiveTraversal = .sequential,
        repeatCount: Int = 1,
        workTarget: [PrimitiveWorkTarget] = [],
        slots: [PrimitiveSlot]
    ) {
        self.id = id
        self.title = title
        self.timing = timing
        self.traversal = traversal
        self.repeatCount = repeatCount
        self.workTarget = workTarget
        self.slots = slots
    }
}

public struct PrimitiveBlock: Codable, Sendable, Equatable {
    public let id: String
    public let title: String?
    public let repeatCount: Int
    public let workTarget: [PrimitiveWorkTarget]
    public let sets: [PrimitiveSet]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case repeatCount = "repeat"
        case workTarget = "work_target"
        case sets
    }

    public init(
        id: String,
        title: String? = nil,
        repeatCount: Int = 1,
        workTarget: [PrimitiveWorkTarget] = [],
        sets: [PrimitiveSet]
    ) {
        self.id = id
        self.title = title
        self.repeatCount = repeatCount
        self.workTarget = workTarget
        self.sets = sets
    }
}

public struct PrimitiveWorkout: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let primitiveBlocks: [PrimitiveBlock]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case primitiveBlocks = "primitive_blocks"
    }

    public init(id: String, name: String, primitiveBlocks: [PrimitiveBlock]) {
        self.id = id
        self.name = name
        self.primitiveBlocks = primitiveBlocks
    }
}

public enum PrimitiveLogRole: String, Codable, Sendable, CaseIterable {
    case slot
    case setResult = "set_result"
    case blockResult = "block_result"
}

public struct PrimitiveSetLog: Codable, Sendable, Equatable {
    public let id: String
    public let role: PrimitiveLogRole
    public let slotId: String?
    public let setId: String?
    public let blockId: String?
    public let workoutId: String?
    public let plannedExerciseId: String?
    public let performedExerciseId: String?
    public let setIndex: Int
    public let setRepeatIndex: Int
    public let blockRepeatIndex: Int
    public let reps: Int?
    public let weight: Double?
    public let weightUnit: WeightUnit?
    public let durationSec: Double?
    public let rounds: Int?
    public let rir: Int?
    public let isWarmup: Bool
    public let completedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case slotId = "slot_id"
        case setId = "set_id"
        case blockId = "block_id"
        case workoutId = "workout_id"
        case plannedExerciseId = "planned_exercise_id"
        case performedExerciseId = "performed_exercise_id"
        case setIndex = "set_index"
        case setRepeatIndex = "set_repeat_index"
        case blockRepeatIndex = "block_repeat_index"
        case reps
        case weight
        case weightUnit = "weight_unit"
        case durationSec = "duration_sec"
        case rounds
        case rir
        case isWarmup = "is_warmup"
        case completedAt = "completed_at"
    }

    public init(
        id: String,
        role: PrimitiveLogRole,
        slotId: String? = nil,
        setId: String? = nil,
        blockId: String? = nil,
        workoutId: String? = nil,
        plannedExerciseId: String? = nil,
        performedExerciseId: String? = nil,
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
        self.slotId = slotId
        self.setId = setId
        self.blockId = blockId
        self.workoutId = workoutId
        self.plannedExerciseId = plannedExerciseId
        self.performedExerciseId = performedExerciseId
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
