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
            switch primitiveExecutionProjection(dto, workoutID: header.id) {
            case .success(let projection):
                return .success(MappedWorkout(
                    workout: workout,
                    blocks: projection.blocks,
                    items: projection.items,
                    alternatives: []
                ))
            case .failure(let error):
                return .failure(error)
            }
        }
    }

    private struct PrimitiveExecutionProjection {
        let blocks: [CoreDomain.Block]
        let items: [CoreDomain.WorkoutItem]
    }

    /// Project the primitive authoring contract into the current execution
    /// runtime's block/item cache. This is a runtime projection, not a wire
    /// fallback: the pulled API contract remains primitive-only, while the
    /// remaining execution surfaces consume their existing cached view until
    /// the UI runtime is fully primitive-native.
    private static func primitiveExecutionProjection(
        _ dto: WorkoutDBSchema.Workout,
        workoutID: UUID
    ) -> Result<PrimitiveExecutionProjection, SyncError> {
        var blocks: [CoreDomain.Block] = []
        var items: [CoreDomain.WorkoutItem] = []
        var blockPosition = 0
        for primitiveBlock in dto.primitiveBlocks {
            guard UUID(uuidString: primitiveBlock.id) != nil else {
                return .failure(.decode("PrimitiveBlock.id is not a UUID: \(primitiveBlock.id)"))
            }
            guard primitiveBlock.repeatCount == 1 else {
                return .failure(.decode(
                    "PrimitiveBlock.repeat > 1 is not supported by the current execution bridge"
                ))
            }
            for primitiveSet in primitiveBlock.sets {
                guard let projectedBlockID = UUID(uuidString: primitiveSet.id) else {
                    return .failure(.decode("PrimitiveSet.id is not a UUID: \(primitiveSet.id)"))
                }
                let projectedTimingMode = timingMode(for: primitiveSet)
                guard projectedTimingMode != .custom else {
                    return .failure(.decode(
                        "Primitive timing/traversal cell is not supported by the current execution bridge"
                    ))
                }
                blocks.append(CoreDomain.Block(
                    id: projectedBlockID,
                    workoutID: workoutID,
                    parentBlockID: nil,
                    position: blockPosition,
                    name: primitiveSet.title ?? primitiveBlock.title,
                    timingMode: projectedTimingMode,
                    timingConfigJSON: timingConfigJSON(for: primitiveSet),
                    rounds: projectedRounds(for: primitiveSet),
                    roundsRepSchemeJSON: nil,
                    notes: nil,
                    intent: nil
                ))
                for slot in primitiveSet.slots {
                    guard let itemID = UUID(uuidString: slot.id) else {
                        return .failure(.decode("PrimitiveSlot.id is not a UUID: \(slot.id)"))
                    }
                    guard let exerciseID = UUID(uuidString: slot.exerciseId) else {
                        return .failure(.decode(
                            "PrimitiveSlot.exercise_id is not a UUID: \(slot.exerciseId)"
                        ))
                    }
                    items.append(CoreDomain.WorkoutItem(
                        id: itemID,
                        blockID: projectedBlockID,
                        position: items.filter { $0.blockID == projectedBlockID }.count,
                        exerciseID: exerciseID,
                        prescriptionJSON: prescriptionJSON(for: primitiveSet, slot: slot)
                    ))
                }
                blockPosition += 1
            }
        }
        return .success(PrimitiveExecutionProjection(blocks: blocks, items: items))
    }

    private static func timingMode(
        for set: WorkoutDBSchema.PrimitiveSet?
    ) -> CoreDomain.TimingMode {
        guard let set else { return .custom }
        switch (set.timing.mode, set.traversal) {
        case (.setBounded, .sequential):
            return .straightSets
        case (.setBounded, .roundRobin):
            return .circuit
        case (.capBounded, .amrap):
            return .amrap
        case (.capBounded, .sequential):
            return .forTime
        case (.timeBounded, .roundRobin):
            return .intervals
        case (.timeBounded, .sequential):
            return .continuous
        case (.targetBounded, _):
            return .accumulate
        default:
            return .custom
        }
    }

    private static func projectedRounds(for set: WorkoutDBSchema.PrimitiveSet) -> Int? {
        switch (set.timing.mode, set.traversal) {
        case (.setBounded, .roundRobin), (.capBounded, .sequential):
            return max(1, set.repeatCount)
        default:
            return set.timing.rounds
        }
    }

    private static func timingConfigJSON(
        for set: WorkoutDBSchema.PrimitiveSet?
    ) -> String {
        guard let set else { return "{}" }
        var config: [String: Any] = [:]
        if let intervalSec = set.timing.intervalSec {
            config["interval_sec"] = intervalSec
        }
        if let capSec = set.timing.capSec {
            config["time_cap_sec"] = capSec
        }
        if let rounds = set.timing.rounds {
            config["rounds"] = rounds
        }
        return jsonString(config)
    }

    private static func prescriptionJSON(
        for set: WorkoutDBSchema.PrimitiveSet,
        slot: WorkoutDBSchema.PrimitiveSlot
    ) -> String {
        var prescription: [String: Any] = [:]
        prescription["sets"] = max(1, set.repeatCount)
        if let reps = slot.workTarget.first(where: { $0.metric == .reps })?.value {
            prescription["reps"] = Int(reps.rounded())
        }
        if let distance = slot.workTarget.first(where: { $0.metric == .distance })?.value {
            prescription["distance_m"] = distance
        }
        if let duration = slot.workTarget.first(where: { $0.metric == .duration })?.value {
            prescription["duration_sec"] = duration
        }
        if let load = slot.load {
            switch (load.unit, load.unitType, load.value) {
            case (.kg, .absolute, let value?):
                prescription["load_kg"] = value
                prescription["weight_unit"] = load.unit.rawValue
            case (.lb, .absolute, let value?):
                prescription["load_kg"] = value
                prescription["weight_unit"] = load.unit.rawValue
            case (.oneRepMax, .relative, let value?):
                prescription["percent_1rm"] = value
            default:
                break
            }
        }
        if let rir = slot.stimuli.first(where: { $0.type == .rir })?.target {
            prescription["target_rir"] = Int(rir.rounded())
        }
        if slot.isWarmup {
            prescription["warmup"] = true
        }
        return jsonString(prescription)
    }

    private static func jsonString(_ value: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
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

}
