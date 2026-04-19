// SchemaVersions.swift
//
// Versioned SwiftData schema. The runtime uses the LATEST version
// (`WorkoutDBSchemaV3`). Older versions are preserved here so SwiftData
// can migrate a store that was written by a previous app build — without
// the version enum for the old shape, SwiftData has nothing to compare
// the on-disk store's metadata against and will fail (or, worse, corrupt)
// the store when the shape doesn't match the single declared schema.
//
// Shape contract: every version lists its own `@Model` snapshot. Each
// snapshot's model classes use the SAME simple name as the live V3 types
// (`WorkoutModel`, `ExerciseModel`, …) so the CoreData entity name is
// stable across versions — that's what SwiftData diffs to decide whether
// a migration applies. Nesting the snapshots inside the version enum
// keeps the Swift-type namespace clear; the rest of the package reads
// the file-scope V3 types unqualified.
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
// → Block chain. Keeping both columns nullable (rather than doing a
// custom stage with a forced default) avoids fighting SwiftData's
// non-null contract during the entity rewrite and keeps the schema
// self-describing: a nil workoutID literally means "this row's parent
// chain was broken at backfill time" (only possible for the handful of
// R1.3-era detach-on-reconcile orphans — production writes after R1.4
// ships always populate both fields). See the R1.4 fix-it for the full
// rationale (history queries must not lose set_logs when reconcile
// removes a parent item).
//
// Shadow @Model types for V1 and V2 live in `SchemaVersionsV1Models.swift`
// and `SchemaVersionsV2Models.swift` so the version enum bodies stay
// under SwiftLint's `type_body_length` cap.

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

// MARK: - V3 (current, R1.4) — SetLog denormalization

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

// MARK: - Migration plan

public enum WorkoutDBMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [WorkoutDBSchemaV1.self, WorkoutDBSchemaV2.self, WorkoutDBSchemaV3.self]
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
            // WorkoutItem → Block chain. Splitting the data move out
            // of the schema stage avoids fighting SwiftData's
            // non-null contract during entity rewrite.
            .lightweight(
                fromVersion: WorkoutDBSchemaV2.self,
                toVersion: WorkoutDBSchemaV3.self
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
/// tests can drive it directly against an open V3 container seeded
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
