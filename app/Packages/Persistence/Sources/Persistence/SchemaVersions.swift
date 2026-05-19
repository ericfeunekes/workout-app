// SchemaVersions.swift
//
// Versioned SwiftData schema. The runtime uses the LATEST version
// (`WorkoutDBSchemaV9`). Older versions are preserved here so SwiftData
// can migrate a store that was written by a previous app build — without
// the version enum for the old shape, SwiftData has nothing to compare
// the on-disk store's metadata against and will fail (or, worse, corrupt)
// the store when the shape doesn't match the single declared schema.
//
// Shape contract: every version lists its own `@Model` snapshot. Each
// snapshot's model classes use the SAME simple name as the live latest types
// (`WorkoutModel`, `ExerciseModel`, …) so the CoreData entity name is
// stable across versions — that's what SwiftData diffs to decide whether
// a migration applies. Nesting the snapshots inside the version enum
// keeps the Swift-type namespace clear; the rest of the package reads
// the file-scope latest types unqualified.
//
// V1 → V2 is lightweight: V2 only adds optional-nullable `String` columns
// (`defaultPrescriptionJSON`, `defaultAlternativesJSON` on Exercise;
// `prescriptionJSONRaw` on WorkoutItem). No data transform, no backfill,
// no required-property promotion. See
// `docs/decisions/ADR-2026-04-18-smart-defaults.md` and the matching
// server migration `server/db/migrations/006_exercise_defaults.sql`.
//
// V2 → V3 is lightweight + post-open backfill: adds two nullable columns
// to SetLog — `workoutID` and `plannedExerciseID`. The lightweight stage
// introduces them as nil; `backfillSetLogDenormalization(context:)` runs
// once at factory open after a V2 store has been migrated and resolves
// each nil `workoutID` / `plannedExerciseID` via the parent WorkoutItem
// → Block chain.
//
// V3 → V4 is lightweight + post-open backfill (perf-002): adds two
// columns to `PushItemModel` — `priority: Int` (non-optional, default
// derived from envelope kind) and `dedupKey: String?` (nullable). The
// lightweight stage introduces them with SwiftData's default values
// (0 / nil); `backfillPushItemPriorityAndDedupKey(context:)` then
// decodes each row's payload envelope and populates both columns from
// `PushItem.Payload.priority` / `.dedupKey`. Rows whose payload can no
// longer be decoded are left at the defaults — the startup
// `pruneUndecodableRows` sweep eventually removes them, and the
// intermediate state is harmless (priority 0 is the safe lane, nil
// dedupKey just means the row won't collide with future enqueues).
// Non-optional integer columns must be lightweight-safe for SwiftData:
// the default value is synthesized automatically, so we don't fight the
// non-null contract with a custom stage here.
//
// V4 → V5 is lightweight: adds nullable `Block.intent`, plus
// `SetLog.skipped` and `SetLog.sideRaw` with defaults matching the
// server migration (`false` / `bilateral`).
//
// V5 → V6 is lightweight: adds `PrimitiveWorkoutModel`, the intact pulled
// Block > Set > Slot payload used by the primitive execution runtime.
//
// V6 → V7 is lightweight: adds `PrimitiveSetLogModel` so primitive result
// rows are first-class queryable data. The primitive cutover explicitly
// permits resetting QA workout/result data, so embedded V6 primitive logs are
// not preserved.
//
// V7 → V8 is lightweight: adds HealthKit archive projection rows. HealthKit is
// authoritative for the underlying samples; the new rows are local projection
// state for export/readback and have no existing data to preserve.
//
// V8 → V9 is lightweight: adds nullable/defaulted telemetry fields to
// PrimitiveSetLogModel (`hrAvgBpm`, `hrMaxBpm`, `skipped`, `sideRaw`, `notes`)
// so watch-originated result data survives local persistence and sync.
//
// Shadow @Model types for V1 / V2 / V3 / V4 live in their dedicated
// `SchemaVersionsV{N}Models.swift` files so the version enum bodies
// stay under SwiftLint's `type_body_length` cap. V6 keeps its one-off
// primitive workout snapshot inline because downstream SwiftPM package
// builds must always see that schema extension when compiling Persistence
// as a dependency.

import CoreDomain
import Foundation
import SwiftData

// MARK: - V1 (pre-006) — snapshot of the old columns

public enum WorkoutDBSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    // `models` is declared in `SchemaVersionsV1Models.swift`.
}

// MARK: - V2 (post-006, pre-R1.4) — snapshot of the smart-defaults shape

public enum WorkoutDBSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            WorkoutModel.self,
            BlockModel.self,
            WorkoutItemModel.self,
            ExerciseModel.self,
            ExerciseAlternativeModel.self,
            SetLogModel.self,
            UserParameterModel.self,
            AppUserModel.self,
            SessionSnapshotModel.self,
            PushItemModel.self,
            EventModel.self,
        ]
    }
}

// MARK: - V3 (R1.4, pre-perf-002) — SetLog denormalization

public enum WorkoutDBSchemaV3: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            WorkoutModel.self,
            BlockModel.self,
            WorkoutItemModel.self,
            ExerciseModel.self,
            ExerciseAlternativeModel.self,
            SetLogModel.self,
            UserParameterModel.self,
            AppUserModel.self,
            SessionSnapshotModel.self,
            PushItemModel.self,
            EventModel.self,
        ]
    }
}

// MARK: - V4 (perf-002, pre-schema-2026-04-26) — PushItem priority + dedupKey columns

public enum WorkoutDBSchemaV4: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    // `models` is declared in `SchemaVersionsV4Models.swift`.
}

// MARK: - V5 (current, schema-2026-04-26) — skipped/side/intent fields

public enum WorkoutDBSchemaV5: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            WorkoutModel.self,
            BlockModel.self,
            WorkoutItemModel.self,
            ExerciseModel.self,
            ExerciseAlternativeModel.self,
            SetLogModel.self,
            UserParameterModel.self,
            AppUserModel.self,
            SessionSnapshotModel.self,
            PushItemModel.self,
            EventModel.self,
        ]
    }
}

// MARK: - V6 (current, primitive cutover checkpoint 1) — primitive workout payload cache

public enum WorkoutDBSchemaV6: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            WorkoutModel.self,
            PrimitiveWorkoutModel.self,
            BlockModel.self,
            WorkoutItemModel.self,
            ExerciseModel.self,
            ExerciseAlternativeModel.self,
            SetLogModel.self,
            UserParameterModel.self,
            AppUserModel.self,
            SessionSnapshotModel.self,
            PushItemModel.self,
            EventModel.self,
        ]
    }

    @Model
    final class PrimitiveWorkoutModel {
        @Attribute(.unique) var id: UUID
        var name: String
        var payloadJSON: String
        var primitiveSetLogsJSON: String

        init(
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
}

// MARK: - V7 (primitive result rows) — first-class primitive set logs

public enum WorkoutDBSchemaV7: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(7, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            WorkoutModel.self,
            PrimitiveWorkoutModel.self,
            PrimitiveSetLogModel.self,
            BlockModel.self,
            WorkoutItemModel.self,
            ExerciseModel.self,
            ExerciseAlternativeModel.self,
            SetLogModel.self,
            UserParameterModel.self,
            AppUserModel.self,
            SessionSnapshotModel.self,
            PushItemModel.self,
            EventModel.self,
        ]
    }

    @Model
    final class PrimitiveSetLogModel {
        @Attribute(.unique) var id: UUID
        var roleRaw: String
        var slotID: UUID?
        var setID: UUID?
        var blockID: UUID?
        var workoutID: UUID
        var plannedExerciseID: UUID?
        var performedExerciseID: UUID?
        var setIndex: Int
        var setRepeatIndex: Int
        var blockRepeatIndex: Int
        var reps: Int?
        var weight: Double?
        var weightUnitRaw: String?
        var durationSec: Double?
        var distanceM: Double?
        var rounds: Int?
        var rir: Int?
        var isWarmup: Bool
        var completedAt: Date

        init(
            id: UUID,
            roleRaw: String,
            slotID: UUID?,
            setID: UUID?,
            blockID: UUID?,
            workoutID: UUID,
            plannedExerciseID: UUID?,
            performedExerciseID: UUID?,
            setIndex: Int,
            setRepeatIndex: Int,
            blockRepeatIndex: Int,
            reps: Int?,
            weight: Double?,
            weightUnitRaw: String?,
            durationSec: Double?,
            distanceM: Double?,
            rounds: Int?,
            rir: Int?,
            isWarmup: Bool,
            completedAt: Date
        ) {
            self.id = id
            self.roleRaw = roleRaw
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
            self.weightUnitRaw = weightUnitRaw
            self.durationSec = durationSec
            self.distanceM = distanceM
            self.rounds = rounds
            self.rir = rir
            self.isWarmup = isWarmup
            self.completedAt = completedAt
        }
    }
}

// MARK: - V8 (HealthKit archive projection)

public enum WorkoutDBSchemaV8: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(8, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            WorkoutModel.self,
            PrimitiveWorkoutModel.self,
            PrimitiveSetLogModel.self,
            HealthDataRecordModel.self,
            HealthDataDeletionModel.self,
            HealthBatchCursorModel.self,
            BlockModel.self,
            WorkoutItemModel.self,
            ExerciseModel.self,
            ExerciseAlternativeModel.self,
            SetLogModel.self,
            UserParameterModel.self,
            AppUserModel.self,
            SessionSnapshotModel.self,
            PushItemModel.self,
            EventModel.self,
        ]
    }

    @Model
    final class PrimitiveSetLogModel {
        @Attribute(.unique) var id: UUID
        var roleRaw: String
        var slotID: UUID?
        var setID: UUID?
        var blockID: UUID?
        var workoutID: UUID
        var plannedExerciseID: UUID?
        var performedExerciseID: UUID?
        var setIndex: Int
        var setRepeatIndex: Int
        var blockRepeatIndex: Int
        var reps: Int?
        var weight: Double?
        var weightUnitRaw: String?
        var durationSec: Double?
        var distanceM: Double?
        var rounds: Int?
        var rir: Int?
        var isWarmup: Bool
        var completedAt: Date

        init(
            id: UUID,
            roleRaw: String,
            slotID: UUID?,
            setID: UUID?,
            blockID: UUID?,
            workoutID: UUID,
            plannedExerciseID: UUID?,
            performedExerciseID: UUID?,
            setIndex: Int,
            setRepeatIndex: Int,
            blockRepeatIndex: Int,
            reps: Int?,
            weight: Double?,
            weightUnitRaw: String?,
            durationSec: Double?,
            distanceM: Double?,
            rounds: Int?,
            rir: Int?,
            isWarmup: Bool,
            completedAt: Date
        ) {
            self.id = id
            self.roleRaw = roleRaw
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
            self.weightUnitRaw = weightUnitRaw
            self.durationSec = durationSec
            self.distanceM = distanceM
            self.rounds = rounds
            self.rir = rir
            self.isWarmup = isWarmup
            self.completedAt = completedAt
        }
    }
}

// MARK: - V9 (primitive set-log telemetry)

public enum WorkoutDBSchemaV9: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(9, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            WorkoutModel.self,
            PrimitiveWorkoutModel.self,
            PrimitiveSetLogModel.self,
            HealthDataRecordModel.self,
            HealthDataDeletionModel.self,
            HealthBatchCursorModel.self,
            BlockModel.self,
            WorkoutItemModel.self,
            ExerciseModel.self,
            ExerciseAlternativeModel.self,
            SetLogModel.self,
            UserParameterModel.self,
            AppUserModel.self,
            SessionSnapshotModel.self,
            PushItemModel.self,
            EventModel.self,
        ]
    }
}

// MARK: - Migration plan

public enum WorkoutDBMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [
            WorkoutDBSchemaV1.self,
            WorkoutDBSchemaV2.self,
            WorkoutDBSchemaV3.self,
            WorkoutDBSchemaV4.self,
            WorkoutDBSchemaV5.self,
            WorkoutDBSchemaV6.self,
            WorkoutDBSchemaV7.self,
            WorkoutDBSchemaV8.self,
            WorkoutDBSchemaV9.self,
        ]
    }

    public static var stages: [MigrationStage] {
        [
            // V1 → V2 adds three optional-nullable String columns
            // (see file header + SwiftDataModels.swift). No data transform
            // is needed — every V1 row's new columns default to nil, which
            // is exactly what the domain expects for rows authored before
            // server migration 006 shipped.
            .lightweight(
                fromVersion: WorkoutDBSchemaV1.self,
                toVersion: WorkoutDBSchemaV2.self
            ),
            // V2 → V3 adds two optional-nullable columns to SetLog
            // (`workoutID` and `plannedExerciseID`). The lightweight
            // stage introduces them as nil; `PersistenceFactory` runs
            // `backfillSetLogDenormalization` once on the first open
            // after migration to resolve each nil from the parent
            // WorkoutItem → Block chain.
            .lightweight(
                fromVersion: WorkoutDBSchemaV2.self,
                toVersion: WorkoutDBSchemaV3.self
            ),
            // V3 → V4 adds `priority: Int` (non-optional, default 0) and
            // `dedupKey: String?` (nullable) to `PushItemModel`. The
            // lightweight stage introduces both with SwiftData's defaults;
            // `backfillPushItemPriorityAndDedupKey` then decodes each
            // row's payload envelope and populates the real values. See
            // the file header for the rationale.
            .lightweight(
                fromVersion: WorkoutDBSchemaV3.self,
                toVersion: WorkoutDBSchemaV4.self
            ),
            .lightweight(
                fromVersion: WorkoutDBSchemaV4.self,
                toVersion: WorkoutDBSchemaV5.self
            ),
            .lightweight(
                fromVersion: WorkoutDBSchemaV5.self,
                toVersion: WorkoutDBSchemaV6.self
            ),
            .lightweight(
                fromVersion: WorkoutDBSchemaV6.self,
                toVersion: WorkoutDBSchemaV7.self
            ),
            .lightweight(
                fromVersion: WorkoutDBSchemaV7.self,
                toVersion: WorkoutDBSchemaV8.self
            ),
            .lightweight(
                fromVersion: WorkoutDBSchemaV8.self,
                toVersion: WorkoutDBSchemaV9.self
            ),
        ]
    }
}

// MARK: - V3 backfill

/// Populate `workoutID` + `plannedExerciseID` for SetLog rows left nil
/// by the V2→V3 lightweight migration. Idempotent: rows whose columns
/// are already populated are skipped.
///
/// Strategy: build a single `[itemID: (workoutID, exerciseID)]` map from
/// every surviving `WorkoutItemModel` up-front, then iterate candidate
/// SetLogs and resolve via lookup. This closes the R1.4 fix-it hole
/// where a SetLog's parent `WorkoutItemModel` was reconciled away
/// *before* the V3 upgrade (R1.3 detach-on-reconcile path): the
/// original backfill bailed on the first missing-item fetch and left
/// `workoutID` nil forever, because the row's own `workoutItemID`
/// pointed at a model that no longer existed. The map form is also
/// cheaper — O(items + logs) rather than O(logs) WorkoutItem fetches.
///
/// Rows whose `workoutItemID` matches no surviving WorkoutItem stay
/// nil (truly orphaned: parent item AND its block are gone, and we
/// cannot invent a workoutID for them). Surface them via
/// `WorkoutCacheImpl.loadOrphanedSetLogs()` so a user can still see
/// the raw log entries — losing local set_logs silently is the one
/// invariant `CLAUDE.md` names as load-bearing.
///
/// Called from `PersistenceFactory` after the container opens. Safe to
/// call on every app launch — the fast path is one descriptor fetch
/// that returns an empty result once the backfill has run. Public so
/// tests can drive it directly against an open V4 container seeded
/// from a V2 fixture.
public func backfillSetLogDenormalization(context: ModelContext) throws {
    // Fast path — only scan rows that still need backfill. SwiftData
    // predicates allow a `nil` check on an optional property.
    let descriptor = FetchDescriptor<SetLogModel>(
        predicate: #Predicate<SetLogModel> { $0.workoutID == nil }
    )
    let candidates = try context.fetch(descriptor)
    guard !candidates.isEmpty else { return }

    // Build the resolution map once from every surviving WorkoutItem.
    // We also cache block.workoutID by blockID so the inner lookup is a
    // dictionary hit, not a fetch per log. Surviving items whose parent
    // block was itself deleted (shouldn't happen under the cascade
    // rules, but we stay defensive) fall through as unresolved.
    let itemMap = try buildItemResolutionMap(context: context)
    for log in candidates {
        guard let resolved = itemMap[log.workoutItemID] else {
            // Truly orphaned — parent item is gone and no surviving
            // row can tell us which workout this log belonged to.
            // Leave columns nil so `loadOrphanedSetLogs()` can still
            // surface the row for recovery.
            continue
        }
        if log.plannedExerciseID == nil {
            log.plannedExerciseID = resolved.exerciseID
        }
        log.workoutID = resolved.workoutID
    }
    try context.save()
}

/// One entry in the backfill resolution map: everything the SetLog
/// backfill needs to populate from a surviving WorkoutItem row.
private struct ItemResolution {
    let workoutID: UUID
    let exerciseID: UUID
}

/// Scan every `WorkoutItemModel` in the context, join with its parent
/// block, and emit a `[itemID: ItemResolution]` map. Unreachable items
/// (block missing) are simply not emitted, which is fine: those logs
/// fall through to the "truly orphaned" bucket.
private func buildItemResolutionMap(context: ModelContext) throws -> [UUID: ItemResolution] {
    let blocks = try context.fetch(FetchDescriptor<BlockModel>())
    let workoutIDByBlock = Dictionary(
        uniqueKeysWithValues: blocks.map { ($0.id, $0.workoutID) }
    )

    let items = try context.fetch(FetchDescriptor<WorkoutItemModel>())
    var out: [UUID: ItemResolution] = [:]
    out.reserveCapacity(items.count)
    for item in items {
        guard let workoutID = workoutIDByBlock[item.blockID] else { continue }
        out[item.id] = ItemResolution(
            workoutID: workoutID,
            exerciseID: item.exerciseID
        )
    }
    return out
}

// MARK: - V4 backfill

/// Populate `priority` + `dedupKey` on every `PushItemModel` row that
/// still carries the V3 defaults (priority==0, dedupKey==nil). The
/// V3→V4 lightweight stage introduces both columns with SwiftData's
/// defaults; this backfill then decodes each row's envelope and
/// rewrites the columns to the real values derived from
/// `PushItem.Payload.priority` / `.dedupKey`.
///
/// Idempotence: a row is skipped if its `dedupKey` is already set OR
/// its decoded payload genuinely has no dedup key AND its priority is
/// already correct. The function can be called on every launch; after
/// the first pass the scan still runs but no writes fire.
///
/// Forgiving to poison rows: if an envelope fails to decode we leave
/// the row at its defaults. The startup `pruneUndecodableRows` sweep
/// (see `PushQueueStoreImpl`) removes such rows eventually; an
/// in-between launch that carries them at priority 0 / dedupKey nil is
/// harmless — priority 0 is the safe (results-first) lane and a nil
/// dedupKey just means the row won't collide with future enqueues of
/// the same logical identity. Losing one collision window for a row
/// that's about to be pruned anyway is the right trade.
///
/// Single-user note: queue depth in the real system is single digits
/// steady state, thousands worst case. A one-shot O(n) decode on
/// launch is negligible. Called from `PersistenceFactory` once per
/// container open.
public func backfillPushItemPriorityAndDedupKey(context: ModelContext) throws {
    let descriptor = FetchDescriptor<PushItemModel>()
    let rows = try context.fetch(descriptor)
    guard !rows.isEmpty else { return }
    var mutated = false
    for row in rows {
        guard let payload = try? PushQueuePayloadCoding.decode(row.payloadJSON) else {
            // Leave poison rows at the defaults — pruneUndecodableRows
            // will sweep them. See the function header for the rationale.
            continue
        }
        let expectedPriority = payload.priority
        let expectedDedupKey = payload.dedupKey
        if row.priority != expectedPriority {
            row.priority = expectedPriority
            mutated = true
        }
        if row.dedupKey != expectedDedupKey {
            row.dedupKey = expectedDedupKey
            mutated = true
        }
    }
    if mutated {
        try context.save()
    }
}
