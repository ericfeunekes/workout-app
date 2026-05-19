// main.swift — entry point for `swift run CoreSessionTests`.
//
// Covers every mutation in SessionMutation against the rules in
// app/README.md § "Autoregulation"/"Tap-to-edit"/"Swap"/"Persistence"
// and docs/prescription.md § "Autoregulation · Edits don't retrigger".

import Foundation
import CoreSession
import CoreDomain
import CoreAutoreg
import CorePrescription
import WorkoutCoreFoundation

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

let itemA = UUID()
let itemB = UUID()
let workoutID = UUID()
let exerciseAlt = UUID()

/// Fixed stamp for reducer `logSet` calls in tests. Most cases don't care
/// about the timestamp; those that do override inline. Hard-coded (not
/// `Date()`) so repeated runs produce identical state snapshots.
let logSetStamp = Date(timeIntervalSince1970: 1_700_000_000)

runCase("primitive ExecutionPlan seeds strength set without legacy timing mode") {
    let workoutID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    let blockID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
    let setID = UUID(uuidString: "30000000-0000-4000-8000-000000000001")!
    let slotID = UUID(uuidString: "40000000-0000-4000-8000-000000000001")!
    let exerciseID = UUID(uuidString: "50000000-0000-4000-8000-000000000001")!
    let workout = PrimitiveWorkout(
        id: workoutID,
        name: "Primitive strength",
        blocks: [
            PrimitiveBlock(id: blockID, sets: [
                PrimitiveSet(
                    id: setID,
                    timing: PrimitiveTiming(mode: .setBounded),
                    repeatCount: 3,
                    slots: [
                        PrimitiveSlot(
                            id: slotID,
                            exerciseID: exerciseID,
                            workTargets: [
                                PrimitiveWorkTarget(metric: .reps, valueForm: .single, value: 5, role: .completion),
                            ],
                            load: PrimitiveLoad(value: 100, unit: .kg, unitType: .absolute),
                            stimuli: [PrimitiveStimulus(type: .rir, target: 2)]
                        ),
                    ]
                ),
            ]),
        ]
    )
    let plan = ExecutionPlan(workout: workout)
    try expectEqual(plan.workoutID, workoutID)
    try expectEqual(plan.blocks[0].sets[0].setRepeat, 3)
    try expectEqual(plan.blocks[0].sets[0].slots[0].slotID, slotID)
    try expectEqual(plan.blocks[0].sets[0].slots[0].loadKg, 100)
}

runCase("primitive log coordinate creates stable role-scoped ids") {
    let slotID = UUID(uuidString: "40000000-0000-4000-8000-000000000001")!
    let setID = UUID(uuidString: "30000000-0000-4000-8000-000000000001")!
    let blockID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
    let a = PrimitiveLogCoordinate(
        role: .slot,
        slotID: slotID,
        setID: setID,
        blockID: blockID,
        blockRepeatIndex: 0,
        setRepeatIndex: 1,
        setIndex: 0
    ).deterministicLogID
    let b = PrimitiveLogCoordinate(
        role: .slot,
        slotID: slotID,
        setID: setID,
        blockID: blockID,
        blockRepeatIndex: 0,
        setRepeatIndex: 1,
        setIndex: 0
    ).deterministicLogID
    let c = PrimitiveLogCoordinate(
        role: .slot,
        slotID: slotID,
        setID: setID,
        blockID: blockID,
        blockRepeatIndex: 0,
        setRepeatIndex: 2,
        setIndex: 0
    ).deterministicLogID
    try expectEqual(a, b)
    try expect(a != c, "repeat index must produce a distinct primitive log id")

    let setResultA = PrimitiveLogCoordinate(
        role: .setResult,
        setID: setID,
        blockID: blockID,
        blockRepeatIndex: 0,
        setRepeatIndex: 1,
        setIndex: 0
    ).deterministicLogID
    let setResultB = PrimitiveLogCoordinate(
        role: .setResult,
        setID: setID,
        blockID: blockID,
        blockRepeatIndex: 0,
        setRepeatIndex: 1,
        setIndex: 99
    ).deterministicLogID
    let blockResultA = PrimitiveLogCoordinate(
        role: .blockResult,
        blockID: blockID,
        blockRepeatIndex: 0,
        setRepeatIndex: 7,
        setIndex: 9
    ).deterministicLogID
    let blockResultB = PrimitiveLogCoordinate(
        role: .blockResult,
        blockID: blockID,
        blockRepeatIndex: 0
    ).deterministicLogID
    try expectEqual(setResultA, setResultB)
    try expectEqual(blockResultA, blockResultB)
    try expect(setResultA != blockResultA, "aggregate roles must remain role-scoped")
}

runCase("primitive result log semantics protect role authority") {
    let completedAt = Date(timeIntervalSince1970: 1_700_000_100)
    let exerciseID = UUID(uuidString: "50000000-0000-4000-8000-000000000101")!
    let performedID = UUID(uuidString: "50000000-0000-4000-8000-000000000102")!
    let slot = PrimitiveSetLog(
        id: UUID(uuidString: "60000000-0000-4000-8000-000000000101")!,
        role: .slot,
        slotID: UUID(uuidString: "40000000-0000-4000-8000-000000000101")!,
        plannedExerciseID: exerciseID,
        performedExerciseID: performedID,
        setIndex: 0,
        reps: 5,
        weight: 100,
        weightUnit: .kg,
        rir: 2,
        completedAt: completedAt
    )
    try expectEqual(slot.resultSemantics.scope, .exercise)
    try expectEqual(slot.resultSemantics.isByExerciseEligible, true)
    try expectEqual(slot.resultSemantics.isAggregate, false)
    try expectEqual(slot.resultSemantics.primaryMetric, .reps)
    try expectEqual(slot.resultSemantics.secondaryMetrics, [.loadCarried])
    try expectEqual(slot.resultSemantics.isSentinel, false)

    let skippedSlot = PrimitiveSetLog(
        id: UUID(uuidString: "60000000-0000-4000-8000-000000000102")!,
        role: .slot,
        slotID: UUID(uuidString: "40000000-0000-4000-8000-000000000102")!,
        plannedExerciseID: exerciseID,
        setIndex: 1,
        skipped: true,
        completedAt: completedAt
    )
    try expectEqual(skippedSlot.resultSemantics.scope, .exercise)
    try expectEqual(skippedSlot.resultSemantics.isByExerciseEligible, false)
    try expectEqual(skippedSlot.resultSemantics.isSentinel, false)
    try expectEqual(skippedSlot.primitiveResultMetrics, [])

    let setAggregate = PrimitiveSetLog(
        id: UUID(uuidString: "60000000-0000-4000-8000-000000000103")!,
        role: .setResult,
        setID: UUID(uuidString: "30000000-0000-4000-8000-000000000103")!,
        blockID: UUID(uuidString: "20000000-0000-4000-8000-000000000103")!,
        setIndex: 0,
        reps: 7,
        rounds: 3,
        completedAt: completedAt
    )
    try expectEqual(setAggregate.resultSemantics.scope, .setAggregate)
    try expectEqual(setAggregate.resultSemantics.isByExerciseEligible, false)
    try expectEqual(setAggregate.resultSemantics.isAggregate, true)
    try expectEqual(setAggregate.resultSemantics.primaryMetric, .rounds)
    try expectEqual(setAggregate.resultSemantics.secondaryMetrics, [.reps])
    try expectEqual(setAggregate.primitiveResultMetrics, [.rounds, .reps])
    try expectEqual(setAggregate.resultSemantics.isSentinel, false)

    let blockSentinel = PrimitiveSetLog(
        id: UUID(uuidString: "60000000-0000-4000-8000-000000000104")!,
        role: .blockResult,
        blockID: UUID(uuidString: "20000000-0000-4000-8000-000000000104")!,
        setIndex: 0,
        completedAt: completedAt
    )
    try expectEqual(blockSentinel.resultSemantics.scope, .blockAggregate)
    try expectEqual(blockSentinel.resultSemantics.isByExerciseEligible, false)
    try expectEqual(blockSentinel.resultSemantics.isAggregate, true)
    try expectEqual(blockSentinel.resultSemantics.primaryMetric, nil)
    try expectEqual(blockSentinel.resultSemantics.isSentinel, true)

    let skippedAggregate = PrimitiveSetLog(
        id: UUID(uuidString: "60000000-0000-4000-8000-000000000105")!,
        role: .blockResult,
        blockID: UUID(uuidString: "20000000-0000-4000-8000-000000000105")!,
        setIndex: 0,
        skipped: true,
        completedAt: completedAt
    )
    try expectEqual(skippedAggregate.resultSemantics.isSentinel, true)
}

runCase("primitive semantics validates shared timing traversal matrix") {
    let exerciseID = UUID(uuidString: "50000000-0000-4000-8000-000000000010")!
    let legal = PrimitiveWorkout(
        id: UUID(uuidString: "10000000-0000-4000-8000-000000000010")!,
        name: "Legal",
        blocks: [
            PrimitiveBlock(id: UUID(uuidString: "20000000-0000-4000-8000-000000000010")!, sets: [
                PrimitiveSet(
                    id: UUID(uuidString: "30000000-0000-4000-8000-000000000010")!,
                    timing: PrimitiveTiming(mode: .capBounded, capSec: 300),
                    traversal: .amrap,
                    workTargets: [
                        PrimitiveWorkTarget(metric: .rounds, valueForm: .open, role: .observation),
                    ],
                    slots: [
                        PrimitiveSlot(
                            id: UUID(uuidString: "40000000-0000-4000-8000-000000000010")!,
                            exerciseID: exerciseID,
                            workTargets: [
                                PrimitiveWorkTarget(metric: .distance, valueForm: .single, value: 1_000, role: .completion),
                            ]
                        ),
                    ]
                ),
            ]),
        ]
    )
    let plan = try ExecutionPlan.validated(workout: legal)
    let set = plan.blocks[0].sets[0]
    try expectEqual(set.allowsVisibleSetProgressTotal, false)
    try expectEqual(set.slots[0].resultInputContract?.metric, .distance)

    let illegal = PrimitiveWorkout(
        id: UUID(uuidString: "10000000-0000-4000-8000-000000000011")!,
        name: "Illegal",
        blocks: [
            PrimitiveBlock(id: UUID(uuidString: "20000000-0000-4000-8000-000000000011")!, sets: [
                PrimitiveSet(
                    id: UUID(uuidString: "30000000-0000-4000-8000-000000000011")!,
                    timing: PrimitiveTiming(mode: .setBounded),
                    traversal: .amrap,
                    slots: [
                        PrimitiveSlot(
                            id: UUID(uuidString: "40000000-0000-4000-8000-000000000011")!,
                            exerciseID: exerciseID,
                            workTargets: []
                        ),
                    ]
                ),
            ]),
        ]
    )
    do {
        _ = try ExecutionPlan.validated(workout: illegal)
        try expect(false, "set_bounded x amrap must reject")
    } catch PrimitiveSemanticError.illegalRuntimeCell(let setID) {
        try expectEqual(setID, UUID(uuidString: "30000000-0000-4000-8000-000000000011")!)
    }
}

runCase("primitive semantics accepts every legal timing traversal cell") {
    let cases: [(PrimitiveTiming, PrimitiveTraversal, [PrimitiveWorkTarget])] = [
        (.init(mode: .setBounded), .sequential, []),
        (.init(mode: .setBounded), .roundRobin, []),
        (.init(mode: .timeBounded, intervalSec: 60, rounds: 3), .sequential, []),
        (.init(mode: .timeBounded, intervalSec: 60, rounds: 3), .roundRobin, []),
        (.init(mode: .timeBounded, intervalSec: 60, rounds: 3), .amrap, [
            .init(metric: .rounds, valueForm: .open, role: .observation),
        ]),
        (.init(mode: .capBounded, capSec: 300), .sequential, [
            .init(metric: .duration, valueForm: .open, role: .observation),
        ]),
        (.init(mode: .capBounded, capSec: 300), .roundRobin, [
            .init(metric: .duration, valueForm: .open, role: .observation),
        ]),
        (.init(mode: .capBounded, capSec: 300), .amrap, [
            .init(metric: .rounds, valueForm: .open, role: .observation),
        ]),
        (.init(mode: .targetBounded), .sequential, [
            .init(metric: .reps, valueForm: .single, value: 100, role: .completion),
        ]),
        (.init(mode: .targetBounded), .roundRobin, [
            .init(metric: .reps, valueForm: .single, value: 100, role: .completion),
        ]),
    ]

    for (index, entry) in cases.enumerated() {
        let workout = primitiveWorkout(
            setID: primitiveUUID(0x3050 + index),
            timing: entry.0,
            traversal: entry.1,
            setTargets: entry.2
        )

        let plan = try ExecutionPlan.validated(workout: workout)

        try expectEqual(plan.blocks[0].sets[0].timing, entry.0, "case \(index)")
        try expectEqual(plan.blocks[0].sets[0].traversal, entry.1, "case \(index)")
    }
}

runCase("primitive semantics maps legacy cursor position across repeated exercise sets") {
    let blockID = UUID(uuidString: "20000000-0000-4000-8000-000000000020")!
    let exerciseID = UUID(uuidString: "50000000-0000-4000-8000-000000000020")!
    let firstSlotID = UUID(uuidString: "40000000-0000-4000-8000-000000000020")!
    let secondSlotID = UUID(uuidString: "40000000-0000-4000-8000-000000000021")!
    let block = ExecutionBlock(
        blockID: blockID,
        blockRepeat: 1,
        workTargets: [],
        sets: [
            ExecutionSet(
                setID: UUID(uuidString: "30000000-0000-4000-8000-000000000020")!,
                blockID: blockID,
                setRepeat: 1,
                timing: PrimitiveTiming(mode: .setBounded),
                traversal: .sequential,
                workTargets: [],
                slots: [
                    ExecutionSlot(
                        slotID: firstSlotID,
                        setID: UUID(uuidString: "30000000-0000-4000-8000-000000000020")!,
                        blockID: blockID,
                        exerciseID: exerciseID,
                        workTargets: [
                            PrimitiveWorkTarget(metric: .reps, valueForm: .single, value: 5, role: .completion),
                        ],
                        loadKg: nil,
                        loadUnit: nil,
                        loadDisplayValue: nil,
                        stimuli: [],
                        postRestSec: 0,
                        isWarmup: false
                    ),
                ]
            ),
            ExecutionSet(
                setID: UUID(uuidString: "30000000-0000-4000-8000-000000000021")!,
                blockID: blockID,
                setRepeat: 1,
                timing: PrimitiveTiming(mode: .setBounded),
                traversal: .sequential,
                workTargets: [],
                slots: [
                    ExecutionSlot(
                        slotID: secondSlotID,
                        setID: UUID(uuidString: "30000000-0000-4000-8000-000000000021")!,
                        blockID: blockID,
                        exerciseID: exerciseID,
                        workTargets: [
                            PrimitiveWorkTarget(metric: .reps, valueForm: .single, value: 8, role: .completion),
                        ],
                        loadKg: nil,
                        loadUnit: nil,
                        loadDisplayValue: nil,
                        stimuli: [],
                        postRestSec: 0,
                        isWarmup: false
                    ),
                ]
            ),
        ]
    )

    guard let second = block.slotForLegacyCursor(
        itemIndex: 1,
        exerciseID: exerciseID,
        itemCount: 2
    ) else {
        try expect(false, "legacy cursor should resolve the second repeated-exercise slot")
        return
    }
    try expectEqual(second.slotID, secondSlotID)
}

runCase("primitive seed resolution covers relative 1rm and bodyweight loads") {
    let exerciseID = primitiveUUID(0x5001)
    let workout = PrimitiveWorkout(
        id: primitiveUUID(0x1001),
        name: "Loads",
        blocks: [
            PrimitiveBlock(id: primitiveUUID(0x2001), sets: [
                PrimitiveSet(
                    id: primitiveUUID(0x3001),
                    timing: .init(mode: .setBounded),
                    slots: [
                        PrimitiveSlot(
                            id: primitiveUUID(0x4001),
                            exerciseID: exerciseID,
                            workTargets: [
                                .init(metric: .reps, valueForm: .single, value: 5, role: .completion),
                            ],
                            load: .init(value: 0.8, unit: .oneRepMax, unitType: .relative)
                        ),
                        PrimitiveSlot(
                            id: primitiveUUID(0x4002),
                            exerciseID: exerciseID,
                            workTargets: [
                                .init(metric: .reps, valueForm: .single, value: 5, role: .completion),
                            ],
                            load: .init(value: 1.25, unit: .bodyweight, unitType: .relative)
                        ),
                        PrimitiveSlot(
                            id: primitiveUUID(0x4003),
                            exerciseID: exerciseID,
                            workTargets: [
                                .init(metric: .reps, valueForm: .single, value: 5, role: .completion),
                            ],
                            load: .init(value: 0.5, unit: .oneRepMax, unitType: .relative)
                        ),
                    ]
                ),
            ]),
        ]
    )

    let plan = try ExecutionPlan.validated(
        workout: workout,
        userParameters: [
            "one_rep_max_\(exerciseID.uuidString.lowercased())_kg": 150,
            "bodyweight_kg": 80,
        ]
    )
    let slots = plan.blocks[0].sets[0].slots

    try expectEqual(slots[0].loadKg, 120)
    try expectEqual(slots[0].loadUnit, .kg)
    try expectEqual(slots[0].loadDisplayValue, 120)
    try expectEqual(slots[1].loadKg, 100)
    try expectEqual(slots[1].loadUnit, .kg)
    try expectEqual(slots[1].loadDisplayValue, 100)
    try expectEqual(slots[2].loadKg, 75)
}

runCase("primitive seed resolution covers absolute relative implicit and carried loads") {
    let exerciseID = primitiveUUID(0x5001)
    let workout = PrimitiveWorkout(
        id: primitiveUUID(0x1001),
        name: "Loads",
        blocks: [
            PrimitiveBlock(id: primitiveUUID(0x2001), sets: [
                PrimitiveSet(
                    id: primitiveUUID(0x3001),
                    timing: .init(mode: .setBounded),
                    slots: [
                        PrimitiveSlot(
                            id: primitiveUUID(0x4001),
                            exerciseID: exerciseID,
                            workTargets: [
                                .init(metric: .reps, valueForm: .single, value: 5, role: .completion),
                            ],
                            load: .init(value: 100, unit: .kg, unitType: .absolute)
                        ),
                        PrimitiveSlot(
                            id: primitiveUUID(0x4002),
                            exerciseID: exerciseID,
                            workTargets: [
                                .init(metric: .reps, valueForm: .single, value: 5, role: .completion),
                            ],
                            load: .init(value: 200, unit: .lb, unitType: .absolute)
                        ),
                        PrimitiveSlot(
                            id: primitiveUUID(0x4003),
                            exerciseID: exerciseID,
                            workTargets: [
                                .init(metric: .reps, valueForm: .single, value: 5, role: .completion),
                            ],
                            load: .init(value: 0.8, unit: .oneRepMax, unitType: .relative)
                        ),
                        PrimitiveSlot(
                            id: primitiveUUID(0x4004),
                            exerciseID: exerciseID,
                            workTargets: [
                                .init(metric: .reps, valueForm: .single, value: 5, role: .completion),
                            ],
                            load: .init(value: 1.25, unit: .bodyweight, unitType: .relative)
                        ),
                        PrimitiveSlot(
                            id: primitiveUUID(0x4005),
                            exerciseID: exerciseID,
                            workTargets: [
                                .init(metric: .completion, valueForm: .open, role: .completion),
                            ],
                            load: .init(unit: .bodyweight, unitType: .implicitBodyweight)
                        ),
                        PrimitiveSlot(
                            id: primitiveUUID(0x4006),
                            exerciseID: exerciseID,
                            workTargets: [
                                .init(metric: .distance, valueForm: .single, value: 50, role: .completion),
                                .init(metric: .loadCarried, valueForm: .single, value: 60, role: .observation),
                            ],
                            load: .init(value: 60, unit: .lb, unitType: .absolute)
                        ),
                    ]
                ),
            ]),
        ]
    )

    let plan = try ExecutionPlan.validated(
        workout: workout,
        userParameters: [
            "one_rep_max_\(exerciseID.uuidString.lowercased())_kg": 150,
            "bodyweight_kg": 80,
        ]
    )
    let slots = plan.blocks[0].sets[0].slots

    try expectEqual(slots[0].loadKg, 100)
    try expectEqual(slots[0].loadUnit, .kg)
    try expectApprox(slots[1].loadKg ?? -1, 90.718474, accuracy: 0.000001)
    try expectEqual(slots[1].loadUnit, .lb)
    try expectEqual(slots[2].loadKg, 120)
    try expectEqual(slots[2].loadUnit, .kg)
    try expectEqual(slots[3].loadKg, 100)
    try expectEqual(slots[3].loadUnit, .kg)
    try expectEqual(slots[4].loadKg, nil)
    try expectEqual(slots[4].loadUnit, nil)
    try expectEqual(slots[5].workTargets.map(\.metric), [.distance, .loadCarried])
    try expectApprox(slots[5].loadKg ?? -1, 27.2155422, accuracy: 0.000001)
}

runCase("primitive seed resolution preserves unresolved relative display value") {
    let exerciseID = primitiveUUID(0x5002)
    let workout = primitiveWorkout(
        setID: primitiveUUID(0x3002),
        timing: .init(mode: .setBounded),
        traversal: .sequential,
        load: .init(value: 0.7, unit: .oneRepMax, unitType: .relative)
    )

    let plan = try ExecutionPlan.validated(workout: workout, userParameters: [:])
    let slot = plan.blocks[0].sets[0].slots[0]

    try expectEqual(slot.exerciseID, exerciseID)
    try expectEqual(slot.loadKg, nil)
    try expectEqual(slot.loadUnit, nil)
    try expectEqual(slot.loadDisplayValue, 0.7)
}

runCase("primitive semantics rejects malformed timing cells and ambiguous completions") {
    let setBoundedAMRAP = primitiveWorkout(
        setID: primitiveUUID(0x3011),
        timing: .init(mode: .setBounded),
        traversal: .amrap
    )
    do {
        _ = try ExecutionPlan.validated(workout: setBoundedAMRAP)
        try expect(false, "set-bounded AMRAP must reject")
    } catch PrimitiveSemanticError.illegalRuntimeCell(let setID) {
        try expectEqual(setID, primitiveUUID(0x3011))
    }

    let targetBoundedAMRAP = primitiveWorkout(
        setID: primitiveUUID(0x3012),
        timing: .init(mode: .targetBounded),
        traversal: .amrap
    )
    do {
        _ = try ExecutionPlan.validated(workout: targetBoundedAMRAP)
        try expect(false, "target-bounded AMRAP must reject")
    } catch PrimitiveSemanticError.illegalRuntimeCell(let setID) {
        try expectEqual(setID, primitiveUUID(0x3012))
    }

    let missingInterval = primitiveWorkout(
        setID: primitiveUUID(0x3013),
        timing: .init(mode: .timeBounded, rounds: 3),
        traversal: .sequential
    )
    do {
        _ = try ExecutionPlan.validated(workout: missingInterval)
        try expect(false, "time-bounded cells require interval and rounds")
    } catch PrimitiveSemanticError.invalidTiming(let setID) {
        try expectEqual(setID, primitiveUUID(0x3013))
    }

    let missingCap = primitiveWorkout(
        setID: primitiveUUID(0x3014),
        timing: .init(mode: .capBounded),
        traversal: .sequential,
        setTargets: [.init(metric: .duration, valueForm: .open, role: .observation)]
    )
    do {
        _ = try ExecutionPlan.validated(workout: missingCap)
        try expect(false, "cap-bounded cells require cap_sec")
    } catch PrimitiveSemanticError.invalidTiming(let setID) {
        try expectEqual(setID, primitiveUUID(0x3014))
    }

    let amrapWithoutRoundsTarget = primitiveWorkout(
        setID: primitiveUUID(0x3015),
        timing: .init(mode: .capBounded, capSec: 300),
        traversal: .amrap
    )
    do {
        _ = try ExecutionPlan.validated(workout: amrapWithoutRoundsTarget)
        try expect(false, "cap-bounded AMRAP must carry rounds observation")
    } catch PrimitiveSemanticError.invalidTiming(let setID) {
        try expectEqual(setID, primitiveUUID(0x3015))
    }

    let capWithoutDuration = primitiveWorkout(
        setID: primitiveUUID(0x3016),
        timing: .init(mode: .capBounded, capSec: 300),
        traversal: .sequential
    )
    do {
        _ = try ExecutionPlan.validated(workout: capWithoutDuration)
        try expect(false, "cap-bounded sequential cell without duration target must reject")
    } catch PrimitiveSemanticError.invalidTiming(let setID) {
        try expectEqual(setID, primitiveUUID(0x3016))
    }

    let ambiguous = primitiveWorkout(
        setID: primitiveUUID(0x3017),
        timing: .init(mode: .setBounded),
        traversal: .sequential,
        slotTargets: [
            .init(metric: .distance, valueForm: .single, value: 50, role: .completion),
            .init(metric: .loadCarried, valueForm: .single, value: 60, role: .completion),
        ]
    )
    do {
        _ = try ExecutionPlan.validated(workout: ambiguous)
        try expect(false, "ambiguous completion metrics must reject")
    } catch PrimitiveSemanticError.invalidTiming(let setID) {
        try expectEqual(setID, primitiveUUID(0x3017))
    }

    let zeroSlotTimed = PrimitiveWorkout(
        id: primitiveUUID(0x1018),
        name: "Timer-only",
        blocks: [
            PrimitiveBlock(id: primitiveUUID(0x2018), sets: [
                PrimitiveSet(
                    id: primitiveUUID(0x3018),
                    timing: .init(mode: .timeBounded, intervalSec: 60, rounds: 1),
                    slots: []
                ),
            ]),
        ]
    )
    do {
        _ = try ExecutionPlan.validated(workout: zeroSlotTimed)
        try expect(false, "zero-slot timed primitive sets must reject")
    } catch PrimitiveSemanticError.invalidTiming(let setID) {
        try expectEqual(setID, primitiveUUID(0x1018))
    }
}

runCase("primitive metric roles preserve non-rep slot result logs") {
    let workout = primitiveWorkout(
        setID: primitiveUUID(0x3020),
        timing: .init(mode: .setBounded),
        traversal: .sequential,
        slotTargets: [
            .init(metric: .distance, valueForm: .single, value: 1_000, role: .completion),
            .init(metric: .duration, valueForm: .open, role: .observation),
            .init(metric: .loadCarried, valueForm: .single, value: 60, role: .observation),
        ],
        load: .init(value: 60, unit: .lb, unitType: .absolute)
    )
    let plan = try ExecutionPlan.validated(workout: workout)
    let slot = plan.blocks[0].sets[0].slots[0]

    let log = slot.slotLog(
        workoutID: workout.id,
        blockRepeatIndex: 0,
        setRepeatIndex: 0,
        setIndex: 0,
        reps: nil,
        durationSec: 360,
        distanceM: 1_000,
        rir: nil,
        completedAt: Date(timeIntervalSince1970: 100)
    )

    try expectEqual(slot.workTargets.map(\.role), [.completion, .observation, .observation])
    try expectEqual(slot.resultInputContract?.metric, .distance)
    try expectEqual(slot.secondaryDisplayTargets.map(\.metric), [.duration, .loadCarried])
    try expectEqual(log.role, .slot)
    try expectEqual(log.distanceM, 1_000)
    try expectEqual(log.durationSec, 360)
    try expectEqual(log.reps, nil)
    try expectApprox(log.weight ?? -1, 60, accuracy: 0.000001)
    try expectEqual(log.weightUnit, .lb)
}

runCase("primitive result identity helpers live on ExecutionPlan") {
    let workout = primitiveWorkout(
        setID: primitiveUUID(0x3030),
        timing: .init(mode: .capBounded, capSec: 300),
        traversal: .amrap,
        setTargets: [.init(metric: .rounds, valueForm: .open, role: .observation)]
    )
    let plan = try ExecutionPlan.validated(workout: workout)
    let slot = plan.blocks[0].sets[0].slots[0]
    let completedAt = Date(timeIntervalSince1970: 200)

    let first = slot.slotLog(
        workoutID: workout.id,
        blockRepeatIndex: 1,
        setRepeatIndex: 2,
        setIndex: 3,
        reps: 10,
        rir: 2,
        completedAt: completedAt
    )
    let same = slot.slotLog(
        workoutID: workout.id,
        blockRepeatIndex: 1,
        setRepeatIndex: 2,
        setIndex: 3,
        reps: 11,
        rir: 1,
        completedAt: completedAt
    )
    let aggregate = plan.setResultLog(
        blockIndex: 0,
        setIndexInBlock: 0,
        blockRepeatIndex: 1,
        setRepeatIndex: 2,
        reps: 4,
        rounds: 7,
        durationSec: 300,
        completedAt: completedAt
    )

    try expectEqual(first.id, same.id, "same coordinate is a same-UUID correction target")
    try expect(first.id != aggregate.id, "slot and aggregate ids must be distinct")
    try expectEqual(aggregate.role, .setResult)
    try expectEqual(aggregate.blockRepeatIndex, 1)
    try expectEqual(aggregate.setRepeatIndex, 2)
    try expectEqual(aggregate.setIndex, 0)
}

runCase("session preview projection exposes current remaining and upcoming primitive facts") {
    let exerciseA = primitiveUUID(0x5101)
    let exerciseB = primitiveUUID(0x5102)
    let workout = PrimitiveWorkout(
        id: primitiveUUID(0x1101),
        name: "Preview",
        blocks: [
            PrimitiveBlock(id: primitiveUUID(0x2101), sets: [
                PrimitiveSet(
                    id: primitiveUUID(0x3101),
                    timing: .init(mode: .setBounded),
                    repeatCount: 2,
                    slots: [
                        PrimitiveSlot(
                            id: primitiveUUID(0x4101),
                            exerciseID: exerciseA,
                            workTargets: [
                                .init(metric: .reps, valueForm: .single, value: 5, role: .completion),
                                .init(metric: .duration, valueForm: .open, role: .observation),
                            ],
                            load: .init(value: 100, unit: .kg, unitType: .absolute)
                        ),
                    ]
                ),
            ]),
            PrimitiveBlock(id: primitiveUUID(0x2102), sets: [
                PrimitiveSet(
                    id: primitiveUUID(0x3102),
                    timing: .init(mode: .setBounded),
                    slots: [
                        PrimitiveSlot(
                            id: primitiveUUID(0x4102),
                            exerciseID: exerciseB,
                            workTargets: [
                                .init(metric: .distance, valueForm: .single, value: 100, role: .completion),
                            ]
                        ),
                    ]
                ),
            ]),
        ]
    )
    let projection = SessionPreviewProjection(plan: try ExecutionPlan.validated(workout: workout))

    try expectEqual(projection.current?.exerciseID, exerciseA)
    try expectEqual(projection.current?.primaryDisplayTarget?.metric, .reps)
    try expectEqual(projection.current?.secondaryDisplayTargets.map(\.metric), [.duration])
    try expectEqual(projection.current?.loadKg, 100)
    try expectEqual(projection.currentBlock?.blockID, primitiveUUID(0x2101))
    try expectEqual(projection.remaining, .bounded(completed: 0, total: 2))
    try expectEqual(projection.remaining.remaining, 2)
    try expectEqual(projection.upcoming.first?.exerciseID, exerciseA)
    try expectEqual(projection.upcoming.dropFirst().first?.exerciseID, exerciseB)
}

runCase("session preview projection suppresses unbounded progress totals") {
    let workout = primitiveWorkout(
        setID: primitiveUUID(0x3201),
        timing: .init(mode: .capBounded, capSec: 300),
        traversal: .amrap,
        setTargets: [.init(metric: .rounds, valueForm: .open, role: .observation)]
    )
    let projection = SessionPreviewProjection(plan: try ExecutionPlan.validated(workout: workout))

    try expectEqual(projection.remaining, .unbounded)
    try expectEqual(projection.remaining.remaining, nil)
}

runCase("session preview projection handles zero-set rest block") {
    let plan = ExecutionPlan(
        workoutID: primitiveUUID(0x1201),
        blocks: [
            ExecutionBlock(
                blockID: primitiveUUID(0x2201),
                blockRepeat: 1,
                workTargets: [],
                sets: []
            ),
        ]
    )
    let projection = SessionPreviewProjection(plan: plan)

    try expectEqual(projection.current, nil)
    try expectEqual(projection.currentBlock?.blockID, primitiveUUID(0x2201))
    try expectEqual(projection.remaining, .bounded(completed: 0, total: 0))
    try expectEqual(projection.upcoming, [])
}

runCase("primitive semantics rejects zero-slot timed rest sibling until runtime supports it") {
    let exerciseID = primitiveUUID(0x5204)
    let workout = PrimitiveWorkout(
        id: primitiveUUID(0x1204),
        name: "Timed",
        blocks: [
            PrimitiveBlock(id: primitiveUUID(0x2204), sets: [
                PrimitiveSet(
                    id: primitiveUUID(0x3203),
                    timing: .init(mode: .setBounded),
                    slots: [
                        PrimitiveSlot(
                            id: primitiveUUID(0x4203),
                            exerciseID: exerciseID,
                            workTargets: [
                                .init(metric: .reps, valueForm: .single, value: 10, role: .completion),
                            ]
                        ),
                    ]
                ),
                PrimitiveSet(
                    id: primitiveUUID(0x3204),
                    timing: .init(mode: .timeBounded, intervalSec: 60, rounds: 3),
                    slots: []
                ),
            ]),
        ]
    )
    do {
        _ = try ExecutionPlan.validated(workout: workout)
        try expect(false, "zero-slot timed rest siblings must reject until primitive rest runtime exists")
    } catch PrimitiveSemanticError.invalidTiming(let setID) {
        try expectEqual(setID, primitiveUUID(0x3204))
    }
}

runCase("session preview projection binds metadata to forwarded current block") {
    let exerciseID = primitiveUUID(0x1203)
    let plan = ExecutionPlan(
        workoutID: primitiveUUID(0x1202),
        blocks: [
            ExecutionBlock(
                blockID: primitiveUUID(0x2202),
                blockRepeat: 1,
                workTargets: [
                    .init(metric: .duration, valueForm: .single, value: 90, role: .completion),
                ],
                sets: []
            ),
            ExecutionBlock(
                blockID: primitiveUUID(0x2203),
                blockRepeat: 1,
                workTargets: [],
                sets: [
                    ExecutionSet(
                        setID: primitiveUUID(0x3203),
                        blockID: primitiveUUID(0x2203),
                        setRepeat: 2,
                        timing: .init(mode: .setBounded),
                        traversal: .sequential,
                        workTargets: [],
                        slots: [
                            ExecutionSlot(
                                slotID: primitiveUUID(0x4203),
                                setID: primitiveUUID(0x3203),
                                blockID: primitiveUUID(0x2203),
                                exerciseID: exerciseID,
                                workTargets: [
                                    .init(
                                        metric: .reps,
                                        valueForm: .single,
                                        value: 8,
                                        role: .completion
                                    ),
                                ],
                                loadKg: nil,
                                loadUnit: nil,
                                loadDisplayValue: nil,
                                stimuli: [],
                                postRestSec: 0,
                                isWarmup: false
                            ),
                        ]
                    ),
                ]
            ),
        ]
    )

    let projection = SessionPreviewProjection(plan: plan)

    try expectEqual(projection.current?.exerciseID, exerciseID)
    try expectEqual(projection.currentBlock?.blockID, primitiveUUID(0x2203))
    try expectEqual(projection.currentBlock?.blockIndex, 1)
    try expectEqual(projection.remaining, .bounded(completed: 0, total: 2))
}

runPrimitiveCompositionGeneratorTests()

func primitiveWorkout(
    setID: UUID,
    timing: PrimitiveTiming,
    traversal: PrimitiveTraversal,
    setTargets: [PrimitiveWorkTarget] = [],
    slotTargets: [PrimitiveWorkTarget] = [
        .init(metric: .reps, valueForm: .single, value: 10, role: .completion),
    ],
    load: PrimitiveLoad? = nil
) -> PrimitiveWorkout {
    PrimitiveWorkout(
        id: primitiveUUID(0x1000),
        name: "Primitive",
        blocks: [
            PrimitiveBlock(id: primitiveUUID(0x2000), sets: [
                PrimitiveSet(
                    id: setID,
                    timing: timing,
                    traversal: traversal,
                    workTargets: setTargets,
                    slots: [
                        PrimitiveSlot(
                            id: primitiveUUID(0x4000),
                            exerciseID: primitiveUUID(0x5002),
                            workTargets: slotTargets,
                            load: load
                        ),
                    ]
                ),
            ]),
        ]
    )
}

func primitiveUUID(_ suffix: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", suffix))!
}

func pristineSets(loadKg: Double = 100.0, reps: Int = 5, count: Int = 3) -> [SetPlan] {
    (1...count).map { i in
        SetPlan(setIndex: i, loadKg: loadKg, reps: reps, done: false, adjust: nil, rir: nil)
    }
}

/// Build a baseline state with two items (itemA, itemB), each with 3 sets,
/// all pending, route=today, cursor at (0, 0, 1). Tests layer on top.
func makeBaselineState() -> SessionState {
    SessionState(
        workoutID: workoutID,
        route: .today,
        cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
        items: [
            SessionState.ItemLog(itemID: itemA, sets: pristineSets()),
            SessionState.ItemLog(itemID: itemB, sets: pristineSets()),
        ],
        restEndsAt: nil,
        note: "",
        structure: SessionState.Structure(
            itemsPerBlock: [2],
            setsPerItem: [[3, 3]]
        )
    )
}

// ---------------------------------------------------------------------------
// 1. start: today → active
// ---------------------------------------------------------------------------
runCase("start · today → active") {
    let s0 = makeBaselineState()
    try expectEqual(s0.route, .today)
    let s1 = SessionReducer.reduce(s0, .start)
    try expectEqual(s1.route, .active)
    // Cursor unchanged (already at first set by construction).
    try expectEqual(s1.cursor.blockIndex, 0)
    try expectEqual(s1.cursor.itemIndex, 0)
    try expectEqual(s1.cursor.setIndex, 1)
}

// ---------------------------------------------------------------------------
// 2. logSet · marks target set done=true with reps+rir; other sets untouched.
// ---------------------------------------------------------------------------
runCase("logSet · target set done=true, reps+rir set; other sets unchanged") {
    let s0 = SessionReducer.reduce(makeBaselineState(), .start)
    let s1 = SessionReducer.reduce(
        s0,
        .logSet(itemID: itemA, setIndex: 2, loggedReps: 4, loggedRir: 1, now: logSetStamp)
    )

    let setsA = s1.items.first(where: { $0.itemID == itemA })!.sets
    try expectEqual(setsA[0].done, false)
    try expectEqual(setsA[0].reps, 5)
    try expectEqual(setsA[0].rir, nil)
    try expectEqual(setsA[1].done, true)
    try expectEqual(setsA[1].reps, 4)
    try expectEqual(setsA[1].rir, 1)
    try expectEqual(setsA[2].done, false)
    try expectEqual(setsA[2].rir, nil)

    // itemB entirely untouched.
    let setsB = s1.items.first(where: { $0.itemID == itemB })!.sets
    try expectEqual(setsB, pristineSets())
}

runCase("logSet · rir nil is preserved (user skipped picker)") {
    let s0 = SessionReducer.reduce(makeBaselineState(), .start)
    let s1 = SessionReducer.reduce(
        s0,
        .logSet(itemID: itemA, setIndex: 1, loggedReps: 5, loggedRir: nil, now: logSetStamp)
    )
    let setsA = s1.items.first(where: { $0.itemID == itemA })!.sets
    try expectEqual(setsA[0].done, true)
    try expectEqual(setsA[0].reps, 5)
    try expectEqual(setsA[0].rir, nil)
}

runCase("skipSet · marks row done/skipped without performance metrics") {
    var s0 = SessionReducer.reduce(makeBaselineState(), .start)
    s0.workStartedAt = Date(timeIntervalSince1970: 1_699_999_990)
    let s1 = SessionReducer.reduce(
        s0,
        .skipSet(itemID: itemA, setIndex: 1, now: logSetStamp)
    )

    let set = s1.items.first(where: { $0.itemID == itemA })!.sets[0]
    try expectEqual(set.done, true)
    try expectEqual(set.skipped, true)
    try expectEqual(set.rir, nil)
    try expectEqual(set.durationSec, nil)
    try expectEqual(set.distanceM, nil)
    try expectEqual(set.completedAt, logSetStamp)
    try expectEqual(set.startedAt, Date(timeIntervalSince1970: 1_699_999_990))
    try expectEqual(set.side, .bilateral)
    try expectEqual(s1.workStartedAt, nil)
}

// ---------------------------------------------------------------------------
// 3. editPastSet · preserves done=true, updates fields, sets adjust=.manual.
// ---------------------------------------------------------------------------
runCase("editPastSet · done=true preserved, fields updated, adjust=.manual") {
    var s = makeBaselineState()
    s = SessionReducer.reduce(s, .start)
    s = SessionReducer.reduce(
        s,
        .logSet(itemID: itemA, setIndex: 1, loggedReps: 5, loggedRir: 2, now: logSetStamp)
    )
    s = SessionReducer.reduce(
        s,
        .editPastSet(
            itemID: itemA,
            setIndex: 1,
            loadKg: 105.0,
            reps: 6,
            rir: 3
        )
    )
    let set = s.items.first(where: { $0.itemID == itemA })!.sets[0]
    try expectEqual(set.done, true)
    try expectEqual(set.loadKg, 105.0)
    try expectEqual(set.reps, 6)
    try expectEqual(set.rir, 3)
    try expectEqual(set.adjust, .manual)
}

// ---------------------------------------------------------------------------
// 4. editPastSet · leaves adjust=.manual if already .manual.
// ---------------------------------------------------------------------------
runCase("editPastSet · adjust stays .manual when already .manual") {
    var s = makeBaselineState()
    s = SessionReducer.reduce(s, .start)
    s = SessionReducer.reduce(
        s,
        .logSet(itemID: itemA, setIndex: 1, loggedReps: 5, loggedRir: 2, now: logSetStamp)
    )
    // First edit stamps .manual
    s = SessionReducer.reduce(
        s,
        .editPastSet(itemID: itemA, setIndex: 1, loadKg: 110.0, reps: nil, rir: nil)
    )
    try expectEqual(s.items[0].sets[0].adjust, .manual)
    // Second edit — adjust stays .manual (idempotent)
    s = SessionReducer.reduce(
        s,
        .editPastSet(itemID: itemA, setIndex: 1, loadKg: nil, reps: 7, rir: nil)
    )
    try expectEqual(s.items[0].sets[0].adjust, .manual)
    try expectEqual(s.items[0].sets[0].loadKg, 110.0)
    try expectEqual(s.items[0].sets[0].reps, 7)
}

// ---------------------------------------------------------------------------
// 5. editPendingSet · non-done set, updates fields, marks .manual.
// ---------------------------------------------------------------------------
runCase("editPendingSet · non-done set updated, adjust=.manual") {
    var s = makeBaselineState()
    let started = Date(timeIntervalSince1970: 1_700_000_010)
    s = SessionReducer.reduce(s, .start)
    s = SessionReducer.reduce(
        s,
        .editPendingSet(
            itemID: itemA,
            setIndex: 2,
            loadKg: 102.5,
            reps: 6,
            rir: 2,
            startedAt: started
        )
    )
    let set = s.items[0].sets[1]
    try expectEqual(set.done, false)
    try expectEqual(set.loadKg, 102.5)
    try expectEqual(set.reps, 6)
    try expectEqual(set.rir, 2)
    try expectEqual(set.startedAt, started)
    try expectEqual(set.adjust, .manual)
}

runCase("markPendingSetStarted · stamps startedAt without manual adjust") {
    var s = makeBaselineState()
    let started = Date(timeIntervalSince1970: 1_700_000_020)
    s = SessionReducer.reduce(s, .start)
    s = SessionReducer.reduce(
        s,
        .markPendingSetStarted(itemID: itemA, setIndex: 2, startedAt: started)
    )
    let set = s.items[0].sets[1]
    try expectEqual(set.done, false)
    try expectEqual(set.startedAt, started)
    try expectEqual(set.adjust, nil)
}

runCase("composite set · non-final slot enters intra-set rest without logging") {
    let start = Date(timeIntervalSince1970: 1_700_000_100)
    let done = start.addingTimeInterval(8)
    var s = makeBaselineState()
    s.compositeSets = [
        SessionState.CompositeSetProgress(
            itemID: itemA,
            setIndex: 1,
            kind: .cluster,
            targetRepsPerSlot: 5,
            slotCount: 2,
            intraRestSec: 15
        ),
    ]

    s = SessionReducer.reduce(
        s,
        .startCompositeSlot(itemID: itemA, setIndex: 1, slotIndex: 1, startedAt: start)
    )
    s = SessionReducer.reduce(
        s,
        .completeCompositeSlot(itemID: itemA, setIndex: 1, now: done)
    )

    try expectEqual(s.items[0].sets[0].done, false)
    try expectEqual(s.workStartedAt, nil)
    guard case .intraRest(let afterSlot, let endsAt) = s.compositeSets[0].phase else {
        throw ExpectationFailure(message: "expected intraRest", file: #file, line: #line)
    }
    try expectEqual(afterSlot, 1)
    try expectEqual(endsAt, done.addingTimeInterval(15))
}

runCase("composite set · finalization logs one top-level set with duration") {
    let start = Date(timeIntervalSince1970: 1_700_000_200)
    let done = start.addingTimeInterval(33)
    var s = makeBaselineState()
    s.compositeSets = [
        SessionState.CompositeSetProgress(
            itemID: itemA,
            setIndex: 1,
            kind: .cluster,
            targetRepsPerSlot: 5,
            slotCount: 2,
            intraRestSec: 15,
            firstStartedAt: start,
            phase: .working(slotIndex: 2, startedAt: done.addingTimeInterval(-8)),
            completedSlots: 1
        ),
    ]

    s = SessionReducer.reduce(
        s,
        .finalizeCompositeSet(
            itemID: itemA,
            setIndex: 1,
            loggedReps: 10,
            loggedRir: 1,
            now: done
        )
    )

    let set = s.items[0].sets[0]
    try expectEqual(set.done, true)
    try expectEqual(set.reps, 10)
    try expectEqual(set.rir, 1)
    try expectEqual(set.startedAt, start)
    try expectEqual(set.completedAt, done)
    try expectEqual(set.durationSec ?? -1, 33)
    try expectEqual(s.compositeSets.isEmpty, true)
}

// ---------------------------------------------------------------------------
// 6. applyAutoregProposal · flips .up/.down, preserves .manual and done.
//    (Re-tests CoreAutoreg.apply via the reducer.)
// ---------------------------------------------------------------------------
runCase("applyAutoregProposal · flips non-manual non-done; preserves .manual + done") {
    // Build an item with explicit set shapes: [done=true .up, pending nil,
    // pending .manual, pending nil].
    let sets = [
        SetPlan(setIndex: 1, loadKg: 100.0, reps: 5, done: true,  adjust: .up,     rir: 2),
        SetPlan(setIndex: 2, loadKg: 100.0, reps: 5, done: false, adjust: nil,     rir: nil),
        SetPlan(setIndex: 3, loadKg: 110.0, reps: 5, done: false, adjust: .manual, rir: nil),
        SetPlan(setIndex: 4, loadKg: 100.0, reps: 5, done: false, adjust: nil,     rir: nil),
    ]
    let s0 = SessionState(
        workoutID: workoutID,
        route: .rest,
        cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 2),
        items: [SessionState.ItemLog(itemID: itemA, sets: sets)],
        restEndsAt: nil,
        note: "",
        structure: SessionState.Structure(itemsPerBlock: [1], setsPerItem: [[4]])
    )
    let proposal = AutoregProposal(
        direction: .down,
        newLoadKg: 97.5,
        reason: .undershootReps(prescribed: 5, actual: 3, threshold: 2)
    )
    let s1 = SessionReducer.reduce(
        s0,
        .applyAutoregProposal(itemID: itemA, proposal: proposal)
    )
    let out = s1.items[0].sets
    // done stays, adjust stays .up, load unchanged
    try expectEqual(out[0].done, true)
    try expectEqual(out[0].adjust, .up)
    try expectEqual(out[0].loadKg, 100.0)
    // pending nil → .down, load bumped
    try expectEqual(out[1].adjust, .down)
    try expectEqual(out[1].loadKg, 97.5)
    // .manual preserved
    try expectEqual(out[2].adjust, .manual)
    try expectEqual(out[2].loadKg, 110.0)
    // pending nil → .down
    try expectEqual(out[3].adjust, .down)
    try expectEqual(out[3].loadKg, 97.5)
}

// ---------------------------------------------------------------------------
// 7. holdAutoreg · sets autoregHeld=true; Core/Session stores the flag and
//    still applies a proposal if one is dispatched (the decision to skip
//    Autoreg.propose lives in Features layer — documented behavior).
// ---------------------------------------------------------------------------
runCase("holdAutoreg · sets flag; idempotent; applyAutoregProposal still mutates") {
    var s = makeBaselineState()
    s = SessionReducer.reduce(s, .start)
    s = SessionReducer.reduce(s, .holdAutoreg(itemID: itemA))
    try expectEqual(s.items[0].autoregHeld, true)
    try expectEqual(s.items[1].autoregHeld, false, "other item unaffected")

    // Idempotent.
    s = SessionReducer.reduce(s, .holdAutoreg(itemID: itemA))
    try expectEqual(s.items[0].autoregHeld, true)

    // Core/Session does not block `applyAutoregProposal` on held — the
    // Features layer is expected to never propose when held. If the
    // caller does dispatch one anyway, the reducer applies it.
    let proposal = AutoregProposal(
        direction: .up,
        newLoadKg: 102.5,
        reason: .overshoot(rirLogged: 4, targetRir: 2, threshold: 2)
    )
    s = SessionReducer.reduce(s, .applyAutoregProposal(itemID: itemA, proposal: proposal))
    try expectEqual(s.items[0].sets[0].loadKg, 102.5)
    try expectEqual(s.items[0].sets[0].adjust, .up)
}

// ---------------------------------------------------------------------------
// 8. swap · sets performedExerciseID on target; other items unchanged;
//    does not reset autoregHeld; does not modify logged sets.
// ---------------------------------------------------------------------------
runCase("swap · target item gets performedExerciseID; other untouched; held preserved; logs preserved") {
    var s = makeBaselineState()
    s = SessionReducer.reduce(s, .start)
    s = SessionReducer.reduce(s, .holdAutoreg(itemID: itemA))
    s = SessionReducer.reduce(
        s,
        .logSet(itemID: itemA, setIndex: 1, loggedReps: 5, loggedRir: 2, now: logSetStamp)
    )

    let s1 = SessionReducer.reduce(s, .swap(itemID: itemA, toExerciseID: exerciseAlt))
    try expectEqual(s1.items[0].performedExerciseID, exerciseAlt)
    try expectEqual(s1.items[0].autoregHeld, true, "hold preserved across swap")
    // Logged set preserved.
    try expectEqual(s1.items[0].sets[0].done, true)
    try expectEqual(s1.items[0].sets[0].reps, 5)
    try expectEqual(s1.items[0].sets[0].rir, 2)
    // Other item untouched.
    try expectEqual(s1.items[1].performedExerciseID, nil)
}

// 8b. swap + overrides · non-done sets pick up load/reps, logged set
//     preserved, target_rir lands on ItemLog.overrides for the driver.
runCase("swap+overrides · remaining sets updated; logged set preserved; target_rir stored") {
    var s = makeBaselineState()
    s = SessionReducer.reduce(s, .start)
    s = SessionReducer.reduce(
        s,
        .logSet(itemID: itemA, setIndex: 1, loggedReps: 5, loggedRir: 2, now: logSetStamp)
    )
    let overrides = AlternativeOverrides(reps: 8, loadKg: 70, targetRir: 3)
    let s1 = SessionReducer.reduce(
        s,
        .swap(itemID: itemA, toExerciseID: exerciseAlt, overrides: overrides)
    )
    try expectEqual(s1.items[0].performedExerciseID, exerciseAlt)
    try expectEqual(s1.items[0].overrides?.reps, 8)
    try expectEqual(s1.items[0].overrides?.loadKg, 70)
    try expectEqual(s1.items[0].overrides?.targetRir, 3)
    // Logged set untouched.
    try expectEqual(s1.items[0].sets[0].done, true)
    try expectEqual(s1.items[0].sets[0].reps, 5)
    try expectEqual(s1.items[0].sets[0].loadKg, 100.0)
    // Remaining sets carry the override.
    try expectEqual(s1.items[0].sets[1].reps, 8)
    try expectEqual(s1.items[0].sets[1].loadKg, 70.0)
    try expectEqual(s1.items[0].sets[2].reps, 8)
    try expectEqual(s1.items[0].sets[2].loadKg, 70.0)
    // Other item entirely untouched.
    try expectEqual(s1.items[1].overrides, nil)
}

// 8c. swap with empty-overrides payload is equivalent to a pure swap —
//     the overrides field stays nil so drivers don't branch.
runCase("swap+empty overrides · overrides field stays nil") {
    var s = SessionReducer.reduce(makeBaselineState(), .start)
    let empty = AlternativeOverrides()
    s.compositeSets = [
        SessionState.CompositeSetProgress(
            itemID: itemA,
            setIndex: 1,
            kind: .cluster,
            targetRepsPerSlot: 5,
            slotCount: 2,
            intraRestSec: 15
        ),
    ]
    s = SessionReducer.reduce(
        s,
        .swap(itemID: itemA, toExerciseID: exerciseAlt, overrides: empty)
    )
    try expectEqual(s.items[0].performedExerciseID, exerciseAlt)
    try expectEqual(s.items[0].overrides, nil)
    try expectEqual(s.compositeSets.count, 1, "pure swap preserves cluster slot progress")
    try expectEqual(s.compositeSets[0].setIndex, 1)
    // Sets unchanged.
    try expectEqual(s.items[0].sets[0].loadKg, 100.0)
    try expectEqual(s.items[0].sets[0].reps, 5)
}

// 8d. swap+overrides · a .manual set is preserved (user's edit wins).
runCase("swap+overrides · manual set preserved, other remaining sets overridden") {
    var s = SessionReducer.reduce(makeBaselineState(), .start)
    // User manually edited set 2.
    s = SessionReducer.reduce(
        s,
        .editPendingSet(itemID: itemA, setIndex: 2, loadKg: 90.0, reps: nil, rir: nil, startedAt: nil)
    )
    try expectEqual(s.items[0].sets[1].loadKg, 90.0)
    try expectEqual(s.items[0].sets[1].adjust, .manual)
    let overrides = AlternativeOverrides(loadKg: 70)
    let s1 = SessionReducer.reduce(
        s,
        .swap(itemID: itemA, toExerciseID: exerciseAlt, overrides: overrides)
    )
    // Set 1: non-manual, non-done → overridden.
    try expectEqual(s1.items[0].sets[0].loadKg, 70.0)
    // Set 2: manual → preserved.
    try expectEqual(s1.items[0].sets[1].loadKg, 90.0)
    try expectEqual(s1.items[0].sets[1].adjust, .manual)
    // Set 3: non-manual, non-done → overridden.
    try expectEqual(s1.items[0].sets[2].loadKg, 70.0)
}

runCase("swap+overrides · manual cluster row preserves slot target") {
    var s = SessionReducer.reduce(makeBaselineState(), .start)
    s.compositeSets = [
        SessionState.CompositeSetProgress(
            itemID: itemA,
            setIndex: 1,
            kind: .cluster,
            targetRepsPerSlot: 5,
            slotCount: 2,
            intraRestSec: 15
        ),
        SessionState.CompositeSetProgress(
            itemID: itemA,
            setIndex: 2,
            kind: .cluster,
            targetRepsPerSlot: 5,
            slotCount: 2,
            intraRestSec: 15
        ),
        SessionState.CompositeSetProgress(
            itemID: itemA,
            setIndex: 3,
            kind: .cluster,
            targetRepsPerSlot: 5,
            slotCount: 2,
            intraRestSec: 15
        ),
    ]
    s = SessionReducer.reduce(
        s,
        .editPendingSet(itemID: itemA, setIndex: 2, loadKg: 90.0, reps: nil, rir: nil, startedAt: nil)
    )

    let overrides = AlternativeOverrides(reps: 8, loadKg: 70)
    let s1 = SessionReducer.reduce(
        s,
        .swap(itemID: itemA, toExerciseID: exerciseAlt, overrides: overrides)
    )

    try expectEqual(s1.items[0].sets.map(\.reps), [16, 5, 16])
    try expectEqual(s1.items[0].sets.map(\.loadKg), [70, 90, 70])
    try expectEqual(s1.compositeSets.map(\.targetRepsPerSlot), [8, 5, 8])
}

// 8e. swap+overrides · sets override on a STRAIGHT-SETS block IS applied.
//     Sanity: the existing `sets` resize path still works for set-major
//     blocks — we didn't regress straight-sets by narrowing the contract
//     for round-robin. This is the baseline the rejection cases contrast
//     against.
runCase("swap+overrides · sets override applied on straight-sets cluster block") {
    // Baseline structure defaults to .setMajor via `itemsPerBlock.map`.
    var s = SessionReducer.reduce(makeBaselineState(), .start)
    s.compositeSets = [
        SessionState.CompositeSetProgress(
            itemID: itemA,
            setIndex: 1,
            kind: .cluster,
            targetRepsPerSlot: 5,
            slotCount: 2,
            intraRestSec: 15
        ),
        SessionState.CompositeSetProgress(
            itemID: itemA,
            setIndex: 2,
            kind: .cluster,
            targetRepsPerSlot: 5,
            slotCount: 2,
            intraRestSec: 15
        ),
        SessionState.CompositeSetProgress(
            itemID: itemA,
            setIndex: 3,
            kind: .cluster,
            targetRepsPerSlot: 5,
            slotCount: 2,
            intraRestSec: 15
        ),
    ]
    // Override bumps the top-level set count to 5 and the per-slot
    // cluster reps to 8; each top-level SetPlan stores total reps.
    let overrides = AlternativeOverrides(sets: 5, reps: 8, loadKg: 70)
    s = SessionReducer.reduce(
        s,
        .swap(itemID: itemA, toExerciseID: exerciseAlt, overrides: overrides)
    )
    try expectEqual(s.items[0].sets.count, 5, "set-major block honors sets override")
    try expectEqual(s.items[0].overrides?.sets, 5)
    try expectEqual(s.items[0].overrides?.reps, 8)
    try expectEqual(s.structure.setsPerItem[0][0], 5, "structure tracks new count")
    try expectEqual(s.compositeSets.filter { $0.itemID == itemA }.map(\.setIndex), [1, 2, 3, 4, 5])
    try expectEqual(s.compositeSets.map(\.targetRepsPerSlot), [8, 8, 8, 8, 8])
    try expectEqual(s.compositeSets.last?.slotCount, 2)
    // Every pending set carries the override load and total cluster reps.
    try expect(s.items[0].sets.allSatisfy { $0.loadKg == 70 && $0.reps == 16 })
}

// 8f. swap+overrides · sets override on a ROUND-ROBIN block (superset) is
//     REJECTED. Reps / load still apply; the block's rows and structure
//     are untouched. Round-robin blocks replicate a shared `rounds` count
//     across every item, so rewriting one item's count would either skew
//     the cursor walk or silently collapse every item — we narrow the
//     contract to set-major only (Path A).
runCase("swap+overrides · sets override REJECTED on superset (round-robin); other fields apply") {
    // 2-item superset × 3 rounds. Cursor at (0, 0, 1).
    let s0 = SessionState(
        workoutID: workoutID,
        route: .active,
        cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
        items: [
            SessionState.ItemLog(itemID: itemA, sets: pristineSets(count: 3)),
            SessionState.ItemLog(itemID: itemB, sets: pristineSets(count: 3)),
        ],
        restEndsAt: nil,
        note: "",
        structure: SessionState.Structure(
            itemsPerBlock: [2],
            setsPerItem: [[3, 3]],
            advancementByBlock: [.roundRobin]
        )
    )
    let overrides = AlternativeOverrides(sets: 6, reps: 10, loadKg: 60)
    let s1 = SessionReducer.reduce(
        s0,
        .swap(itemID: itemA, toExerciseID: exerciseAlt, overrides: overrides)
    )
    // Sets count is UNCHANGED — the round-robin invariant wins.
    try expectEqual(s1.items[0].sets.count, 3, "round-robin sets count preserved")
    try expectEqual(s1.structure.setsPerItem[0][0], 3, "structure row count preserved")
    try expectEqual(s1.structure.setsPerItem[0][1], 3, "peer item untouched")
    // Other fields DO apply — reps / load mirror onto non-done rows.
    try expect(s1.items[0].sets.allSatisfy { $0.reps == 10 && $0.loadKg == 60 })
    // `overrides` is stored verbatim — the rejection is a runtime
    // interpretation call, not a parser mutation. Drivers reading
    // `overrides?.sets` still see the authored value; they just don't
    // get row-count enforcement behind them.
    try expectEqual(s1.items[0].overrides?.sets, 6)
    try expectEqual(s1.items[0].performedExerciseID, exerciseAlt)
}

runCase("swap+overrides · round-robin cluster updates slot reps while rejecting set count") {
    let s0 = SessionState(
        workoutID: workoutID,
        route: .active,
        cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
        items: [
            SessionState.ItemLog(itemID: itemA, sets: pristineSets(count: 3)),
            SessionState.ItemLog(itemID: itemB, sets: pristineSets(count: 3)),
        ],
        compositeSets: [
            SessionState.CompositeSetProgress(
                itemID: itemA,
                setIndex: 1,
                kind: .cluster,
                targetRepsPerSlot: 5,
                slotCount: 2,
                intraRestSec: 15
            ),
            SessionState.CompositeSetProgress(
                itemID: itemA,
                setIndex: 2,
                kind: .cluster,
                targetRepsPerSlot: 5,
                slotCount: 2,
                intraRestSec: 15
            ),
            SessionState.CompositeSetProgress(
                itemID: itemA,
                setIndex: 3,
                kind: .cluster,
                targetRepsPerSlot: 5,
                slotCount: 2,
                intraRestSec: 15
            ),
        ],
        restEndsAt: nil,
        note: "",
        structure: SessionState.Structure(
            itemsPerBlock: [2],
            setsPerItem: [[3, 3]],
            advancementByBlock: [.roundRobin]
        )
    )
    let overrides = AlternativeOverrides(sets: 6, reps: 10, loadKg: 60)
    let s1 = SessionReducer.reduce(
        s0,
        .swap(itemID: itemA, toExerciseID: exerciseAlt, overrides: overrides)
    )

    try expectEqual(s1.items[0].sets.count, 3, "round-robin sets count preserved")
    try expectEqual(s1.structure.setsPerItem[0][0], 3, "structure row count preserved")
    try expectEqual(s1.items[0].sets.map(\.reps), [20, 20, 20])
    try expectEqual(s1.items[0].sets.map(\.loadKg), [60, 60, 60])
    try expectEqual(s1.compositeSets.map(\.targetRepsPerSlot), [10, 10, 10])
}

// 8g. swap+overrides · sets override on a CIRCUIT block is REJECTED.
runCase("swap+overrides · sets override REJECTED on circuit (round-robin)") {
    // 3-item circuit × 4 rounds.
    let itemC = UUID()
    let s0 = SessionState(
        workoutID: workoutID,
        route: .active,
        cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
        items: [
            SessionState.ItemLog(itemID: itemA, sets: pristineSets(count: 4)),
            SessionState.ItemLog(itemID: itemB, sets: pristineSets(count: 4)),
            SessionState.ItemLog(itemID: itemC, sets: pristineSets(count: 4)),
        ],
        restEndsAt: nil,
        note: "",
        structure: SessionState.Structure(
            itemsPerBlock: [3],
            setsPerItem: [[4, 4, 4]],
            advancementByBlock: [.roundRobin]
        )
    )
    let overrides = AlternativeOverrides(sets: 2)
    let s1 = SessionReducer.reduce(
        s0,
        .swap(itemID: itemB, toExerciseID: exerciseAlt, overrides: overrides)
    )
    // All three items keep their 4 rounds — no collapse to 2.
    try expectEqual(s1.items[0].sets.count, 4)
    try expectEqual(s1.items[1].sets.count, 4)
    try expectEqual(s1.items[2].sets.count, 4)
    try expectEqual(s1.structure.setsPerItem[0], [4, 4, 4])
}

// 8h. swap+overrides · sets override on a TABATA block (8 rounds round-robin)
//     is REJECTED.
runCase("swap+overrides · sets override REJECTED on tabata (round-robin, 8 rounds)") {
    // Tabata: 2 items × 8 rounds. Bumping sets to 4 on one item must NOT
    // truncate it — the 8-round drive loop would overrun the SetPlan array.
    let s0 = SessionState(
        workoutID: workoutID,
        route: .active,
        cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
        items: [
            SessionState.ItemLog(itemID: itemA, sets: pristineSets(count: 8)),
            SessionState.ItemLog(itemID: itemB, sets: pristineSets(count: 8)),
        ],
        restEndsAt: nil,
        note: "",
        structure: SessionState.Structure(
            itemsPerBlock: [2],
            setsPerItem: [[8, 8]],
            advancementByBlock: [.roundRobin]
        )
    )
    let overrides = AlternativeOverrides(sets: 4, loadKg: 20)
    let s1 = SessionReducer.reduce(
        s0,
        .swap(itemID: itemA, toExerciseID: exerciseAlt, overrides: overrides)
    )
    // Row count stays at 8 — tabata's 8-round cursor walk must find every row.
    try expectEqual(s1.items[0].sets.count, 8, "tabata row count preserved")
    try expectEqual(s1.structure.setsPerItem[0][0], 8)
    // The loadKg override still lands.
    try expect(s1.items[0].sets.allSatisfy { $0.loadKg == 20 })
}

// ---------------------------------------------------------------------------
// 9. enterRest · sets restEndsAt = now + durationSec.
// ---------------------------------------------------------------------------
runCase("enterRest · sets restEndsAt = now + 180") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var s = SessionReducer.reduce(makeBaselineState(), .start)
    s = SessionReducer.reduce(s, .enterRest(durationSec: 180, now: now))
    try expectEqual(s.route, .rest)
    try expectEqual(s.restEndsAt, now.addingTimeInterval(180))
}

runCase("extendRest · adds recovery time to an active rest window") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var s = SessionReducer.reduce(makeBaselineState(), .start)
    s = SessionReducer.reduce(s, .enterRest(durationSec: 180, now: now))
    s = SessionReducer.reduce(s, .extendRest(durationSec: 30))
    try expectEqual(s.route, .rest)
    try expectEqual(s.restEndsAt, now.addingTimeInterval(210))
}

runCase("extendRest · no-ops outside rest") {
    let s0 = SessionReducer.reduce(makeBaselineState(), .start)
    let s1 = SessionReducer.reduce(s0, .extendRest(durationSec: 30))
    try expectEqual(s1, s0)
}

runCase("extendRest · ignores non-positive durations") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var s = SessionReducer.reduce(makeBaselineState(), .start)
    s = SessionReducer.reduce(s, .enterRest(durationSec: 180, now: now))
    let zero = SessionReducer.reduce(s, .extendRest(durationSec: 0))
    let negative = SessionReducer.reduce(s, .extendRest(durationSec: -30))
    try expectEqual(zero, s)
    try expectEqual(negative, s)
}

// ---------------------------------------------------------------------------
// 10. advanceFromRest · last set of last item of last block → complete,
//     restEndsAt = nil.
// ---------------------------------------------------------------------------
runCase("advanceFromRest · last-set-last-item-last-block → .complete, restEndsAt=nil") {
    // Build a one-block, one-item, one-set state with cursor on that set
    // and restEndsAt set.
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let s0 = SessionState(
        workoutID: workoutID,
        route: .rest,
        cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
        items: [
            SessionState.ItemLog(
                itemID: itemA,
                sets: [SetPlan(setIndex: 1, loadKg: 100, reps: 5, done: true, adjust: nil, rir: 2)]
            )
        ],
        restEndsAt: now.addingTimeInterval(60),
        note: "",
        structure: SessionState.Structure(itemsPerBlock: [1], setsPerItem: [[1]])
    )
    let s1 = SessionReducer.reduce(s0, .advanceFromRest)
    try expectEqual(s1.route, .complete)
    try expectEqual(s1.restEndsAt, nil)
}

// ---------------------------------------------------------------------------
// 11. advanceFromRest · intermediate set → cursor advances, route=.active,
//     restEndsAt=nil.
// ---------------------------------------------------------------------------
runCase("advanceFromRest · intermediate set → cursor.setIndex advances, route=.active") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var s = makeBaselineState()
    s.route = .rest
    s.restEndsAt = now.addingTimeInterval(60)
    // cursor is (0, 0, 1) — advance should go to (0, 0, 2)
    let s1 = SessionReducer.reduce(s, .advanceFromRest)
    try expectEqual(s1.route, .active)
    try expectEqual(s1.cursor.setIndex, 2)
    try expectEqual(s1.cursor.itemIndex, 0)
    try expectEqual(s1.cursor.blockIndex, 0)
    try expectEqual(s1.restEndsAt, nil)
}

runCase("advanceFromRest · last set of current item → next item, setIndex=1") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var s = makeBaselineState()
    s.route = .rest
    s.restEndsAt = now.addingTimeInterval(60)
    // move cursor to last set of first item (item 0, set 3)
    s.cursor = SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 3)
    let s1 = SessionReducer.reduce(s, .advanceFromRest)
    try expectEqual(s1.cursor.itemIndex, 1)
    try expectEqual(s1.cursor.setIndex, 1)
    try expectEqual(s1.cursor.blockIndex, 0)
    try expectEqual(s1.route, .active)
}

// ---------------------------------------------------------------------------
// 12. save · returns pristine state with route=.today, sets un-done.
// ---------------------------------------------------------------------------
runCase("save · returns pristine state with route=.today, note cleared, sets fresh") {
    var s = makeBaselineState()
    s = SessionReducer.reduce(s, .start)
    s = SessionReducer.reduce(
        s,
        .logSet(itemID: itemA, setIndex: 1, loggedReps: 5, loggedRir: 2, now: logSetStamp)
    )
    s = SessionReducer.reduce(s, .appendNote("felt good"))
    s = SessionReducer.reduce(s, .holdAutoreg(itemID: itemA))

    let freshItems = [
        SessionState.ItemLog(itemID: itemA, autoregHeld: false, sets: pristineSets()),
        SessionState.ItemLog(itemID: itemB, autoregHeld: false, sets: pristineSets()),
    ]
    let freshStructure = SessionState.Structure(
        itemsPerBlock: [2],
        setsPerItem: [[3, 3]]
    )
    let s1 = SessionReducer.reduce(
        s,
        .save(freshItems: freshItems, freshStructure: freshStructure)
    )

    try expectEqual(s1.route, .today)
    try expectEqual(s1.note, "")
    try expectEqual(s1.restEndsAt, nil)
    try expectEqual(s1.cursor.blockIndex, 0)
    try expectEqual(s1.cursor.itemIndex, 0)
    try expectEqual(s1.cursor.setIndex, 1)
    try expectEqual(s1.workoutID, workoutID, "workoutID preserved")
    try expectEqual(s1.items[0].sets[0].done, false, "fresh sets un-done")
    try expectEqual(s1.items[0].autoregHeld, false, "hold cleared")
}

// ---------------------------------------------------------------------------
// 13. appendNote · concatenates with newline separator.
// ---------------------------------------------------------------------------
runCase("appendNote · first append replaces empty; subsequent appends add newline") {
    var s = makeBaselineState()
    try expectEqual(s.note, "")
    s = SessionReducer.reduce(s, .appendNote("felt strong"))
    try expectEqual(s.note, "felt strong")
    s = SessionReducer.reduce(s, .appendNote("left shoulder twinge"))
    try expectEqual(s.note, "felt strong\nleft shoulder twinge")
}

runCase("appendNote · empty input is a no-op") {
    var s = makeBaselineState()
    s = SessionReducer.reduce(s, .appendNote("start"))
    s = SessionReducer.reduce(s, .appendNote(""))
    try expectEqual(s.note, "start")
}

// ---------------------------------------------------------------------------
// 14. Unknown-item mutations are no-ops.
// ---------------------------------------------------------------------------
runCase("no-op · logSet with unknown itemID leaves state unchanged") {
    let unknown = UUID()
    let s0 = SessionReducer.reduce(makeBaselineState(), .start)
    let s1 = SessionReducer.reduce(
        s0,
        .logSet(itemID: unknown, setIndex: 1, loggedReps: 5, loggedRir: 2, now: logSetStamp)
    )
    try expectEqual(s0, s1)
}

runCase("no-op · logSet with unknown setIndex leaves state unchanged") {
    let s0 = SessionReducer.reduce(makeBaselineState(), .start)
    let s1 = SessionReducer.reduce(
        s0,
        .logSet(itemID: itemA, setIndex: 99, loggedReps: 5, loggedRir: 2, now: logSetStamp)
    )
    try expectEqual(s0, s1)
}

runCase("no-op · holdAutoreg / swap / editPendingSet with unknown itemID unchanged") {
    let unknown = UUID()
    let s0 = SessionReducer.reduce(makeBaselineState(), .start)
    let s1 = SessionReducer.reduce(s0, .holdAutoreg(itemID: unknown))
    try expectEqual(s0, s1)
    let s2 = SessionReducer.reduce(s0, .swap(itemID: unknown, toExerciseID: exerciseAlt))
    try expectEqual(s0, s2)
    let s3 = SessionReducer.reduce(
        s0,
        .editPendingSet(itemID: unknown, setIndex: 1, loadKg: 50, reps: 5, rir: nil, startedAt: nil)
    )
    try expectEqual(s0, s3)
}

// ---------------------------------------------------------------------------
// Bonus: editPastSet on a pending set is a no-op (wrong mutation path);
//        editPendingSet on a done set is a no-op.
// ---------------------------------------------------------------------------
runCase("no-op · editPastSet on pending set unchanged") {
    let s0 = SessionReducer.reduce(makeBaselineState(), .start)
    let s1 = SessionReducer.reduce(
        s0,
        .editPastSet(itemID: itemA, setIndex: 1, loadKg: 999, reps: 99, rir: 5)
    )
    try expectEqual(s0, s1)
}

runCase("no-op · editPendingSet on done set unchanged") {
    var s = SessionReducer.reduce(makeBaselineState(), .start)
    s = SessionReducer.reduce(
        s,
        .logSet(itemID: itemA, setIndex: 1, loggedReps: 5, loggedRir: 2, now: logSetStamp)
    )
    let s1 = SessionReducer.reduce(
        s,
        .editPendingSet(itemID: itemA, setIndex: 1, loadKg: 999, reps: 99, rir: nil, startedAt: nil)
    )
    try expectEqual(s, s1)
}

// ---------------------------------------------------------------------------
// 15. complete · route → .complete; state otherwise preserved.
// ---------------------------------------------------------------------------
runCase("complete · route flips to .complete, log preserved") {
    var s = makeBaselineState()
    s = SessionReducer.reduce(s, .start)
    s = SessionReducer.reduce(
        s,
        .logSet(itemID: itemA, setIndex: 1, loggedReps: 5, loggedRir: 2, now: logSetStamp)
    )
    let s1 = SessionReducer.reduce(s, .complete)
    try expectEqual(s1.route, .complete)
    try expectEqual(s1.items[0].sets[0].done, true)
    try expectEqual(s1.items[0].sets[0].reps, 5)
}

// ---------------------------------------------------------------------------
// 16. advanceFromRest · last set of a work block → next block is zero-item
//     (standalone rest) → cursor LANDS on the rest block (blockIndex+1,
//     itemIndex=0, setIndex=1). The view model reroutes to `.rest` on
//     arrival — the reducer itself sets route=.active here. This matches
//     the Decision A1 cursor model documented in `RestBlockDriver`.
// ---------------------------------------------------------------------------
runCase("advanceFromRest · last set of work block → cursor lands on zero-item rest block") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    // Work block (1 item, 2 sets) → rest block (zero items) → work block
    // (1 item, 2 sets). Cursor on block 0 last set.
    let s0 = SessionState(
        workoutID: workoutID,
        route: .rest,
        cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 2),
        items: [
            SessionState.ItemLog(
                itemID: itemA,
                sets: [
                    SetPlan(setIndex: 1, loadKg: 100, reps: 5, done: true, adjust: nil, rir: 2),
                    SetPlan(setIndex: 2, loadKg: 100, reps: 5, done: true, adjust: nil, rir: 2),
                ]
            ),
            SessionState.ItemLog(
                itemID: itemB,
                sets: [
                    SetPlan(setIndex: 1, loadKg: 60, reps: 8, done: false, adjust: nil, rir: nil),
                    SetPlan(setIndex: 2, loadKg: 60, reps: 8, done: false, adjust: nil, rir: nil),
                ]
            ),
        ],
        restEndsAt: now.addingTimeInterval(60),
        note: "",
        structure: SessionState.Structure(
            itemsPerBlock: [1, 0, 1],
            setsPerItem: [[2], [], [2]]
        )
    )
    let s1 = SessionReducer.reduce(s0, .advanceFromRest)
    // Lands on the rest block (b=1), not skipped.
    try expectEqual(s1.cursor.blockIndex, 1)
    try expectEqual(s1.cursor.itemIndex, 0)
    try expectEqual(s1.cursor.setIndex, 1)
    // The reducer does not know about "rest block" — it sets route=.active
    // on every advance that produces a new cursor. The ExecutionViewModel
    // re-flips to `.rest` on zero-item landings (see `RestBlockDriver`).
    try expectEqual(s1.route, .active)
    try expectEqual(s1.restEndsAt, nil)
}

// ---------------------------------------------------------------------------
// 17. advanceFromRest · FROM a zero-item rest block → next work block.
// ---------------------------------------------------------------------------
runCase("advanceFromRest · from zero-item rest block → next block, setIndex=1") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    // Same 3-block structure; cursor is currently on the rest block.
    let s0 = SessionState(
        workoutID: workoutID,
        route: .rest,
        cursor: SessionState.Cursor(blockIndex: 1, itemIndex: 0, setIndex: 1),
        items: [
            SessionState.ItemLog(
                itemID: itemA,
                sets: [SetPlan(setIndex: 1, loadKg: 100, reps: 5, done: true, adjust: nil, rir: 2)]
            ),
            SessionState.ItemLog(
                itemID: itemB,
                sets: [SetPlan(setIndex: 1, loadKg: 60, reps: 8, done: false, adjust: nil, rir: nil)]
            ),
        ],
        restEndsAt: now.addingTimeInterval(30),
        note: "",
        structure: SessionState.Structure(
            itemsPerBlock: [1, 0, 1],
            setsPerItem: [[1], [], [1]]
        )
    )
    let s1 = SessionReducer.reduce(s0, .advanceFromRest)
    try expectEqual(s1.cursor.blockIndex, 2)
    try expectEqual(s1.cursor.itemIndex, 0)
    try expectEqual(s1.cursor.setIndex, 1)
    try expectEqual(s1.route, .active)
    try expectEqual(s1.restEndsAt, nil)
}

// ---------------------------------------------------------------------------
// 18. advanceFromRest · FROM a zero-item rest block that is the LAST block
//     → complete.
// ---------------------------------------------------------------------------
runCase("advanceFromRest · from trailing zero-item rest block → .complete") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let s0 = SessionState(
        workoutID: workoutID,
        route: .rest,
        cursor: SessionState.Cursor(blockIndex: 1, itemIndex: 0, setIndex: 1),
        items: [
            SessionState.ItemLog(
                itemID: itemA,
                sets: [SetPlan(setIndex: 1, loadKg: 100, reps: 5, done: true, adjust: nil, rir: 2)]
            ),
        ],
        restEndsAt: now.addingTimeInterval(30),
        note: "",
        structure: SessionState.Structure(
            itemsPerBlock: [1, 0],
            setsPerItem: [[1], []]
        )
    )
    let s1 = SessionReducer.reduce(s0, .advanceFromRest)
    try expectEqual(s1.route, .complete)
    try expectEqual(s1.restEndsAt, nil)
}

// ---------------------------------------------------------------------------
// 19. advanceFromRest · round-robin mode — after logging an item, cursor
//     moves to the NEXT item in the same round (setIndex unchanged).
//     Used by circuit / superset / amrap / emom / forTime / tabata.
// ---------------------------------------------------------------------------
runCase("advanceFromRest · round-robin: (item 0, round 1) → (item 1, round 1)") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    // 3 items × 3 rounds circuit. Cursor at item 0, round 1.
    let s0 = SessionState(
        workoutID: workoutID,
        route: .rest,
        cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
        items: [
            SessionState.ItemLog(itemID: UUID(), sets: pristineSets(count: 3)),
            SessionState.ItemLog(itemID: UUID(), sets: pristineSets(count: 3)),
            SessionState.ItemLog(itemID: UUID(), sets: pristineSets(count: 3)),
        ],
        restEndsAt: now.addingTimeInterval(30),
        note: "",
        structure: SessionState.Structure(
            itemsPerBlock: [3],
            setsPerItem: [[3, 3, 3]],
            advancementByBlock: [.roundRobin]
        )
    )
    let s1 = SessionReducer.reduce(s0, .advanceFromRest)
    try expectEqual(s1.cursor.blockIndex, 0)
    try expectEqual(s1.cursor.itemIndex, 1, "next item in same round")
    try expectEqual(s1.cursor.setIndex, 1, "same round")
    try expectEqual(s1.route, .active)
}

// ---------------------------------------------------------------------------
// 20. advanceFromRest · round-robin mode — last item of round N → first
//     item of round N+1 (setIndex bumps).
// ---------------------------------------------------------------------------
runCase("advanceFromRest · round-robin: (last item, round N) → (item 0, round N+1)") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    // 2 items × 3 rounds superset. Cursor at item 1 (last), round 2.
    let s0 = SessionState(
        workoutID: workoutID,
        route: .rest,
        cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 1, setIndex: 2),
        items: [
            SessionState.ItemLog(itemID: UUID(), sets: pristineSets(count: 3)),
            SessionState.ItemLog(itemID: UUID(), sets: pristineSets(count: 3)),
        ],
        restEndsAt: now.addingTimeInterval(120),
        note: "",
        structure: SessionState.Structure(
            itemsPerBlock: [2],
            setsPerItem: [[3, 3]],
            advancementByBlock: [.roundRobin]
        )
    )
    let s1 = SessionReducer.reduce(s0, .advanceFromRest)
    try expectEqual(s1.cursor.itemIndex, 0, "wrap to first item")
    try expectEqual(s1.cursor.setIndex, 3, "bump round")
    try expectEqual(s1.route, .active)
}

// ---------------------------------------------------------------------------
// 21. advanceFromRest · round-robin mode — last item of last round →
//     complete (no next block).
// ---------------------------------------------------------------------------
runCase("advanceFromRest · round-robin: last item of last round → .complete") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let s0 = SessionState(
        workoutID: workoutID,
        route: .rest,
        cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 1, setIndex: 3),
        items: [
            SessionState.ItemLog(itemID: UUID(), sets: pristineSets(count: 3)),
            SessionState.ItemLog(itemID: UUID(), sets: pristineSets(count: 3)),
        ],
        restEndsAt: now.addingTimeInterval(30),
        note: "",
        structure: SessionState.Structure(
            itemsPerBlock: [2],
            setsPerItem: [[3, 3]],
            advancementByBlock: [.roundRobin]
        )
    )
    let s1 = SessionReducer.reduce(s0, .advanceFromRest)
    try expectEqual(s1.route, .complete)
}

// ---------------------------------------------------------------------------
// 22. advanceFromRest · set-major preserves legacy straight-sets walk
//     (item 0 set 1 → item 0 set 2, ..., item 0 set N → item 1 set 1).
// ---------------------------------------------------------------------------
runCase("advanceFromRest · set-major: (item 0, set N) → (item 1, set 1)") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var s = makeBaselineState()
    s.route = .rest
    s.restEndsAt = now.addingTimeInterval(60)
    s.cursor = SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 3)
    // makeBaselineState defaults to `.setMajor` via the structure
    // default; verify by leaving advancementByBlock unspecified.
    let s1 = SessionReducer.reduce(s, .advanceFromRest)
    try expectEqual(s1.cursor.itemIndex, 1)
    try expectEqual(s1.cursor.setIndex, 1)
}

// ---------------------------------------------------------------------------
// 23. advanceFromRest · blockEndsAt / workEndsAt cleared on block change.
// ---------------------------------------------------------------------------
runCase("advanceFromRest · blockEndsAt+workEndsAt cleared on block change") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    // Two blocks — block 0 (1 item, 1 set) with both timers set, then
    // block 1 (1 item, 1 set). After advancing from block 0's last set,
    // the cursor should land on block 1 and both timers should be cleared.
    let s0 = SessionState(
        workoutID: workoutID,
        route: .rest,
        cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
        items: [
            SessionState.ItemLog(
                itemID: itemA,
                sets: [SetPlan(setIndex: 1, loadKg: 0, reps: 0, done: true, adjust: nil, rir: nil)]
            ),
            SessionState.ItemLog(
                itemID: itemB,
                sets: [SetPlan(setIndex: 1, loadKg: 0, reps: 0, done: false, adjust: nil, rir: nil)]
            ),
        ],
        restEndsAt: now.addingTimeInterval(30),
        blockEndsAt: now.addingTimeInterval(600),
        workEndsAt: now.addingTimeInterval(20),
        note: "",
        structure: SessionState.Structure(
            itemsPerBlock: [1, 1],
            setsPerItem: [[1], [1]]
        )
    )
    let s1 = SessionReducer.reduce(s0, .advanceFromRest)
    try expectEqual(s1.cursor.blockIndex, 1, "landed on next block")
    try expectEqual(s1.blockEndsAt, nil, "blockEndsAt cleared on block change")
    try expectEqual(s1.workEndsAt, nil, "workEndsAt cleared on block change")
}

// ---------------------------------------------------------------------------
// 24. enterRest · clears workEndsAt (Tabata's 20s window ended).
// ---------------------------------------------------------------------------
runCase("enterRest · clears workEndsAt") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var s = SessionReducer.reduce(makeBaselineState(), .start)
    s.workEndsAt = now.addingTimeInterval(20)
    s = SessionReducer.reduce(s, .enterRest(durationSec: 10, now: now))
    try expectEqual(s.workEndsAt, nil)
    try expectEqual(s.restEndsAt, now.addingTimeInterval(10))
}

// ---------------------------------------------------------------------------
// 25. advanceFromRest · intervalAnchorAt cleared on block change. The EMOM
//     interval grid is a per-block anchor — crossing a block boundary must
//     clear it so the next block's `enterBlockTimerIfNeeded` can re-stamp
//     a fresh anchor (or leave it nil for non-EMOM blocks).
// ---------------------------------------------------------------------------
runCase("advanceFromRest · intervalAnchorAt cleared on block change") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let s0 = SessionState(
        workoutID: workoutID,
        route: .rest,
        cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
        items: [
            SessionState.ItemLog(
                itemID: itemA,
                sets: [SetPlan(setIndex: 1, loadKg: 0, reps: 0, done: true, adjust: nil, rir: nil)]
            ),
            SessionState.ItemLog(
                itemID: itemB,
                sets: [SetPlan(setIndex: 1, loadKg: 0, reps: 0, done: false, adjust: nil, rir: nil)]
            ),
        ],
        restEndsAt: now.addingTimeInterval(30),
        blockEndsAt: now.addingTimeInterval(600),
        workEndsAt: nil,
        intervalAnchorAt: now,
        note: "",
        structure: SessionState.Structure(
            itemsPerBlock: [1, 1],
            setsPerItem: [[1], [1]]
        )
    )
    let s1 = SessionReducer.reduce(s0, .advanceFromRest)
    try expectEqual(s1.cursor.blockIndex, 1, "landed on next block")
    try expectEqual(s1.intervalAnchorAt, nil, "intervalAnchorAt cleared on block change")
}

// ---------------------------------------------------------------------------
// 26. advanceFromRest · intervalAnchorAt preserved WITHIN a block. A round-
//     robin EMOM walks items/rounds in the same block — the anchor must
//     survive all those intra-block advances so boundaries stay pinned to
//     the original block-start instant. Only a block CHANGE clears it.
// ---------------------------------------------------------------------------
runCase("advanceFromRest · intervalAnchorAt preserved on intra-block advance") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let anchor = now
    let s0 = SessionState(
        workoutID: workoutID,
        route: .rest,
        cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
        items: [
            SessionState.ItemLog(itemID: itemA, sets: pristineSets(count: 3)),
            SessionState.ItemLog(itemID: itemB, sets: pristineSets(count: 3)),
        ],
        restEndsAt: now.addingTimeInterval(30),
        blockEndsAt: now.addingTimeInterval(600),
        workEndsAt: nil,
        intervalAnchorAt: anchor,
        note: "",
        structure: SessionState.Structure(
            itemsPerBlock: [2],
            setsPerItem: [[3, 3]],
            advancementByBlock: [.roundRobin]
        )
    )
    let s1 = SessionReducer.reduce(s0, .advanceFromRest)
    try expectEqual(s1.cursor.itemIndex, 1, "moved to next item in same round")
    try expectEqual(s1.intervalAnchorAt, anchor, "anchor preserved inside a block")
    try expectEqual(s1.blockEndsAt, now.addingTimeInterval(600), "blockEndsAt preserved inside a block")
}

// ---------------------------------------------------------------------------
// 27. save · clears intervalAnchorAt alongside blockEndsAt / workEndsAt.
// ---------------------------------------------------------------------------
runCase("save · clears intervalAnchorAt") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var s = makeBaselineState()
    s = SessionReducer.reduce(s, .start)
    s.intervalAnchorAt = now
    s.blockEndsAt = now.addingTimeInterval(600)
    let freshItems = [
        SessionState.ItemLog(itemID: itemA, autoregHeld: false, sets: pristineSets()),
        SessionState.ItemLog(itemID: itemB, autoregHeld: false, sets: pristineSets()),
    ]
    let freshStructure = SessionState.Structure(
        itemsPerBlock: [2],
        setsPerItem: [[3, 3]]
    )
    let s1 = SessionReducer.reduce(
        s,
        .save(freshItems: freshItems, freshStructure: freshStructure)
    )
    try expectEqual(s1.intervalAnchorAt, nil)
    try expectEqual(s1.blockEndsAt, nil)
    try expectEqual(s1.workEndsAt, nil)
}

// ---------------------------------------------------------------------------
// 28. qa-041 · crossing a block boundary into a roundRobin block must re-read
//      advancementByBlock[newBlockIndex]. Regression test: straight-sets block
//      (setMajor) followed by a superset block (roundRobin). After completing
//      block 0, the cursor must alternate items within block 1, not continue
//      with setMajor semantics that leave it stuck on the last item.
// ---------------------------------------------------------------------------
runCase("advanceFromRest · block transition from setMajor to roundRobin honors new mode") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let blockAItem = UUID()
    let supersetItem0 = UUID()
    let supersetItem1 = UUID()
    // Block 0: 1 item × 2 sets (straight sets).
    // Block 1: 2 items × 2 rounds (superset / round-robin).
    let s0 = SessionState(
        workoutID: workoutID,
        route: .active,
        cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
        items: [
            SessionState.ItemLog(itemID: blockAItem, sets: pristineSets(count: 2)),
            SessionState.ItemLog(itemID: supersetItem0, sets: pristineSets(count: 2)),
            SessionState.ItemLog(itemID: supersetItem1, sets: pristineSets(count: 2)),
        ],
        restEndsAt: nil,
        note: "",
        structure: SessionState.Structure(
            itemsPerBlock: [1, 2],
            setsPerItem: [[2], [2, 2]],
            advancementByBlock: [.setMajor, .roundRobin]
        )
    )

    // Walk block 0: log set 1, advance → (0,0,2); log set 2, advance → (1,0,1).
    var s = SessionReducer.reduce(
        s0,
        .logSet(itemID: blockAItem, setIndex: 1, loggedReps: 5, loggedRir: 2, now: now)
    )
    s = SessionReducer.reduce(s, .advanceFromRest)
    try expectEqual(s.cursor.blockIndex, 0, "still in block 0 after first set")
    try expectEqual(s.cursor.itemIndex, 0)
    try expectEqual(s.cursor.setIndex, 2)

    s = SessionReducer.reduce(
        s,
        .logSet(itemID: blockAItem, setIndex: 2, loggedReps: 5, loggedRir: 2, now: now)
    )
    s = SessionReducer.reduce(s, .advanceFromRest)
    try expectEqual(s.cursor.blockIndex, 1, "crossed into block 1")
    try expectEqual(s.cursor.itemIndex, 0, "landed on first item of new block")
    try expectEqual(s.cursor.setIndex, 1, "first round of new block")

    // Block 1 round 1: log item 0 → advance must go to item 1 (round-robin).
    s = SessionReducer.reduce(
        s,
        .logSet(itemID: supersetItem0, setIndex: 1, loggedReps: 10, loggedRir: 2, now: now)
    )
    s = SessionReducer.reduce(s, .advanceFromRest)
    try expectEqual(s.cursor.blockIndex, 1)
    try expectEqual(s.cursor.itemIndex, 1, "round-robin moved to item 1 in same round")
    try expectEqual(s.cursor.setIndex, 1, "still round 1")

    // Log item 1 → advance must alternate back to item 0, round 2.
    s = SessionReducer.reduce(
        s,
        .logSet(itemID: supersetItem1, setIndex: 1, loggedReps: 10, loggedRir: 2, now: now)
    )
    s = SessionReducer.reduce(s, .advanceFromRest)
    try expectEqual(s.cursor.blockIndex, 1)
    try expectEqual(
        s.cursor.itemIndex, 0,
        "round-robin alternates back to item 0 at the round boundary — qa-041 regression"
    )
    try expectEqual(s.cursor.setIndex, 2, "round bumped to 2")
}

reportAndExit()
