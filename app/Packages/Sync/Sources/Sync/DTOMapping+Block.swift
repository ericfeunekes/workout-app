// DTOMapping+Block.swift
//
// Block + WorkoutItem mapping. Flattens the nested wire shape
// (blocks -> workout_items -> alternatives) into three parallel lists on
// the domain side, matching the persistence table layout.

import Foundation
import CoreDomain
import WorkoutCoreFoundation
import WorkoutDBSchema

extension DTOMapping {

    // MARK: - WorkoutItem

    /// Flattens the nested wire shape into Domain: returns the `WorkoutItem`
    /// plus the alternatives that live under it.
    public static func mapWorkoutItem(
        _ dto: WorkoutDBSchema.WorkoutItem,
        blockID: BlockID
    ) -> Result<(item: CoreDomain.WorkoutItem, alternatives: [CoreDomain.ExerciseAlternative]), SyncError> {
        guard let id = UUID(uuidString: dto.id) else {
            return .failure(.decode("WorkoutItem.id is not a UUID: \(dto.id)"))
        }
        guard let exerciseID = UUID(uuidString: dto.exerciseId) else {
            return .failure(.decode("WorkoutItem.exercise_id is not a UUID: \(dto.exerciseId)"))
        }
        var alternatives: [CoreDomain.ExerciseAlternative] = []
        for altDTO in dto.alternatives {
            switch mapAlternative(altDTO, workoutItemID: id) {
            case .success(let alt): alternatives.append(alt)
            case .failure(let err): return .failure(err)
            }
        }
        let item = CoreDomain.WorkoutItem(
            id: id,
            blockID: blockID,
            position: dto.position,
            exerciseID: exerciseID,
            prescriptionJSON: dto.prescriptionJson,
            prescriptionJSONRaw: dto.prescriptionJsonRaw
        )
        return .success((item, alternatives))
    }

    // MARK: - Block

    public static func mapBlock(
        _ dto: WorkoutDBSchema.Block,
        workoutID: WorkoutID
    ) -> Result<
        (
            block: CoreDomain.Block,
            items: [CoreDomain.WorkoutItem],
            alternatives: [CoreDomain.ExerciseAlternative]
        ),
        SyncError
    > {
        guard let id = UUID(uuidString: dto.id) else {
            return .failure(.decode("Block.id is not a UUID: \(dto.id)"))
        }
        let parentID: BlockID?
        switch parseOptionalUUID(dto.parentBlockId, fieldName: "Block.parent_block_id") {
        case .success(let parsed): parentID = parsed
        case .failure(let err): return .failure(err)
        }
        guard let timingMode = CoreDomain.TimingMode(rawValue: dto.timingMode.rawValue) else {
            return .failure(.decode("Block.timing_mode unknown: \(dto.timingMode.rawValue)"))
        }
        switch mapBlockChildren(dto, blockID: id) {
        case .success(let children):
            let block = CoreDomain.Block(
                id: id,
                workoutID: workoutID,
                parentBlockID: parentID,
                position: dto.position,
                name: dto.name,
                timingMode: timingMode,
                timingConfigJSON: dto.timingConfigJson,
                rounds: dto.rounds,
                roundsRepSchemeJSON: dto.roundsRepSchemeJson,
                notes: dto.notes
            )
            return .success((block, children.items, children.alternatives))
        case .failure(let err):
            return .failure(err)
        }
    }

    /// Fan out the items nested under a `Block` DTO into parallel Domain
    /// arrays. Factored out of `mapBlock` to keep that function under the
    /// SwiftLint `function_body_length` cap.
    private static func mapBlockChildren(
        _ dto: WorkoutDBSchema.Block,
        blockID: BlockID
    ) -> Result<(items: [CoreDomain.WorkoutItem], alternatives: [CoreDomain.ExerciseAlternative]), SyncError> {
        var items: [CoreDomain.WorkoutItem] = []
        var alts: [CoreDomain.ExerciseAlternative] = []
        for itemDTO in dto.workoutItems {
            switch mapWorkoutItem(itemDTO, blockID: blockID) {
            case .success(let pair):
                items.append(pair.item)
                alts.append(contentsOf: pair.alternatives)
            case .failure(let err):
                return .failure(err)
            }
        }
        return .success((items, alts))
    }
}
