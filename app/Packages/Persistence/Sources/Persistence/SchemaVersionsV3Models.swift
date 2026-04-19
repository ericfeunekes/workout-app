// SchemaVersionsV3Models.swift
//
// R1.4-era `@Model` snapshots, nested inside `WorkoutDBSchemaV3`. Split
// from `SchemaVersions.swift` so the enum body stays under SwiftLint's
// `type_body_length` cap and the V1 / V2 shadow models stay grouped
// alongside their versioned counterparts.
//
// Rules for this file (mirror `SchemaVersionsV2Models.swift`):
//   • Class simple names match V4 so CoreData treats the diff as an in-
//     place entity upgrade, not an entity removal + addition.
//   • Columns match V4 byte-for-byte *except* for the two columns added
//     in V4 (perf-002): `priority: Int` + `dedupKey: String?` on
//     `PushItemModel`. Any other shape delta belongs in a V5 enum.
//   • Shadow @Model types are intentionally non-public — nothing outside
//     this package imports them. The V3→V4 lightweight migration stage
//     in `SchemaVersions.swift` plus the post-open backfill in
//     `backfillPushItemPriorityAndDedupKey` walks these types to
//     populate the new columns from each row's decoded envelope.

import Foundation
import SwiftData

extension WorkoutDBSchemaV3 {

    @Model
    final class WorkoutModel {
        @Attribute(.unique) var id: UUID
        var userID: UUID
        var name: String
        var scheduledDate: Date?
        var statusRaw: String
        var sourceRaw: String
        var notes: String?
        var createdAt: Date
        var updatedAt: Date
        var completedAt: Date?
        var tagsJSON: String?

        @Relationship(deleteRule: .cascade, inverse: \BlockModel.workout)
        var blocks: [BlockModel] = []

        init(
            id: UUID,
            userID: UUID,
            name: String,
            scheduledDate: Date?,
            statusRaw: String,
            sourceRaw: String,
            notes: String?,
            createdAt: Date,
            updatedAt: Date,
            completedAt: Date?,
            tagsJSON: String?
        ) {
            self.id = id
            self.userID = userID
            self.name = name
            self.scheduledDate = scheduledDate
            self.statusRaw = statusRaw
            self.sourceRaw = sourceRaw
            self.notes = notes
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.completedAt = completedAt
            self.tagsJSON = tagsJSON
        }
    }

    @Model
    final class BlockModel {
        @Attribute(.unique) var id: UUID
        var workoutID: UUID
        var parentBlockID: UUID?
        var position: Int
        var name: String?
        var timingModeRaw: String
        var timingConfigJSON: String
        var rounds: Int?
        var roundsRepSchemeJSON: String?
        var notes: String?

        var workout: WorkoutModel?

        @Relationship(deleteRule: .cascade, inverse: \WorkoutItemModel.block)
        var items: [WorkoutItemModel] = []

        init(
            id: UUID,
            workoutID: UUID,
            parentBlockID: UUID?,
            position: Int,
            name: String?,
            timingModeRaw: String,
            timingConfigJSON: String,
            rounds: Int?,
            roundsRepSchemeJSON: String?,
            notes: String?
        ) {
            self.id = id
            self.workoutID = workoutID
            self.parentBlockID = parentBlockID
            self.position = position
            self.name = name
            self.timingModeRaw = timingModeRaw
            self.timingConfigJSON = timingConfigJSON
            self.rounds = rounds
            self.roundsRepSchemeJSON = roundsRepSchemeJSON
            self.notes = notes
        }
    }

    @Model
    final class WorkoutItemModel {
        @Attribute(.unique) var id: UUID
        var blockID: UUID
        var position: Int
        var exerciseID: UUID
        var prescriptionJSON: String
        var prescriptionJSONRaw: String?

        var block: BlockModel?

        @Relationship(deleteRule: .cascade, inverse: \SetLogModel.workoutItem)
        var setLogs: [SetLogModel] = []

        @Relationship(deleteRule: .cascade, inverse: \ExerciseAlternativeModel.workoutItem)
        var alternatives: [ExerciseAlternativeModel] = []

        init(
            id: UUID,
            blockID: UUID,
            position: Int,
            exerciseID: UUID,
            prescriptionJSON: String,
            prescriptionJSONRaw: String? = nil
        ) {
            self.id = id
            self.blockID = blockID
            self.position = position
            self.exerciseID = exerciseID
            self.prescriptionJSON = prescriptionJSON
            self.prescriptionJSONRaw = prescriptionJSONRaw
        }
    }

    @Model
    final class ExerciseModel {
        @Attribute(.unique) var id: UUID
        var name: String
        var notes: String?
        var demoURLString: String?
        var defaultPrescriptionJSON: String?
        var defaultAlternativesJSON: String?

        init(
            id: UUID,
            name: String,
            notes: String?,
            demoURLString: String?,
            defaultPrescriptionJSON: String? = nil,
            defaultAlternativesJSON: String? = nil
        ) {
            self.id = id
            self.name = name
            self.notes = notes
            self.demoURLString = demoURLString
            self.defaultPrescriptionJSON = defaultPrescriptionJSON
            self.defaultAlternativesJSON = defaultAlternativesJSON
        }
    }

    @Model
    final class ExerciseAlternativeModel {
        @Attribute(.unique) var id: UUID
        var workoutItemID: UUID
        var exerciseID: UUID
        var reason: String
        var parameterOverridesJSON: String?

        var workoutItem: WorkoutItemModel?

        init(
            id: UUID,
            workoutItemID: UUID,
            exerciseID: UUID,
            reason: String,
            parameterOverridesJSON: String?
        ) {
            self.id = id
            self.workoutItemID = workoutItemID
            self.exerciseID = exerciseID
            self.reason = reason
            self.parameterOverridesJSON = parameterOverridesJSON
        }
    }

    @Model
    final class SetLogModel {
        @Attribute(.unique) var id: UUID
        var workoutItemID: UUID
        var workoutID: UUID?
        var plannedExerciseID: UUID?
        var performedExerciseID: UUID?
        var setIndex: Int
        var reps: Int?
        var weight: Double?
        var weightUnitRaw: String?
        var durationSec: Double?
        var distanceM: Double?
        var rir: Int?
        var isWarmup: Bool
        var startedAt: Date?
        var completedAt: Date
        var hrAvgBpm: Int?
        var hrMaxBpm: Int?
        var cadenceAvgSpm: Int?
        var motionSamplesRef: String?
        var notes: String?

        var workoutItem: WorkoutItemModel?

        init(
            id: UUID,
            workoutItemID: UUID,
            workoutID: UUID?,
            plannedExerciseID: UUID?,
            performedExerciseID: UUID?,
            setIndex: Int,
            reps: Int?,
            weight: Double?,
            weightUnitRaw: String?,
            durationSec: Double?,
            distanceM: Double?,
            rir: Int?,
            isWarmup: Bool,
            startedAt: Date?,
            completedAt: Date,
            hrAvgBpm: Int?,
            hrMaxBpm: Int?,
            cadenceAvgSpm: Int?,
            motionSamplesRef: String?,
            notes: String?
        ) {
            self.id = id
            self.workoutItemID = workoutItemID
            self.workoutID = workoutID
            self.plannedExerciseID = plannedExerciseID
            self.performedExerciseID = performedExerciseID
            self.setIndex = setIndex
            self.reps = reps
            self.weight = weight
            self.weightUnitRaw = weightUnitRaw
            self.durationSec = durationSec
            self.distanceM = distanceM
            self.rir = rir
            self.isWarmup = isWarmup
            self.startedAt = startedAt
            self.completedAt = completedAt
            self.hrAvgBpm = hrAvgBpm
            self.hrMaxBpm = hrMaxBpm
            self.cadenceAvgSpm = cadenceAvgSpm
            self.motionSamplesRef = motionSamplesRef
            self.notes = notes
        }
    }

    @Model
    final class UserParameterModel {
        @Attribute(.unique) var id: UUID
        var userID: UUID
        var key: String
        var value: String
        var updatedAt: Date
        var sourceRaw: String

        init(
            id: UUID,
            userID: UUID,
            key: String,
            value: String,
            updatedAt: Date,
            sourceRaw: String
        ) {
            self.id = id
            self.userID = userID
            self.key = key
            self.value = value
            self.updatedAt = updatedAt
            self.sourceRaw = sourceRaw
        }
    }

    @Model
    final class AppUserModel {
        @Attribute(.unique) var id: UUID
        var name: String
        var createdAt: Date

        init(id: UUID, name: String, createdAt: Date) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
        }
    }

    @Model
    final class SessionSnapshotModel {
        @Attribute(.unique) var id: UUID
        var encodedJSON: Data
        var savedAt: Date

        init(id: UUID, encodedJSON: Data, savedAt: Date) {
            self.id = id
            self.encodedJSON = encodedJSON
            self.savedAt = savedAt
        }
    }

    @Model
    final class PushItemModel {
        @Attribute(.unique) var id: UUID
        var enqueuedAt: Date
        var attempts: Int
        var payloadJSON: Data
        // No `priority` or `dedupKey` in V3 — they arrive in V4 via the
        // lightweight migration stage in `SchemaVersions.swift` plus the
        // post-open backfill in `backfillPushItemPriorityAndDedupKey`.

        init(id: UUID, enqueuedAt: Date, attempts: Int, payloadJSON: Data) {
            self.id = id
            self.enqueuedAt = enqueuedAt
            self.attempts = attempts
            self.payloadJSON = payloadJSON
        }
    }

    @Model
    final class EventModel {
        @Attribute(.unique) var id: UUID
        var timestamp: Date
        var sessionID: UUID
        var kind: String
        var name: String
        var dataJSON: String?
        var workoutID: UUID?
        var setLogID: UUID?

        init(
            id: UUID,
            timestamp: Date,
            sessionID: UUID,
            kind: String,
            name: String,
            dataJSON: String?,
            workoutID: UUID?,
            setLogID: UUID?
        ) {
            self.id = id
            self.timestamp = timestamp
            self.sessionID = sessionID
            self.kind = kind
            self.name = name
            self.dataJSON = dataJSON
            self.workoutID = workoutID
            self.setLogID = setLogID
        }
    }
}
