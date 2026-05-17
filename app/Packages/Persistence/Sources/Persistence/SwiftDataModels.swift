// SwiftDataModels.swift
//
// @Model classes mirroring the CoreDomain entities. One-to-one with the
// server's SQLite schema so on-device storage matches the wire shape —
// Domain ↔ @Model mapping lives in `DomainMapping.swift`.
//
// Every JSON blob field (`prescriptionJSON`, `timingConfigJSON`, etc.) is
// stored as a `String`. SwiftData deliberately does not crack the JSON — new
// prescription shapes are data-only changes (see
// `docs/specs/v2-architecture.md` and `docs/prescription.md`).
//
// Relationships follow the spec's cascade rules:
//   • Workout → Block → WorkoutItem → SetLog : all cascade (deleting a
//     workout tears the whole subtree down).
//   • Exercise → ExerciseAlternative : nullify (alternatives survive
//     exercise deletion as dangling UUIDs — the app still renders the name
//     from the alternative's own exerciseID lookup; if the exercise is gone
//     the render falls back to "Unknown exercise" rather than crashing).
//   • SetLog.performedExerciseID is stored as a raw UUID, NOT a
//     `@Relationship`. Exercises can be replaced server-side (Claude
//     overwrites on UUID); we do not want those overwrites to cascade into
//     historical set_logs. Keep the link loose.
//
// These file-scope classes are the latest `WorkoutDBSchemaV6` shape
// (post-perf-002 PushItem `priority` + `dedupKey` columns). The V1
// (pre-006), V2 (post-006, pre-R1.4), and V3 (R1.4, pre-perf-002)
// shapes are preserved as shadow @Model types inside their respective
// `WorkoutDBSchemaVN` enums in their dedicated models files so
// SwiftData can diff and migrate an older store in place. Future
// schema bumps add a new snapshot there and register a
// `MigrationPlan` stage.

import Foundation
import SwiftData

// MARK: - WorkoutModel

@Model
public final class WorkoutModel {
    @Attribute(.unique) public var id: UUID
    public var userID: UUID
    public var name: String
    public var scheduledDate: Date?
    /// Stored as the raw rawValue (`planned`, `active`, `completed`, `skipped`).
    public var statusRaw: String
    /// Stored as the raw rawValue (`claude`, `manual`).
    public var sourceRaw: String
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var tagsJSON: String?

    @Relationship(deleteRule: .cascade, inverse: \BlockModel.workout)
    public var blocks: [BlockModel] = []

    public init(
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

// MARK: - PrimitiveWorkoutModel

@Model
public final class PrimitiveWorkoutModel {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var payloadJSON: String
    public var primitiveSetLogsJSON: String

    public init(
        id: UUID,
        name: String,
        payloadJSON: String,
        primitiveSetLogsJSON: String = "[]"
    ) {
        self.id = id
        self.name = name
        self.payloadJSON = payloadJSON
        self.primitiveSetLogsJSON = primitiveSetLogsJSON
    }
}

// MARK: - BlockModel

@Model
public final class BlockModel {
    @Attribute(.unique) public var id: UUID
    public var workoutID: UUID
    public var parentBlockID: UUID?
    public var position: Int
    public var name: String?
    /// Raw rawValue from `TimingMode` (e.g. `straight_sets`).
    public var timingModeRaw: String
    public var timingConfigJSON: String
    public var rounds: Int?
    public var roundsRepSchemeJSON: String?
    public var notes: String?
    public var intent: String?

    /// Inverse of WorkoutModel.blocks. Not optional in the data sense — every
    /// block belongs to a workout — but SwiftData requires optional inverses
    /// for cascade rules to resolve.
    public var workout: WorkoutModel?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutItemModel.block)
    public var items: [WorkoutItemModel] = []

    public init(
        id: UUID,
        workoutID: UUID,
        parentBlockID: UUID?,
        position: Int,
        name: String?,
        timingModeRaw: String,
        timingConfigJSON: String,
        rounds: Int?,
        roundsRepSchemeJSON: String?,
        notes: String?,
        intent: String? = nil
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
        self.intent = intent
    }
}

// MARK: - WorkoutItemModel

@Model
public final class WorkoutItemModel {
    @Attribute(.unique) public var id: UUID
    public var blockID: UUID
    public var position: Int
    public var exerciseID: UUID
    /// Resolved form (server already merged library defaults in).
    public var prescriptionJSON: String
    /// Optional snapshot of the sparse payload the client originally sent.
    /// Nil when the resolved prescription equals what was sent. See
    /// `ADR-2026-04-18-smart-defaults.md`. Added in V2 as a lightweight
    /// migration from V1 — optional, no default, no data-transform.
    public var prescriptionJSONRaw: String?

    public var block: BlockModel?

    @Relationship(deleteRule: .cascade, inverse: \SetLogModel.workoutItem)
    public var setLogs: [SetLogModel] = []

    @Relationship(deleteRule: .cascade, inverse: \ExerciseAlternativeModel.workoutItem)
    public var alternatives: [ExerciseAlternativeModel] = []

    public init(
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

// MARK: - ExerciseModel

@Model
public final class ExerciseModel {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var notes: String?
    public var demoURLString: String?
    /// Library-level prescription defaults. Added in V2 as a lightweight
    /// migration from V1. The app does not read this at runtime — the
    /// server merges it into each workout_item's prescription_json before
    /// the app ever sees it. See `ADR-2026-04-18-smart-defaults.md`.
    public var defaultPrescriptionJSON: String?
    /// Library-level alternatives list. Same runtime story — round-tripped
    /// only.
    public var defaultAlternativesJSON: String?

    public init(
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

// MARK: - ExerciseAlternativeModel

@Model
public final class ExerciseAlternativeModel {
    @Attribute(.unique) public var id: UUID
    public var workoutItemID: UUID
    /// Loose UUID link to an exercise. NOT a SwiftData @Relationship — see
    /// the file header for why alternatives must not cascade from exercise
    /// deletion.
    public var exerciseID: UUID
    public var reason: String
    public var parameterOverridesJSON: String?

    public var workoutItem: WorkoutItemModel?

    public init(
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

// MARK: - SetLogModel

@Model
public final class SetLogModel {
    @Attribute(.unique) public var id: UUID
    public var workoutItemID: UUID
    /// Denormalized copy of the parent Workout's id, stamped at log
    /// time so `loadSetLogs(workoutID:)` can resolve via a direct
    /// `FetchDescriptor` predicate without walking blocks → items.
    /// This lets logs survive reconcile (see
    /// `WorkoutCache+Reconcile.swift`'s `detachSetLogs` dance) while
    /// still being visible to History via the public API — the R1.3
    /// fix preserved rows on disk but the block→item walk still lost
    /// them because the parent item was gone. Nullable on disk to
    /// tolerate the V2→V3 lightweight migration + best-effort
    /// backfill; new writes always populate it.
    public var workoutID: UUID?
    /// Denormalized copy of the parent WorkoutItem's planned
    /// `exerciseID`, stamped at log time. Lets `loadSetLogs(exerciseID:)`
    /// resolve planned-exercise matches with a direct predicate (no
    /// WorkoutItem fetch required), so History keeps surfacing logged
    /// sets even after the parent item has been reconciled away.
    /// `performedExerciseID` (above) still captures mid-workout swaps
    /// separately; the History query ORs the two.
    public var plannedExerciseID: UUID?
    /// Nil unless the user swapped mid-workout. Stored as a raw UUID — no
    /// SwiftData relationship, per file header.
    public var performedExerciseID: UUID?
    public var setIndex: Int
    public var reps: Int?
    public var weight: Double?
    public var weightUnitRaw: String?
    public var durationSec: Double?
    public var distanceM: Double?
    public var rir: Int?
    public var isWarmup: Bool
    public var skipped: Bool = false
    public var sideRaw: String = "bilateral"
    public var startedAt: Date?
    public var completedAt: Date
    public var hrAvgBpm: Int?
    public var hrMaxBpm: Int?
    public var cadenceAvgSpm: Int?
    public var motionSamplesRef: String?
    public var notes: String?

    public var workoutItem: WorkoutItemModel?

    public init(
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
        skipped: Bool = false,
        sideRaw: String = "bilateral",
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
        self.skipped = skipped
        self.sideRaw = sideRaw
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.hrAvgBpm = hrAvgBpm
        self.hrMaxBpm = hrMaxBpm
        self.cadenceAvgSpm = cadenceAvgSpm
        self.motionSamplesRef = motionSamplesRef
        self.notes = notes
    }
}

// MARK: - UserParameterModel

@Model
public final class UserParameterModel {
    @Attribute(.unique) public var id: UUID
    public var userID: UUID
    public var key: String
    public var value: String
    public var updatedAt: Date
    /// Raw rawValue from `UserParameterSource` (`claude`, `app_log`, `manual`).
    public var sourceRaw: String

    public init(
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

// MARK: - AppUserModel

@Model
public final class AppUserModel {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var createdAt: Date

    public init(id: UUID, name: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

// MARK: - SessionSnapshotModel
//
// Single-row-ever table holding the encoded `SessionState` JSON. We do not
// dismember SessionState into columns — Core/Session owns the shape and we
// keep the serialization boundary narrow. On load we decode JSON → domain;
// on save we encode the reverse.

@Model
public final class SessionSnapshotModel {
    /// Hardcoded singleton ID. There is only ever one live session, so we
    /// key the row on a constant UUID and upsert.
    @Attribute(.unique) public var id: UUID
    public var encodedJSON: Data
    public var savedAt: Date

    public init(id: UUID = SessionSnapshotModel.singletonID, encodedJSON: Data, savedAt: Date) {
        self.id = id
        self.encodedJSON = encodedJSON
        self.savedAt = savedAt
    }

    // Hardcoded UUID literal — the string is syntactically valid at compile
    // time, so `UUID(uuidString:)` cannot fail. The force-unwrap documents
    // the intent better than a `fatalError` fallback would.
    // swiftlint:disable:next force_unwrapping
    public static let singletonID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}

// MARK: - PushItemModel
//
// Durable row for the PushQueueStore implementation. The payload is encoded
// as a small JSON envelope (see `PushQueueStoreImpl`) so the PushItem shape
// can evolve without schema churn. `id` is the PushItem's UUID so enqueue is
// idempotent on retry.
//
// V4 columns (added in perf-002):
//   • `priority` — drain-order weighting. `0` for results (setLogs,
//     statusUpdate, userParameter), `1` for telemetry events. Stored so
//     `peek` can resolve the `(priority, enqueuedAt)` sort inside
//     SwiftData / SQLite instead of decoding every row's envelope in
//     memory on every flush.
//   • `dedupKey` — stable logical-identity string (see
//     `PushItem.Payload.dedupKey` for the shape contract). Nil for
//     payloads that do not participate in dedup (batch setLogs and
//     telemetry events). Persisted so `PushQueue+Dedup.swift` can drop
//     prior matching rows via a scoped `FetchDescriptor` predicate
//     instead of a full-table peek + decode.

@Model
public final class PushItemModel {
    @Attribute(.unique) public var id: UUID
    public var enqueuedAt: Date
    public var attempts: Int
    public var payloadJSON: Data
    /// Drain priority. Non-optional at the Swift level, but declared
    /// with a stored default of `0` so SwiftData's lightweight
    /// migration can add the column to a pre-perf-002 (V3) store
    /// without a custom stage — Core Data uses the declared default
    /// when the column materializes on existing rows. The post-open
    /// `backfillPushItemPriorityAndDedupKey` then rewrites the real
    /// value from each row's decoded envelope. See the V4 migration
    /// header in `SchemaVersions.swift`.
    public var priority: Int = 0
    public var dedupKey: String?

    public init(
        id: UUID,
        enqueuedAt: Date,
        attempts: Int,
        payloadJSON: Data,
        priority: Int,
        dedupKey: String?
    ) {
        self.id = id
        self.enqueuedAt = enqueuedAt
        self.attempts = attempts
        self.payloadJSON = payloadJSON
        self.priority = priority
        self.dedupKey = dedupKey
    }
}

// MARK: - EventModel
//
// Durable row for a structured telemetry event. Mirrors the on-wire
// `TelemetryEvent` DTO and the in-process `CoreTelemetry.Event` value
// type. The emitter inserts one row per `emit(_:)` call; the push queue
// drains rows to the server on the regular foreground cadence.
//
// `dataJSON` is a freeform string (the server never cracks it) so new
// event shapes don't require schema migrations. Workout / set_log IDs are
// loose UUID references, not SwiftData relationships — an event about a
// set_log that was later deleted shouldn't cascade into nothing.

@Model
public final class EventModel {
    @Attribute(.unique) public var id: UUID
    public var timestamp: Date
    public var sessionID: UUID
    public var kind: String
    public var name: String
    public var dataJSON: String?
    public var workoutID: UUID?
    public var setLogID: UUID?

    public init(
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
