// PrimitiveExecutionPlan.swift
//
// Canonical executable state for the primitive authoring model. This lives in
// Core/Session because reducers, execution features, persistence, and sync
// all need the same runtime contract.

import Foundation
import CoreDomain
import WorkoutCoreFoundation

public struct ExecutionPlan: Equatable, Sendable {
    public var workoutID: WorkoutID
    public var blocks: [ExecutionBlock]

    public init(workoutID: WorkoutID, blocks: [ExecutionBlock]) {
        self.workoutID = workoutID
        self.blocks = blocks
    }

    public init(workout: PrimitiveWorkout) {
        self.workoutID = workout.id
        self.blocks = workout.blocks.map { ExecutionBlock(block: $0) }
    }
}

public struct ExecutionBlock: Equatable, Sendable {
    public var blockID: BlockID
    public var blockRepeat: Int
    public var workTargets: [PrimitiveWorkTarget]
    public var sets: [ExecutionSet]

    public init(blockID: BlockID, blockRepeat: Int, workTargets: [PrimitiveWorkTarget], sets: [ExecutionSet]) {
        self.blockID = blockID
        self.blockRepeat = blockRepeat
        self.workTargets = workTargets
        self.sets = sets
    }

    public init(block: PrimitiveBlock) {
        self.blockID = block.id
        self.blockRepeat = block.repeatCount
        self.workTargets = block.workTargets
        self.sets = block.sets.map { ExecutionSet(set: $0, blockID: block.id) }
    }

    public func blockResultLog(
        workoutID: WorkoutID,
        blockRepeatIndex: Int,
        durationSec: Double?,
        completedAt: Date
    ) -> PrimitiveSetLog {
        let coordinate = PrimitiveLogCoordinate(
            role: .blockResult,
            blockID: blockID,
            blockRepeatIndex: blockRepeatIndex
        )
        return PrimitiveSetLog(
            id: coordinate.deterministicLogID,
            role: .blockResult,
            blockID: blockID,
            workoutID: workoutID,
            setIndex: 0,
            blockRepeatIndex: blockRepeatIndex,
            durationSec: durationSec,
            completedAt: completedAt
        )
    }
}

public struct ExecutionSet: Equatable, Sendable {
    public var setID: PrimitiveSetID
    public var blockID: BlockID
    public var setRepeat: Int
    public var timing: PrimitiveTiming
    public var traversal: PrimitiveTraversal
    public var workTargets: [PrimitiveWorkTarget]
    public var slots: [ExecutionSlot]

    public init(
        setID: PrimitiveSetID,
        blockID: BlockID,
        setRepeat: Int,
        timing: PrimitiveTiming,
        traversal: PrimitiveTraversal,
        workTargets: [PrimitiveWorkTarget],
        slots: [ExecutionSlot]
    ) {
        self.setID = setID
        self.blockID = blockID
        self.setRepeat = setRepeat
        self.timing = timing
        self.traversal = traversal
        self.workTargets = workTargets
        self.slots = slots
    }

    public init(set: PrimitiveSet, blockID: BlockID) {
        self.setID = set.id
        self.blockID = blockID
        self.setRepeat = set.repeatCount
        self.timing = set.timing
        self.traversal = set.traversal
        self.workTargets = set.workTargets
        self.slots = set.slots.map { ExecutionSlot(slot: $0, setID: set.id, blockID: blockID) }
    }

    public func setResultLog(
        workoutID: WorkoutID,
        blockRepeatIndex: Int,
        setRepeatIndex: Int,
        reps: Int?,
        rounds: Int?,
        durationSec: Double?,
        completedAt: Date
    ) -> PrimitiveSetLog {
        let coordinate = PrimitiveLogCoordinate(
            role: .setResult,
            setID: setID,
            blockID: blockID,
            blockRepeatIndex: blockRepeatIndex,
            setRepeatIndex: setRepeatIndex
        )
        return PrimitiveSetLog(
            id: coordinate.deterministicLogID,
            role: .setResult,
            setID: setID,
            blockID: blockID,
            workoutID: workoutID,
            setIndex: 0,
            setRepeatIndex: setRepeatIndex,
            blockRepeatIndex: blockRepeatIndex,
            reps: reps,
            durationSec: durationSec,
            rounds: rounds,
            completedAt: completedAt
        )
    }
}

public struct ExecutionSlot: Equatable, Sendable {
    public var slotID: PrimitiveSlotID
    public var setID: PrimitiveSetID
    public var blockID: BlockID
    public var exerciseID: ExerciseID
    public var workTargets: [PrimitiveWorkTarget]
    public var loadKg: Double?
    public var loadUnit: WeightUnit?
    public var loadDisplayValue: Double?
    public var stimuli: [PrimitiveStimulus]
    public var postRestSec: Int
    public var isWarmup: Bool

    public init(
        slotID: PrimitiveSlotID,
        setID: PrimitiveSetID,
        blockID: BlockID,
        exerciseID: ExerciseID,
        workTargets: [PrimitiveWorkTarget],
        loadKg: Double?,
        loadUnit: WeightUnit?,
        loadDisplayValue: Double?,
        stimuli: [PrimitiveStimulus],
        postRestSec: Int,
        isWarmup: Bool
    ) {
        self.slotID = slotID
        self.setID = setID
        self.blockID = blockID
        self.exerciseID = exerciseID
        self.workTargets = workTargets
        self.loadKg = loadKg
        self.loadUnit = loadUnit
        self.loadDisplayValue = loadDisplayValue
        self.stimuli = stimuli
        self.postRestSec = postRestSec
        self.isWarmup = isWarmup
    }

    public init(slot: PrimitiveSlot, setID: PrimitiveSetID, blockID: BlockID) {
        let resolved = Self.resolve(load: slot.load)
        self.init(
            slotID: slot.id,
            setID: setID,
            blockID: blockID,
            exerciseID: slot.exerciseID,
            workTargets: slot.workTargets,
            loadKg: resolved.loadKg,
            loadUnit: resolved.unit,
            loadDisplayValue: slot.load?.value,
            stimuli: slot.stimuli,
            postRestSec: slot.postRestSec,
            isWarmup: slot.isWarmup
        )
    }

    private static func resolve(load: PrimitiveLoad?) -> (loadKg: Double?, unit: WeightUnit?) {
        guard let load, let value = load.value else { return (nil, nil) }
        switch (load.unit, load.unitType) {
        case (.kg, .absolute):
            return (value, .kg)
        case (.lb, .absolute):
            return (value * 0.45359237, .lb)
        default:
            return (nil, nil)
        }
    }
}

public struct PrimitiveLogCoordinate: Equatable, Sendable {
    public var role: PrimitiveLogRole
    public var slotID: PrimitiveSlotID?
    public var setID: PrimitiveSetID?
    public var blockID: BlockID?
    public var blockRepeatIndex: Int
    public var setRepeatIndex: Int
    public var setIndex: Int

    public init(
        role: PrimitiveLogRole,
        slotID: PrimitiveSlotID? = nil,
        setID: PrimitiveSetID? = nil,
        blockID: BlockID? = nil,
        blockRepeatIndex: Int = 0,
        setRepeatIndex: Int = 0,
        setIndex: Int = 0
    ) {
        self.role = role
        self.slotID = slotID
        self.setID = setID
        self.blockID = blockID
        self.blockRepeatIndex = blockRepeatIndex
        self.setRepeatIndex = setRepeatIndex
        self.setIndex = setIndex
    }

    public var deterministicLogID: SetLogID {
        let seed: String
        switch role {
        case .slot:
            let scope = slotID ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            seed = [
                scope.wireID,
                role.rawValue,
                String(blockRepeatIndex),
                String(setRepeatIndex),
                String(setIndex),
            ].joined(separator: ":")
        case .setResult:
            let scope = setID ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            seed = [
                scope.wireID,
                role.rawValue,
                String(blockRepeatIndex),
                String(setRepeatIndex),
            ].joined(separator: ":")
        case .blockResult:
            let scope = blockID ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            seed = [
                scope.wireID,
                role.rawValue,
                String(blockRepeatIndex),
            ].joined(separator: ":")
        }
        return UUID.deterministicPrimitiveID(seed)
    }
}

public extension ExecutionSlot {
    func slotLog(
        workoutID: WorkoutID,
        blockRepeatIndex: Int,
        setRepeatIndex: Int,
        setIndex: Int,
        reps: Int?,
        rir: Int?,
        completedAt: Date
    ) -> PrimitiveSetLog {
        let coordinate = PrimitiveLogCoordinate(
            role: .slot,
            slotID: slotID,
            setID: setID,
            blockID: blockID,
            blockRepeatIndex: blockRepeatIndex,
            setRepeatIndex: setRepeatIndex,
            setIndex: setIndex
        )
        return PrimitiveSetLog(
            id: coordinate.deterministicLogID,
            role: .slot,
            slotID: slotID,
            setID: setID,
            blockID: blockID,
            workoutID: workoutID,
            plannedExerciseID: exerciseID,
            setIndex: setIndex,
            setRepeatIndex: setRepeatIndex,
            blockRepeatIndex: blockRepeatIndex,
            reps: reps,
            weight: loadKg,
            weightUnit: loadUnit,
            rir: rir,
            isWarmup: isWarmup,
            completedAt: completedAt
        )
    }
}

private extension UUID {
    static func deterministicPrimitiveID(_ seed: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        for index in 0..<16 {
            let shift = UInt64((index % 8) * 8)
            bytes[index] = UInt8((hash >> shift) & 0xff)
            hash = (hash ^ UInt64(index + 1)) &* 0x100000001b3
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
