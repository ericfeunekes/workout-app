import Foundation
import CoreDomain
import CoreSession
import WorkoutCoreFoundation

public enum PrimitiveExportAmbiguity: String, Sendable, Hashable, Codable, CaseIterable {
    case missingSportSequence
    case multipleCompatibleIntervalInterpretations
    case resultOverlayNotRepresentedInPrimitives
    case missingSourceFact
    case standaloneRestHasNoWorkoutShape
}

public enum PrimitiveExportFact: String, Sendable, Hashable, Codable, CaseIterable {
    case workoutIdentity
    case blockOrder
    case blockRepeatCount
    case setOrder
    case setTiming
    case setTraversal
    case setRepeatCount
    case slotOrder
    case slotExercise
    case workTarget
    case load
    case rirStimulus
    case rest
    case warmup
}

public struct PrimitiveExportFacts: Sendable, Hashable, Codable {
    public var workoutID: WorkoutID
    public var workoutName: String
    public var activityIntent: ActivityIntent?
    public var blocks: [PrimitiveExportBlock]
    public var axes: PrimitiveAxisSummary
    public var ambiguities: Set<PrimitiveExportAmbiguity>

    public init(
        workoutID: WorkoutID,
        workoutName: String,
        activityIntent: ActivityIntent? = nil,
        blocks: [PrimitiveExportBlock],
        axes: PrimitiveAxisSummary,
        ambiguities: Set<PrimitiveExportAmbiguity> = []
    ) {
        self.workoutID = workoutID
        self.workoutName = workoutName
        self.activityIntent = activityIntent
        self.blocks = blocks
        self.axes = axes
        self.ambiguities = ambiguities
    }
}

public struct PrimitiveExportBlock: Sendable, Hashable, Codable {
    public var id: BlockID
    public var order: Int
    public var title: String?
    public var repeatCount: Int
    public var workTargets: [PrimitiveWorkTarget]
    public var sets: [PrimitiveExportSet]

    public init(
        id: BlockID,
        order: Int,
        title: String?,
        repeatCount: Int,
        workTargets: [PrimitiveWorkTarget],
        sets: [PrimitiveExportSet]
    ) {
        self.id = id
        self.order = order
        self.title = title
        self.repeatCount = repeatCount
        self.workTargets = workTargets
        self.sets = sets
    }
}

public struct PrimitiveExportSet: Sendable, Hashable, Codable {
    public var id: PrimitiveSetID
    public var blockID: BlockID
    public var order: Int
    public var title: String?
    public var timing: PrimitiveTiming
    public var traversal: PrimitiveTraversal
    public var repeatCount: Int
    public var workTargets: [PrimitiveWorkTarget]
    public var slots: [PrimitiveExportSlot]

    public init(
        id: PrimitiveSetID,
        blockID: BlockID,
        order: Int,
        title: String?,
        timing: PrimitiveTiming,
        traversal: PrimitiveTraversal,
        repeatCount: Int,
        workTargets: [PrimitiveWorkTarget],
        slots: [PrimitiveExportSlot]
    ) {
        self.id = id
        self.blockID = blockID
        self.order = order
        self.title = title
        self.timing = timing
        self.traversal = traversal
        self.repeatCount = repeatCount
        self.workTargets = workTargets
        self.slots = slots
    }
}

public struct PrimitiveExportSlot: Sendable, Hashable, Codable {
    public var id: PrimitiveSlotID
    public var setID: PrimitiveSetID
    public var order: Int
    public var exerciseID: ExerciseID
    public var workTargets: [PrimitiveWorkTarget]
    public var load: PrimitiveLoad?
    public var stimuli: [PrimitiveStimulus]
    public var postRestSec: Int
    public var isWarmup: Bool

    public init(
        id: PrimitiveSlotID,
        setID: PrimitiveSetID,
        order: Int,
        exerciseID: ExerciseID,
        workTargets: [PrimitiveWorkTarget],
        load: PrimitiveLoad?,
        stimuli: [PrimitiveStimulus],
        postRestSec: Int,
        isWarmup: Bool
    ) {
        self.id = id
        self.setID = setID
        self.order = order
        self.exerciseID = exerciseID
        self.workTargets = workTargets
        self.load = load
        self.stimuli = stimuli
        self.postRestSec = postRestSec
        self.isWarmup = isWarmup
    }
}

public struct PrimitiveAxisSummary: Sendable, Hashable, Codable {
    public var setTimings: Set<PrimitiveTimingMode>
    public var traversals: Set<PrimitiveTraversal>
    public var repeatCount: Int
    public var metrics: Set<PrimitiveMetric>
    public var targetScopes: Set<PrimitiveTargetScope>
    public var hasLoad: Bool
    public var hasRir: Bool
    public var hasRest: Bool
    public var hasWarmup: Bool
    public var slotCount: Int
    public var setCount: Int
    public var blockCount: Int
    public var slotsWithLoadAndDistance: Int
    public var slotsWithLoadAndDuration: Int

    public init(
        setTimings: Set<PrimitiveTimingMode>,
        traversals: Set<PrimitiveTraversal>,
        repeatCount: Int,
        metrics: Set<PrimitiveMetric>,
        targetScopes: Set<PrimitiveTargetScope>,
        hasLoad: Bool,
        hasRir: Bool,
        hasRest: Bool,
        hasWarmup: Bool,
        slotCount: Int,
        setCount: Int,
        blockCount: Int,
        slotsWithLoadAndDistance: Int,
        slotsWithLoadAndDuration: Int
    ) {
        self.setTimings = setTimings
        self.traversals = traversals
        self.repeatCount = repeatCount
        self.metrics = metrics
        self.targetScopes = targetScopes
        self.hasLoad = hasLoad
        self.hasRir = hasRir
        self.hasRest = hasRest
        self.hasWarmup = hasWarmup
        self.slotCount = slotCount
        self.setCount = setCount
        self.blockCount = blockCount
        self.slotsWithLoadAndDistance = slotsWithLoadAndDistance
        self.slotsWithLoadAndDuration = slotsWithLoadAndDuration
    }
}

public enum PrimitiveTargetScope: String, Sendable, Hashable, Codable, CaseIterable {
    case block
    case set
    case slot
}

public enum PrimitiveExportProfileBuilder {
    public static func build(workout: PrimitiveWorkout) throws -> PrimitiveExportFacts {
        try PrimitiveSemantics.validate(workout)
        let blocks = workout.blocks.enumerated().map { blockOffset, block in
            PrimitiveExportBlock(
                id: block.id,
                order: blockOffset,
                title: block.title,
                repeatCount: block.repeatCount,
                workTargets: block.workTargets,
                sets: block.sets.enumerated().map { setOffset, set in
                    PrimitiveExportSet(
                        id: set.id,
                        blockID: block.id,
                        order: setOffset,
                        title: set.title,
                        timing: set.timing,
                        traversal: set.traversal,
                        repeatCount: set.repeatCount,
                        workTargets: set.workTargets,
                        slots: set.slots.enumerated().map { slotOffset, slot in
                            PrimitiveExportSlot(
                                id: slot.id,
                                setID: set.id,
                                order: slotOffset,
                                exerciseID: slot.exerciseID,
                                workTargets: slot.workTargets,
                                load: slot.load,
                                stimuli: slot.stimuli,
                                postRestSec: slot.postRestSec,
                                isWarmup: slot.isWarmup
                            )
                        }
                    )
                }
            )
        }
        let axes = PrimitiveAxisSummary(blocks: blocks)
        return PrimitiveExportFacts(
            workoutID: workout.id,
            workoutName: workout.name,
            activityIntent: workout.activityIntent,
            blocks: blocks,
            axes: axes,
            ambiguities: ambiguities(for: axes, activityIntent: workout.activityIntent)
        )
    }

    private static func ambiguities(
        for axes: PrimitiveAxisSummary,
        activityIntent: ActivityIntent?
    ) -> Set<PrimitiveExportAmbiguity> {
        var ambiguities: Set<PrimitiveExportAmbiguity> = []
        if axes.traversals.contains(.amrap), axes.metrics.contains(.rounds) {
            ambiguities.insert(.resultOverlayNotRepresentedInPrimitives)
        }
        if axes.traversals.contains(.roundRobin),
           axes.setTimings.contains(.timeBounded),
           axes.metrics.contains(.reps)
        {
            ambiguities.insert(.multipleCompatibleIntervalInterpretations)
        }
        if activityIntent == nil && sourceDependent(axes: axes) {
            ambiguities.insert(.missingSourceFact)
        }
        return ambiguities
    }

    private static func sourceDependent(axes: PrimitiveAxisSummary) -> Bool {
        if axes.metrics.contains(.distance), !axes.metrics.contains(.loadCarried) {
            return true
        }
        if axes.metrics.contains(.duration),
           !axes.hasLoad,
           !axes.hasRest,
           !axes.setTimings.contains(.timeBounded)
        {
            return true
        }
        if axes.setTimings.contains(.timeBounded), axes.hasRest, !axes.hasLoad {
            return true
        }
        return false
    }
}

private extension PrimitiveAxisSummary {
    init(blocks: [PrimitiveExportBlock]) {
        let sets = blocks.flatMap(\.sets)
        let slots = sets.flatMap(\.slots)
        let blockTargets = blocks.flatMap(\.workTargets)
        let setTargets = sets.flatMap(\.workTargets)
        let slotTargets = slots.flatMap(\.workTargets)
        let allTargets = blockTargets + setTargets + slotTargets
        let stimuli = slots.flatMap(\.stimuli)
        let scopes = [
            blockTargets.isEmpty ? nil : PrimitiveTargetScope.block,
            setTargets.isEmpty ? nil : PrimitiveTargetScope.set,
            slotTargets.isEmpty ? nil : PrimitiveTargetScope.slot,
        ].compactMap { $0 }

        self.init(
            setTimings: Set(sets.map(\.timing.mode)),
            traversals: Set(sets.map(\.traversal)),
            repeatCount: max(blocks.map(\.repeatCount).max() ?? 1, sets.map(\.repeatCount).max() ?? 1),
            metrics: Set(allTargets.map(\.metric)),
            targetScopes: Set(scopes),
            hasLoad: slots.contains { $0.load != nil },
            hasRir: stimuli.contains { $0.type == .rir },
            hasRest: slots.contains { $0.postRestSec > 0 },
            hasWarmup: slots.contains { $0.isWarmup },
            slotCount: slots.count,
            setCount: sets.count,
            blockCount: blocks.count,
            slotsWithLoadAndDistance: slots.filter { slot in
                slot.load != nil && slot.workTargets.contains { $0.metric == .distance }
            }.count,
            slotsWithLoadAndDuration: slots.filter { slot in
                slot.load != nil && slot.workTargets.contains { $0.metric == .duration }
            }.count
        )
    }
}
