// Core entity DTOs — wire types that mirror the server's Pydantic schemas.
//
// Design choices:
//   • Snake_case JSON mapped to camelCase Swift via CodingKeys.
//   • JSON blob fields (prescription_json, timing_config_json, tags_json, etc.)
//     stay as String. The server treats them as opaque; so does the client. Parse
//     them separately per the documented shapes in docs/specs/v2-architecture.md.
//   • Dates are ISO-8601 strings. JSONDecoder should use .iso8601 strategy.
//   • All types are public + Sendable + Codable + Equatable for test-friendliness.

import Foundation

public struct AppUser: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt = "created_at"
    }

    public init(id: String, name: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

public struct Exercise: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let notes: String?
    public let demoUrl: String?
    /// Library-level prescription defaults merged into every workout_item
    /// referencing this exercise (unless the item overrides). See
    /// `docs/decisions/ADR-2026-04-18-smart-defaults.md`.
    public let defaultPrescriptionJson: String?
    /// Library-level alternatives list — a JSON array matching the
    /// `ExerciseAlternative` shape minus the workout_item pointer.
    public let defaultAlternativesJson: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case notes
        case demoUrl = "demo_url"
        case defaultPrescriptionJson = "default_prescription_json"
        case defaultAlternativesJson = "default_alternatives_json"
    }

    public init(
        id: String,
        name: String,
        notes: String? = nil,
        demoUrl: String? = nil,
        defaultPrescriptionJson: String? = nil,
        defaultAlternativesJson: String? = nil
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.demoUrl = demoUrl
        self.defaultPrescriptionJson = defaultPrescriptionJson
        self.defaultAlternativesJson = defaultAlternativesJson
    }
}

public struct ExerciseAlternative: Codable, Sendable, Equatable {
    public let id: String
    public let exerciseId: String
    public let reason: String
    public let parameterOverridesJson: String?

    enum CodingKeys: String, CodingKey {
        case id
        case exerciseId = "exercise_id"
        case reason
        case parameterOverridesJson = "parameter_overrides_json"
    }

    public init(
        id: String,
        exerciseId: String,
        reason: String,
        parameterOverridesJson: String? = nil
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.reason = reason
        self.parameterOverridesJson = parameterOverridesJson
    }
}

public struct WorkoutItem: Codable, Sendable, Equatable {
    public let id: String
    public let position: Int
    public let exerciseId: String
    /// Always the resolved form (library defaults merged in).
    public let prescriptionJson: String
    /// The client's original sparse payload (null when the resolved form
    /// equals what the client sent). Round-tripped for completeness but not
    /// used at runtime — the app reads only the resolved
    /// `prescriptionJson`. See `ADR-2026-04-18-smart-defaults.md`.
    public let prescriptionJsonRaw: String?
    public let alternatives: [ExerciseAlternative]

    enum CodingKeys: String, CodingKey {
        case id
        case position
        case exerciseId = "exercise_id"
        case prescriptionJson = "prescription_json"
        case prescriptionJsonRaw = "prescription_json_raw"
        case alternatives
    }

    public init(
        id: String,
        position: Int,
        exerciseId: String,
        prescriptionJson: String,
        prescriptionJsonRaw: String? = nil,
        alternatives: [ExerciseAlternative] = []
    ) {
        self.id = id
        self.position = position
        self.exerciseId = exerciseId
        self.prescriptionJson = prescriptionJson
        self.prescriptionJsonRaw = prescriptionJsonRaw
        self.alternatives = alternatives
    }
}

public struct Block: Codable, Sendable, Equatable {
    public let id: String
    public let position: Int
    public let parentBlockId: String?
    public let name: String?
    public let timingMode: TimingMode
    public let timingConfigJson: String
    public let rounds: Int?
    public let roundsRepSchemeJson: String?
    public let notes: String?
    public let intent: String?
    public let workoutItems: [WorkoutItem]

    enum CodingKeys: String, CodingKey {
        case id
        case position
        case parentBlockId = "parent_block_id"
        case name
        case timingMode = "timing_mode"
        case timingConfigJson = "timing_config_json"
        case rounds
        case roundsRepSchemeJson = "rounds_rep_scheme_json"
        case notes
        case intent
        case workoutItems = "workout_items"
    }

    public init(
        id: String,
        position: Int,
        parentBlockId: String? = nil,
        name: String? = nil,
        timingMode: TimingMode,
        timingConfigJson: String,
        rounds: Int? = nil,
        roundsRepSchemeJson: String? = nil,
        notes: String? = nil,
        intent: String? = nil,
        workoutItems: [WorkoutItem] = []
    ) {
        self.id = id
        self.position = position
        self.parentBlockId = parentBlockId
        self.name = name
        self.timingMode = timingMode
        self.timingConfigJson = timingConfigJson
        self.rounds = rounds
        self.roundsRepSchemeJson = roundsRepSchemeJson
        self.notes = notes
        self.intent = intent
        self.workoutItems = workoutItems
    }
}

public struct Workout: Codable, Sendable, Equatable {
    public let id: String
    public let userId: String
    public let name: String
    public let scheduledDate: String?
    public let status: WorkoutStatus
    public let source: WorkoutSource
    public let notes: String?
    public let tagsJson: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let completedAt: Date?
    public let blocks: [Block]
    public let primitiveBlocks: [PrimitiveBlock]

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case scheduledDate = "scheduled_date"
        case status
        case source
        case notes
        case tagsJson = "tags_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
        case blocks
        case primitiveBlocks = "primitive_blocks"
    }

    public init(
        id: String,
        userId: String,
        name: String,
        scheduledDate: String? = nil,
        status: WorkoutStatus,
        source: WorkoutSource,
        notes: String? = nil,
        tagsJson: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date? = nil,
        blocks: [Block] = [],
        primitiveBlocks: [PrimitiveBlock] = []
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.scheduledDate = scheduledDate
        self.status = status
        self.source = source
        self.notes = notes
        self.tagsJson = tagsJson
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.blocks = blocks
        self.primitiveBlocks = primitiveBlocks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        scheduledDate = try container.decodeIfPresent(String.self, forKey: .scheduledDate)
        status = try container.decode(WorkoutStatus.self, forKey: .status)
        source = try container.decode(WorkoutSource.self, forKey: .source)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        tagsJson = try container.decodeIfPresent(String.self, forKey: .tagsJson)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        blocks = try container.decode([Block].self, forKey: .blocks)
        primitiveBlocks = try container.decodeIfPresent(
            [PrimitiveBlock].self,
            forKey: .primitiveBlocks
        ) ?? []
    }
}

public struct SetLog: Codable, Sendable, Equatable {
    public let id: String
    public let workoutItemId: String
    public let performedExerciseId: String?
    public let setIndex: Int
    public let reps: Int?
    public let weight: Double?
    public let weightUnit: WeightUnit?
    public let durationSec: Double?
    public let distanceM: Double?
    public let rir: Int?
    public let isWarmup: Bool
    public let skipped: Bool
    public let side: SetLogSide
    public let startedAt: Date?
    public let completedAt: Date
    public let hrAvgBpm: Int?
    public let hrMaxBpm: Int?
    public let cadenceAvgSpm: Int?
    public let motionSamplesRef: String?
    public let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case workoutItemId = "workout_item_id"
        case performedExerciseId = "performed_exercise_id"
        case setIndex = "set_index"
        case reps
        case weight
        case weightUnit = "weight_unit"
        case durationSec = "duration_sec"
        case distanceM = "distance_m"
        case rir
        case isWarmup = "is_warmup"
        case skipped
        case side
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case hrAvgBpm = "hr_avg_bpm"
        case hrMaxBpm = "hr_max_bpm"
        case cadenceAvgSpm = "cadence_avg_spm"
        case motionSamplesRef = "motion_samples_ref"
        case notes
    }

    public init(
        id: String,
        workoutItemId: String,
        performedExerciseId: String? = nil,
        setIndex: Int,
        reps: Int? = nil,
        weight: Double? = nil,
        weightUnit: WeightUnit? = nil,
        durationSec: Double? = nil,
        distanceM: Double? = nil,
        rir: Int? = nil,
        isWarmup: Bool = false,
        skipped: Bool = false,
        side: SetLogSide = .bilateral,
        startedAt: Date? = nil,
        completedAt: Date,
        hrAvgBpm: Int? = nil,
        hrMaxBpm: Int? = nil,
        cadenceAvgSpm: Int? = nil,
        motionSamplesRef: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.workoutItemId = workoutItemId
        self.performedExerciseId = performedExerciseId
        self.setIndex = setIndex
        self.reps = reps
        self.weight = weight
        self.weightUnit = weightUnit
        self.durationSec = durationSec
        self.distanceM = distanceM
        self.rir = rir
        self.isWarmup = isWarmup
        self.skipped = skipped
        self.side = side
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.hrAvgBpm = hrAvgBpm
        self.hrMaxBpm = hrMaxBpm
        self.cadenceAvgSpm = cadenceAvgSpm
        self.motionSamplesRef = motionSamplesRef
        self.notes = notes
    }
}

public struct UserParameter: Codable, Sendable, Equatable {
    public let id: String
    public let userId: String
    public let key: String
    public let value: String
    public let updatedAt: Date
    public let source: UserParameterSource

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case key
        case value
        case updatedAt = "updated_at"
        case source
    }

    public init(
        id: String,
        userId: String,
        key: String,
        value: String,
        updatedAt: Date,
        source: UserParameterSource
    ) {
        self.id = id
        self.userId = userId
        self.key = key
        self.value = value
        self.updatedAt = updatedAt
        self.source = source
    }
}
