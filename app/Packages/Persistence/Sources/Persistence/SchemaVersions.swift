// SchemaVersions.swift
//
// Versioned SwiftData schema. v1 is the initial shape. Future migrations add
// a `WorkoutDBSchemaV2` (etc.) and register a stage in `WorkoutDBMigrationPlan`.
//
// The empty `stages` list is intentional — there is nothing to migrate from
// yet. When we bump to v2 we fill in the first `MigrationStage.lightweight(...)`
// or `.custom(...)` as per `docs/MIGRATIONS.md`.

import Foundation
import SwiftData

public enum WorkoutDBSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

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

public enum WorkoutDBMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [WorkoutDBSchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}
