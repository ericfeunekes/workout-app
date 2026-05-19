import Foundation
import CoreSession
import CoreDomain
import WorkoutCoreFoundation

func runPrimitiveCompositionGeneratorTests() {
    runCase("primitive composition generator accepts broad valid randomized matrix") {
        let generator = PrimitiveCompositionGenerator(seed: 0x5345_544D_4152_4B31)
        let cases = generator.validCases(count: 96)
        var coveredTimingModes: Set<PrimitiveTimingMode> = []
        var coveredTraversals: Set<PrimitiveTraversal> = []
        var coveredMetrics: Set<PrimitiveMetric> = []
        var coveredLoadUnits: Set<PrimitiveLoadUnit> = []
        var coveredStimuli: Set<PrimitiveStimulusType> = []

        for generated in cases {
            let plan = try ExecutionPlan.validated(workout: generated.workout)

            try expectEqual(
                plan.blocks.count,
                generated.workout.blocks.count,
                "\(generated.name): block count preserved"
            )
            try expect(
                !plan.blocks.flatMap(\.sets).flatMap(\.slots).isEmpty,
                "\(generated.name): generated accepted workout must execute at least one slot"
            )

            var logIDs: Set<SetLogID> = []
            for block in plan.blocks {
                coveredMetrics.formUnion(block.observationTargets.map(\.metric))

                for set in block.sets {
                    coveredTimingModes.insert(set.timing.mode)
                    coveredTraversals.insert(set.traversal)
                    coveredMetrics.formUnion(set.workTargets.map(\.metric))

                    try expectEqual(
                        set.allowsVisibleSetProgressTotal,
                        set.traversal != .amrap && set.timing.mode != .timeBounded,
                        "\(generated.name): visible progress policy"
                    )
                    try expectEqual(
                        set.aggregateResultMetric,
                        generated.expectedAggregateMetric(for: set),
                        "\(generated.name): aggregate result metric"
                    )

                    for slot in set.slots {
                        coveredMetrics.formUnion(slot.workTargets.map(\.metric))
                        coveredStimuli.formUnion(slot.stimuli.map(\.type))
                        if let source = generated.slotSource(for: slot.slotID),
                           let load = source.load {
                            coveredLoadUnits.insert(load.unit)
                        }

                        try expect(
                            slot.completionTargets.count <= 1,
                            "\(generated.name): generated slot has at most one completion target"
                        )
                        try expectEqual(
                            slot.resultInputContract?.metric,
                            generated.expectedResultMetric(for: slot),
                            "\(generated.name): slot result input metric"
                        )
                        try expectEqual(
                            slot.primaryDisplayTarget,
                            slot.completionTargets.first ?? slot.observationTargets.first,
                            "\(generated.name): primary display target"
                        )

                        for blockRepeatIndex in 0..<max(block.blockRepeat, 1) {
                            for setRepeatIndex in 0..<max(set.setRepeat, 1) {
                                for setIndex in 0..<set.slots.count {
                                    let logID = slot.slotLog(
                                        workoutID: plan.workoutID,
                                        blockRepeatIndex: blockRepeatIndex,
                                        setRepeatIndex: setRepeatIndex,
                                        setIndex: setIndex,
                                        reps: 1,
                                        rir: nil,
                                        completedAt: generated.completedAt
                                    ).id
                                    try expect(
                                        logIDs.insert(logID).inserted,
                                        "\(generated.name): duplicate slot log id \(logID)"
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        try expectEqual(coveredTimingModes, Set(PrimitiveTimingMode.allCases), "timing mode coverage")
        try expectEqual(coveredTraversals, Set(PrimitiveTraversal.allCases), "traversal coverage")
        try expect(coveredMetrics.isSuperset(of: Set(PrimitiveMetric.allCases)), "metric coverage")
        try expect(
            coveredLoadUnits.isSuperset(of: Set(PrimitiveLoadUnit.allCases)),
            "load unit coverage"
        )
        try expectEqual(coveredStimuli, Set(PrimitiveStimulusType.allCases), "stimulus coverage")
    }

    runCase("primitive composition generator rejects invalid randomized matrix with expected causes") {
        let generator = PrimitiveCompositionGenerator(seed: 0x5345_544D_4152_4B32)
        let cases = generator.invalidCases(count: 72)
        var coveredReasons: Set<InvalidPrimitiveReason> = []

        for generated in cases {
            coveredReasons.insert(generated.reason)
            do {
                _ = try ExecutionPlan.validated(workout: generated.workout)
                try expect(false, "\(generated.name): expected rejection for \(generated.reason)")
            } catch let error as PrimitiveSemanticError {
                try expectEqual(error, generated.expectedError, "\(generated.name): rejection cause")
            }
        }

        try expectEqual(
            coveredReasons,
            Set(InvalidPrimitiveReason.allCases),
            "invalid reason coverage"
        )
    }
}

private struct PrimitiveCompositionGenerator {
    private var random: DeterministicRandom

    init(seed: UInt64) {
        self.random = DeterministicRandom(seed: seed)
    }

    func validCases(count: Int) -> [GeneratedPrimitiveCase] {
        var generator = self
        return (0..<count).map { index in
            generator.makeValidCase(index: index)
        }
    }

    func invalidCases(count: Int) -> [GeneratedInvalidPrimitiveCase] {
        var generator = self
        return (0..<count).map { index in
            generator.makeInvalidCase(index: index)
        }
    }

    private mutating func makeValidCase(index: Int) -> GeneratedPrimitiveCase {
        let blockCount = random.int(in: 1...3)
        var blocks: [PrimitiveBlock] = []
        var sourceSlots: [PrimitiveSlotID: PrimitiveSlot] = [:]

        for blockIndex in 0..<blockCount {
            let setCount = random.int(in: 1...3)
            var sets: [PrimitiveSet] = []
            for setIndex in 0..<setCount {
                let comboIndex = index + blockIndex + setIndex
                let combo = validCombo(comboIndex)
                let slotCount = random.int(in: 1...4)
                let slots = (0..<slotCount).map { slotIndex in
                    makeSlot(
                        caseIndex: index,
                        blockIndex: blockIndex,
                        setIndex: setIndex,
                        slotIndex: slotIndex
                    )
                }
                for slot in slots {
                    sourceSlots[slot.id] = slot
                }
                sets.append(
                    PrimitiveSet(
                        id: generatedUUID(kind: 3, caseIndex: index, blockIndex: blockIndex, setIndex: setIndex),
                        timing: combo.timing,
                        traversal: combo.traversal,
                        repeatCount: random.int(in: 1...3),
                        workTargets: combo.setTargets,
                        slots: slots
                    )
                )
            }
            let blockTargets = random.bool()
                ? [PrimitiveWorkTarget(metric: .duration, valueForm: .open, role: .observation)]
                : []
            blocks.append(
                PrimitiveBlock(
                    id: generatedUUID(kind: 2, caseIndex: index, blockIndex: blockIndex),
                    repeatCount: random.int(in: 1...2),
                    workTargets: blockTargets,
                    sets: sets
                )
            )
        }

        let workout = PrimitiveWorkout(
            id: generatedUUID(kind: 1, caseIndex: index),
            name: "Generated primitive composition \(index)",
            blocks: blocks
        )
        return GeneratedPrimitiveCase(
            name: "generated-valid-\(index)",
            workout: workout,
            sourceSlots: sourceSlots
        )
    }

    private mutating func makeInvalidCase(index: Int) -> GeneratedInvalidPrimitiveCase {
        let reason = InvalidPrimitiveReason.allCases[index % InvalidPrimitiveReason.allCases.count]
        let setID = generatedUUID(kind: 3, caseIndex: index, blockIndex: 0, setIndex: 0)
        let blockID = generatedUUID(kind: 2, caseIndex: index, blockIndex: 0)
        let workoutID = generatedUUID(kind: 1, caseIndex: index)

        let validSlot = makeSlot(caseIndex: index, blockIndex: 0, setIndex: 0, slotIndex: 0)
        let workout: PrimitiveWorkout
        let expectedError: PrimitiveSemanticError
        switch reason {
        case .emptyWorkout:
            workout = PrimitiveWorkout(id: workoutID, name: "invalid", blocks: [])
            expectedError = .invalidTiming(setID: workoutID)
        case .emptyBlock:
            workout = PrimitiveWorkout(
                id: workoutID,
                name: "invalid",
                blocks: [PrimitiveBlock(id: blockID, sets: [])]
            )
            expectedError = .invalidTiming(setID: workoutID)
        case .emptySet:
            workout = PrimitiveWorkout(
                id: workoutID,
                name: "invalid",
                blocks: [
                    PrimitiveBlock(id: blockID, sets: [
                        PrimitiveSet(id: setID, timing: PrimitiveTiming(mode: .setBounded), slots: []),
                    ]),
                ]
            )
            expectedError = .invalidTiming(setID: workoutID)
        case .amrapSetBounded:
            workout = workoutWith(
                workoutID: workoutID,
                blockID: blockID,
                set: PrimitiveSet(
                    id: setID,
                    timing: PrimitiveTiming(mode: .setBounded),
                    traversal: .amrap,
                    slots: [validSlot]
                )
            )
            expectedError = .illegalRuntimeCell(setID: setID)
        case .amrapTargetBounded:
            workout = workoutWith(
                workoutID: workoutID,
                blockID: blockID,
                set: PrimitiveSet(
                    id: setID,
                    timing: PrimitiveTiming(mode: .targetBounded),
                    traversal: .amrap,
                    workTargets: [
                        PrimitiveWorkTarget(metric: .reps, valueForm: .single, value: 30, role: .completion),
                    ],
                    slots: [validSlot]
                )
            )
            expectedError = .illegalRuntimeCell(setID: setID)
        case .timeMissingInterval:
            workout = workoutWith(
                workoutID: workoutID,
                blockID: blockID,
                set: PrimitiveSet(
                    id: setID,
                    timing: PrimitiveTiming(mode: .timeBounded, rounds: 4),
                    slots: [validSlot]
                )
            )
            expectedError = .invalidTiming(setID: setID)
        case .timeMissingRounds:
            workout = workoutWith(
                workoutID: workoutID,
                blockID: blockID,
                set: PrimitiveSet(
                    id: setID,
                    timing: PrimitiveTiming(mode: .timeBounded, intervalSec: 60),
                    slots: [validSlot]
                )
            )
            expectedError = .invalidTiming(setID: setID)
        case .capMissingCap:
            workout = workoutWith(
                workoutID: workoutID,
                blockID: blockID,
                set: PrimitiveSet(id: setID, timing: PrimitiveTiming(mode: .capBounded), slots: [validSlot])
            )
            expectedError = .invalidTiming(setID: setID)
        case .capAmrapMissingRoundsObservation:
            workout = workoutWith(
                workoutID: workoutID,
                blockID: blockID,
                set: PrimitiveSet(
                    id: setID,
                    timing: PrimitiveTiming(mode: .capBounded, capSec: 600),
                    traversal: .amrap,
                    workTargets: [
                        PrimitiveWorkTarget(metric: .duration, valueForm: .open, role: .observation),
                    ],
                    slots: [validSlot]
                )
            )
            expectedError = .invalidTiming(setID: setID)
        case .capNonAmrapMissingDurationObservation:
            workout = workoutWith(
                workoutID: workoutID,
                blockID: blockID,
                set: PrimitiveSet(
                    id: setID,
                    timing: PrimitiveTiming(mode: .capBounded, capSec: 600),
                    traversal: .roundRobin,
                    workTargets: [
                        PrimitiveWorkTarget(metric: .rounds, valueForm: .open, role: .observation),
                    ],
                    slots: [validSlot]
                )
            )
            expectedError = .invalidTiming(setID: setID)
        case .ambiguousSlotCompletion:
            var ambiguous = validSlot
            ambiguous.workTargets = [
                PrimitiveWorkTarget(metric: .reps, valueForm: .single, value: 10, role: .completion),
                PrimitiveWorkTarget(metric: .duration, valueForm: .single, value: 45, role: .completion),
            ]
            workout = workoutWith(
                workoutID: workoutID,
                blockID: blockID,
                set: PrimitiveSet(id: setID, timing: PrimitiveTiming(mode: .setBounded), slots: [ambiguous])
            )
            expectedError = .invalidTiming(setID: setID)
        }

        return GeneratedInvalidPrimitiveCase(
            name: "generated-invalid-\(reason.rawValue)-\(index)",
            reason: reason,
            workout: workout,
            expectedError: expectedError
        )
    }

    private func validCombo(
        _ index: Int
    ) -> (timing: PrimitiveTiming, traversal: PrimitiveTraversal, setTargets: [PrimitiveWorkTarget]) {
        let combos: [(PrimitiveTiming, PrimitiveTraversal, [PrimitiveWorkTarget])] = [
            (.init(mode: .setBounded), .sequential, []),
            (.init(mode: .setBounded), .roundRobin, []),
            (.init(mode: .timeBounded, intervalSec: 45, rounds: 6), .sequential, []),
            (.init(mode: .timeBounded, intervalSec: 60, rounds: 4), .roundRobin, []),
            (.init(mode: .timeBounded, intervalSec: 60, rounds: 5), .amrap, [
                PrimitiveWorkTarget(metric: .rounds, valueForm: .open, role: .observation),
            ]),
            (.init(mode: .capBounded, capSec: 900), .sequential, [
                PrimitiveWorkTarget(metric: .duration, valueForm: .open, role: .observation),
            ]),
            (.init(mode: .capBounded, capSec: 1_200), .roundRobin, [
                PrimitiveWorkTarget(metric: .duration, valueForm: .open, role: .observation),
            ]),
            (.init(mode: .capBounded, capSec: 1_200), .amrap, [
                PrimitiveWorkTarget(metric: .rounds, valueForm: .open, role: .observation),
            ]),
            (.init(mode: .targetBounded), .sequential, [
                PrimitiveWorkTarget(metric: .reps, valueForm: .single, value: 100, role: .completion),
            ]),
            (.init(mode: .targetBounded), .roundRobin, [
                PrimitiveWorkTarget(metric: .distance, valueForm: .single, value: 1_000, role: .completion),
            ]),
        ]
        return combos[index % combos.count]
    }

    private mutating func makeSlot(
        caseIndex: Int,
        blockIndex: Int,
        setIndex: Int,
        slotIndex: Int
    ) -> PrimitiveSlot {
        let metric = PrimitiveMetric.allCases[(caseIndex + blockIndex + setIndex + slotIndex) % PrimitiveMetric.allCases.count]
        let completionMetric = metric == .rounds ? PrimitiveMetric.reps : metric
        let observationMetric = PrimitiveMetric.allCases[
            (caseIndex + blockIndex + setIndex + slotIndex + 2) % PrimitiveMetric.allCases.count
        ]
        let targets = [
            PrimitiveWorkTarget(
                metric: completionMetric,
                valueForm: completionMetric == .completion ? .open : .single,
                value: completionMetric == .completion ? nil : Double(5 + random.int(in: 0...80)),
                role: .completion
            ),
            PrimitiveWorkTarget(
                metric: observationMetric,
                valueForm: .open,
                role: .observation
            ),
        ]
        let load = makeLoad(index: caseIndex + blockIndex + setIndex + slotIndex)
        let stimulus = PrimitiveStimulusType.allCases[
            (caseIndex + blockIndex + setIndex + slotIndex) % PrimitiveStimulusType.allCases.count
        ]
        return PrimitiveSlot(
            id: generatedUUID(
                kind: 4,
                caseIndex: caseIndex,
                blockIndex: blockIndex,
                setIndex: setIndex,
                slotIndex: slotIndex
            ),
            exerciseID: generatedUUID(kind: 5, caseIndex: caseIndex, slotIndex: slotIndex),
            workTargets: targets,
            load: load,
            stimuli: [PrimitiveStimulus(type: stimulus, target: stimulus == .rir ? 2 : 3)],
            postRestSec: random.bool() ? random.int(in: 15...120) : 0,
            isWarmup: random.bool()
        )
    }

    private func makeLoad(index: Int) -> PrimitiveLoad? {
        switch index % 5 {
        case 0:
            return PrimitiveLoad(value: 60, unit: .kg, unitType: .absolute)
        case 1:
            return PrimitiveLoad(value: 135, unit: .lb, unitType: .absolute)
        case 2:
            return PrimitiveLoad(value: 0.8, unit: .oneRepMax, unitType: .relative)
        case 3:
            return PrimitiveLoad(unit: .bodyweight, unitType: .implicitBodyweight)
        default:
            return nil
        }
    }
}

private struct GeneratedPrimitiveCase {
    var name: String
    var workout: PrimitiveWorkout
    var sourceSlots: [PrimitiveSlotID: PrimitiveSlot]
    var completedAt = Date(timeIntervalSince1970: 1_700_000_000)

    func slotSource(for slotID: PrimitiveSlotID) -> PrimitiveSlot? {
        sourceSlots[slotID]
    }

    func expectedAggregateMetric(for set: ExecutionSet) -> PrimitiveResultMetric? {
        if set.workTargets.contains(where: { $0.metric == .rounds && $0.role == .observation }) {
            return .rounds
        }
        if set.workTargets.contains(where: { $0.metric == .duration && $0.role == .observation }) {
            return .duration
        }
        if set.workTargets.contains(where: { $0.metric == .distance && $0.role == .observation }) {
            return .distance
        }
        if set.workTargets.contains(where: { $0.metric == .loadCarried && $0.role == .observation }) {
            return .loadCarried
        }
        return nil
    }

    func expectedResultMetric(for slot: ExecutionSlot) -> PrimitiveResultMetric? {
        guard let completion = slot.completionTargets.first else { return nil }
        switch completion.metric {
        case .reps:
            return .reps
        case .duration:
            return .duration
        case .distance:
            return .distance
        case .loadCarried:
            return .loadCarried
        case .completion:
            return .completion
        case .rounds:
            return nil
        }
    }
}

private struct GeneratedInvalidPrimitiveCase {
    var name: String
    var reason: InvalidPrimitiveReason
    var workout: PrimitiveWorkout
    var expectedError: PrimitiveSemanticError
}

private enum InvalidPrimitiveReason: String, CaseIterable, Hashable {
    case emptyWorkout
    case emptyBlock
    case emptySet
    case amrapSetBounded
    case amrapTargetBounded
    case timeMissingInterval
    case timeMissingRounds
    case capMissingCap
    case capAmrapMissingRoundsObservation
    case capNonAmrapMissingDurationObservation
    case ambiguousSlotCompletion
}

private struct DeterministicRandom {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        let width = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % width)
    }

    mutating func bool() -> Bool {
        next().isMultiple(of: 2)
    }
}

private func workoutWith(
    workoutID: WorkoutID,
    blockID: BlockID,
    set: PrimitiveSet
) -> PrimitiveWorkout {
    PrimitiveWorkout(
        id: workoutID,
        name: "invalid",
        blocks: [PrimitiveBlock(id: blockID, sets: [set])]
    )
}

private func generatedUUID(
    kind: Int,
    caseIndex: Int,
    blockIndex: Int = 0,
    setIndex: Int = 0,
    slotIndex: Int = 0
) -> UUID {
    let suffix = kind * 1_000_000 + caseIndex * 1_000 + blockIndex * 100 + setIndex * 10 + slotIndex
    return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", suffix))!
}
