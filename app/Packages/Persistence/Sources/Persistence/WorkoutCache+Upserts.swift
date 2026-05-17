// WorkoutCache+Upserts.swift
//
// Per-entity upsert helpers for `WorkoutCacheImpl`, split out of
// `WorkoutCache.swift` so the actor body stays under SwiftLint's
// `type_body_length` cap. Every helper is an upsert-on-UUID: look the id
// up in the preloaded id-keyed dictionary, apply the domain value in
// place if found, otherwise insert a fresh model and seed the dictionary
// so later rows can find it as a parent.
//
// Why the preload dictionary: `save(_:)` previously issued one
// `modelContext.fetch(descriptor)` per row (and another per parent
// attachment), which made the pull O(rows) in SQL query count. The new
// shape does one batched IN-predicate fetch per entity class in
// `WorkoutCache+Preload.swift` and threads the resulting dictionary
// through these helpers. Upsert then becomes a dictionary lookup.

import Foundation
import SwiftData
import CoreDomain
import WorkoutCoreFoundation

extension WorkoutCacheImpl {

    func upsertWorkout(_ w: Workout, preload: PullPreload) throws {
        if let existing = preload.workoutsByID[w.id] {
            existing.apply(w)
        } else {
            let model = WorkoutModel.from(w)
            modelContext.insert(model)
            // Seed the preload so child rows (blocks) in this same
            // save() batch can attach via the same dictionary without
            // a per-child parent fetch.
            preload.workoutsByID[w.id] = model
        }
    }

    func upsertPrimitiveWorkout(_ w: PrimitiveWorkout, preload: PullPreload) throws {
        if let existing = preload.primitiveWorkoutsByID[w.id] {
            try existing.apply(w)
        } else {
            let model = try PrimitiveWorkoutModel.from(w)
            modelContext.insert(model)
            preload.primitiveWorkoutsByID[w.id] = model
        }
    }

    func upsertBlock(_ b: Block, preload: PullPreload) throws {
        let model: BlockModel
        if let existing = preload.blocksByID[b.id] {
            existing.apply(b)
            model = existing
        } else {
            model = BlockModel.from(b)
            modelContext.insert(model)
            preload.blocksByID[b.id] = model
        }
        // Attach the parent relationship from the preload dictionary
        // rather than fetching per row.
        model.workout = preload.workoutsByID[b.workoutID]
    }

    func upsertItem(_ i: WorkoutItem, preload: PullPreload) throws {
        let model: WorkoutItemModel
        if let existing = preload.itemsByID[i.id] {
            existing.apply(i)
            model = existing
        } else {
            model = WorkoutItemModel.from(i)
            modelContext.insert(model)
            preload.itemsByID[i.id] = model
        }
        model.block = preload.blocksByID[i.blockID]
    }

    func upsertAlternative(_ a: ExerciseAlternative, preload: PullPreload) throws {
        let model: ExerciseAlternativeModel
        if let existing = preload.alternativesByID[a.id] {
            existing.apply(a)
            model = existing
        } else {
            model = ExerciseAlternativeModel.from(a)
            modelContext.insert(model)
            preload.alternativesByID[a.id] = model
        }
        model.workoutItem = preload.itemsByID[a.workoutItemID]
    }

    func upsertExercise(_ e: Exercise, preload: PullPreload) throws {
        if let existing = preload.exercisesByID[e.id] {
            existing.apply(e)
        } else {
            let model = ExerciseModel.from(e)
            modelContext.insert(model)
            preload.exercisesByID[e.id] = model
        }
    }

    func upsertUserParameter(_ p: UserParameter, preload: PullPreload) throws {
        // user_parameters is append-only — the server sends us every row, so
        // upsert on PK is safe (same UUID = same row; different UUID = new row).
        if let existing = preload.userParametersByID[p.id] {
            existing.apply(p)
        } else {
            let model = UserParameterModel.from(p)
            modelContext.insert(model)
            preload.userParametersByID[p.id] = model
        }
    }
}
