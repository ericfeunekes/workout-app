// WorkoutCache+Upserts.swift
//
// Per-entity upsert helpers for `WorkoutCacheImpl`, split out of
// `WorkoutCache.swift` so the actor body stays under SwiftLint's
// `type_body_length` cap. Every helper is an upsert-on-UUID: fetch by id,
// apply the domain value in place if found, otherwise insert a fresh model.

import Foundation
import SwiftData
import CoreDomain
import WorkoutCoreFoundation

extension WorkoutCacheImpl {

    func upsertWorkout(_ w: Workout) throws {
        let id = w.id
        let descriptor = FetchDescriptor<WorkoutModel>(
            predicate: #Predicate<WorkoutModel> { $0.id == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.apply(w)
        } else {
            modelContext.insert(WorkoutModel.from(w))
        }
    }

    func upsertBlock(_ b: Block) throws {
        let id = b.id
        let descriptor = FetchDescriptor<BlockModel>(
            predicate: #Predicate<BlockModel> { $0.id == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.apply(b)
            try attachBlockToWorkout(existing, workoutID: b.workoutID)
        } else {
            let model = BlockModel.from(b)
            modelContext.insert(model)
            try attachBlockToWorkout(model, workoutID: b.workoutID)
        }
    }

    private func attachBlockToWorkout(_ block: BlockModel, workoutID: UUID) throws {
        let descriptor = FetchDescriptor<WorkoutModel>(
            predicate: #Predicate<WorkoutModel> { $0.id == workoutID }
        )
        if let parent = try modelContext.fetch(descriptor).first {
            block.workout = parent
        }
    }

    func upsertItem(_ i: WorkoutItem) throws {
        let id = i.id
        let descriptor = FetchDescriptor<WorkoutItemModel>(
            predicate: #Predicate<WorkoutItemModel> { $0.id == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.apply(i)
            try attachItemToBlock(existing, blockID: i.blockID)
        } else {
            let model = WorkoutItemModel.from(i)
            modelContext.insert(model)
            try attachItemToBlock(model, blockID: i.blockID)
        }
    }

    private func attachItemToBlock(_ item: WorkoutItemModel, blockID: UUID) throws {
        let descriptor = FetchDescriptor<BlockModel>(
            predicate: #Predicate<BlockModel> { $0.id == blockID }
        )
        if let parent = try modelContext.fetch(descriptor).first {
            item.block = parent
        }
    }

    func upsertAlternative(_ a: ExerciseAlternative) throws {
        let id = a.id
        let descriptor = FetchDescriptor<ExerciseAlternativeModel>(
            predicate: #Predicate<ExerciseAlternativeModel> { $0.id == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.apply(a)
            try attachAlternativeToItem(existing, itemID: a.workoutItemID)
        } else {
            let model = ExerciseAlternativeModel.from(a)
            modelContext.insert(model)
            try attachAlternativeToItem(model, itemID: a.workoutItemID)
        }
    }

    private func attachAlternativeToItem(_ alt: ExerciseAlternativeModel, itemID: UUID) throws {
        let descriptor = FetchDescriptor<WorkoutItemModel>(
            predicate: #Predicate<WorkoutItemModel> { $0.id == itemID }
        )
        if let parent = try modelContext.fetch(descriptor).first {
            alt.workoutItem = parent
        }
    }

    func upsertExercise(_ e: Exercise) throws {
        let id = e.id
        let descriptor = FetchDescriptor<ExerciseModel>(
            predicate: #Predicate<ExerciseModel> { $0.id == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.apply(e)
        } else {
            modelContext.insert(ExerciseModel.from(e))
        }
    }

    func upsertUserParameter(_ p: UserParameter) throws {
        // user_parameters is append-only — the server sends us every row, so
        // upsert on PK is safe (same UUID = same row; different UUID = new row).
        let id = p.id
        let descriptor = FetchDescriptor<UserParameterModel>(
            predicate: #Predicate<UserParameterModel> { $0.id == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.apply(p)
        } else {
            modelContext.insert(UserParameterModel.from(p))
        }
    }
}
