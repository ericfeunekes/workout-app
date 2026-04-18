// DTOMapping+Workout.swift
//
// Top-level Workout mapping. Walks the nested wire shape
// (workout -> blocks -> items -> alternatives) and returns a `MappedWorkout`
// with four flat arrays ready to hand to `WorkoutCache.save`.

import Foundation
import CoreDomain
import WorkoutCoreFoundation
import WorkoutDBSchema

extension DTOMapping {

    public static func mapWorkout(_ dto: WorkoutDBSchema.Workout) -> Result<MappedWorkout, SyncError> {
        switch decodeWorkoutHeader(dto) {
        case .failure(let err):
            return .failure(err)
        case .success(let header):
            switch mapWorkoutBlocks(dto, workoutID: header.id) {
            case .failure(let err):
                return .failure(err)
            case .success(let children):
                let workout = CoreDomain.Workout(
                    id: header.id,
                    userID: header.userID,
                    name: dto.name,
                    scheduledDate: header.scheduledDate,
                    status: header.status,
                    source: header.source,
                    notes: dto.notes,
                    createdAt: dto.createdAt,
                    updatedAt: dto.updatedAt,
                    completedAt: dto.completedAt,
                    tagsJSON: dto.tagsJson
                )
                return .success(MappedWorkout(
                    workout: workout,
                    blocks: children.blocks,
                    items: children.items,
                    alternatives: children.alternatives
                ))
            }
        }
    }

    /// The decoded leaf fields from a `Workout` DTO. Pulled out so
    /// `mapWorkout` can stay short.
    private struct WorkoutHeader {
        let id: UUID
        let userID: UUID
        let status: CoreDomain.WorkoutStatus
        let source: CoreDomain.WorkoutSource
        let scheduledDate: Date?
    }

    /// Validate and decode the scalar fields on a `Workout` DTO. Does not
    /// touch `blocks`.
    private static func decodeWorkoutHeader(
        _ dto: WorkoutDBSchema.Workout
    ) -> Result<WorkoutHeader, SyncError> {
        guard let id = UUID(uuidString: dto.id) else {
            return .failure(.decode("Workout.id is not a UUID: \(dto.id)"))
        }
        guard let userID = UUID(uuidString: dto.userId) else {
            return .failure(.decode("Workout.user_id is not a UUID: \(dto.userId)"))
        }
        guard let status = CoreDomain.WorkoutStatus(rawValue: dto.status.rawValue) else {
            return .failure(.decode("Workout.status unknown: \(dto.status.rawValue)"))
        }
        guard let source = CoreDomain.WorkoutSource(rawValue: dto.source.rawValue) else {
            return .failure(.decode("Workout.source unknown: \(dto.source.rawValue)"))
        }
        let scheduled: Date?
        if let raw = dto.scheduledDate {
            guard let parsed = parseDateOnly(raw) else {
                return .failure(.decode("Workout.scheduled_date is not y-M-d: \(raw)"))
            }
            scheduled = parsed
        } else {
            scheduled = nil
        }
        return .success(WorkoutHeader(
            id: id,
            userID: userID,
            status: status,
            source: source,
            scheduledDate: scheduled
        ))
    }

    /// Walk the `blocks` nesting under a `Workout` DTO and fan out into
    /// three parallel Domain arrays. Errors short-circuit.
    private static func mapWorkoutBlocks(
        _ dto: WorkoutDBSchema.Workout,
        workoutID: UUID
    ) -> Result<
        (
            blocks: [CoreDomain.Block],
            items: [CoreDomain.WorkoutItem],
            alternatives: [CoreDomain.ExerciseAlternative]
        ),
        SyncError
    > {
        var blocks: [CoreDomain.Block] = []
        var items: [CoreDomain.WorkoutItem] = []
        var alts: [CoreDomain.ExerciseAlternative] = []
        for blockDTO in dto.blocks {
            switch mapBlock(blockDTO, workoutID: workoutID) {
            case .success(let triple):
                blocks.append(triple.block)
                items.append(contentsOf: triple.items)
                alts.append(contentsOf: triple.alternatives)
            case .failure(let err):
                return .failure(err)
            }
        }
        return .success((blocks, items, alts))
    }
}
