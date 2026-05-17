import XCTest
import CoreDomain
import FeaturesExecution

final class PrimitiveSessionSeederTests: XCTestCase {
    func testSeedsCapBoundedAMRAPPrimitivePlan() {
        let workoutID = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
        let blockID = UUID(uuidString: "20000000-0000-4000-8000-000000000002")!
        let setID = UUID(uuidString: "30000000-0000-4000-8000-000000000002")!
        let pushupSlot = UUID(uuidString: "40000000-0000-4000-8000-000000000002")!
        let pullupSlot = UUID(uuidString: "40000000-0000-4000-8000-000000000003")!
        let pushup = UUID(uuidString: "50000000-0000-4000-8000-000000000002")!
        let pullup = UUID(uuidString: "50000000-0000-4000-8000-000000000003")!
        let workout = PrimitiveWorkout(
            id: workoutID,
            name: "Primitive AMRAP",
            blocks: [
                PrimitiveBlock(id: blockID, sets: [
                    PrimitiveSet(
                        id: setID,
                        timing: PrimitiveTiming(mode: .capBounded, capSec: 300),
                        traversal: .amrap,
                        workTargets: [
                            PrimitiveWorkTarget(metric: .rounds, valueForm: .open, role: .observation),
                        ],
                        slots: [
                            PrimitiveSlot(
                                id: pushupSlot,
                                exerciseID: pushup,
                                workTargets: [PrimitiveWorkTarget(metric: .reps, valueForm: .single, value: 10, role: .completion)]
                            ),
                            PrimitiveSlot(
                                id: pullupSlot,
                                exerciseID: pullup,
                                workTargets: [PrimitiveWorkTarget(metric: .reps, valueForm: .single, value: 5, role: .completion)]
                            ),
                        ]
                    ),
                ]),
            ]
        )

        let plan = try! PrimitiveSessionSeeder.seed(workout: workout)

        XCTAssertEqual(plan.workoutID, workoutID)
        XCTAssertEqual(plan.blocks[0].sets[0].timing.mode, .capBounded)
        XCTAssertEqual(plan.blocks[0].sets[0].traversal, .amrap)
        XCTAssertEqual(plan.blocks[0].sets[0].workTargets[0].metric, .rounds)
        XCTAssertEqual(plan.blocks[0].sets[0].slots.map(\.slotID), [pushupSlot, pullupSlot])

        let completedAt = Date(timeIntervalSince1970: 1_800)
        let setLog = PrimitiveSessionSeeder.setResultLog(
            plan: plan,
            blockIndex: 0,
            setIndexInBlock: 0,
            blockRepeatIndex: 0,
            setRepeatIndex: 0,
            reps: 4,
            rounds: 7,
            durationSec: 300,
            completedAt: completedAt
        )
        XCTAssertEqual(setLog.role, .setResult)
        XCTAssertEqual(setLog.workoutID, workoutID)
        XCTAssertEqual(setLog.setID, setID)
        XCTAssertEqual(setLog.blockID, blockID)
        XCTAssertEqual(setLog.setIndex, 0)
        XCTAssertEqual(setLog.reps, 4)
        XCTAssertEqual(setLog.rounds, 7)
        XCTAssertEqual(setLog.durationSec, 300)

        let blockLog = PrimitiveSessionSeeder.blockResultLog(
            plan: plan,
            blockIndex: 0,
            blockRepeatIndex: 0,
            durationSec: 300,
            completedAt: completedAt
        )
        XCTAssertEqual(blockLog.role, .blockResult)
        XCTAssertEqual(blockLog.workoutID, workoutID)
        XCTAssertEqual(blockLog.blockID, blockID)
        XCTAssertNil(blockLog.setID)
        XCTAssertEqual(blockLog.setIndex, 0)
        XCTAssertEqual(blockLog.setRepeatIndex, 0)
    }

    func testRejectsUnsupportedRelativeLoadAtSeedTime() {
        let slotID = UUID(uuidString: "40000000-0000-4000-8000-000000000004")!
        let workout = PrimitiveWorkout(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000004")!,
            name: "Relative Load",
            blocks: [
                PrimitiveBlock(id: UUID(uuidString: "20000000-0000-4000-8000-000000000004")!, sets: [
                    PrimitiveSet(
                        id: UUID(uuidString: "30000000-0000-4000-8000-000000000004")!,
                        timing: PrimitiveTiming(mode: .setBounded),
                        slots: [
                            PrimitiveSlot(
                                id: slotID,
                                exerciseID: UUID(uuidString: "50000000-0000-4000-8000-000000000004")!,
                                workTargets: [],
                                load: PrimitiveLoad(value: 0.8, unit: .oneRepMax, unitType: .relative)
                            ),
                        ]
                    ),
                ]),
            ]
        )

        XCTAssertThrowsError(try PrimitiveSessionSeeder.seed(workout: workout)) { error in
            XCTAssertEqual(error as? PrimitiveSessionSeedError, .unsupportedRelativeLoad(slotID: slotID))
        }
    }

    func testRejectsRepeatedAggregateResultSetsForPhaseOneRuntime() {
        let setID = UUID(uuidString: "30000000-0000-4000-8000-000000000005")!
        let workout = PrimitiveWorkout(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000005")!,
            name: "Repeated AMRAP",
            blocks: [
                PrimitiveBlock(id: UUID(uuidString: "20000000-0000-4000-8000-000000000005")!, sets: [
                    PrimitiveSet(
                        id: setID,
                        timing: PrimitiveTiming(mode: .capBounded, capSec: 300),
                        traversal: .amrap,
                        repeatCount: 2,
                        workTargets: [
                            PrimitiveWorkTarget(metric: .rounds, valueForm: .open, role: .observation),
                        ],
                        slots: [
                            PrimitiveSlot(
                                id: UUID(uuidString: "40000000-0000-4000-8000-000000000005")!,
                                exerciseID: UUID(uuidString: "50000000-0000-4000-8000-000000000005")!,
                                workTargets: [
                                    PrimitiveWorkTarget(
                                        metric: .reps,
                                        valueForm: .single,
                                        value: 10,
                                        role: .completion
                                    ),
                                ]
                            ),
                        ]
                    ),
                ]),
            ]
        )

        XCTAssertThrowsError(try PrimitiveSessionSeeder.seed(workout: workout)) { error in
            XCTAssertEqual(error as? PrimitiveSessionSeedError, .illegalRuntimeCell(setID: setID))
        }
    }

    func testRejectsRepeatedBlockDurationAggregateForPhaseOneRuntime() {
        let setID = UUID(uuidString: "30000000-0000-4000-8000-000000000006")!
        let slotID = UUID(uuidString: "40000000-0000-4000-8000-000000000006")!
        let workout = PrimitiveWorkout(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000006")!,
            name: "Repeated For Time",
            blocks: [
                PrimitiveBlock(
                    id: UUID(uuidString: "20000000-0000-4000-8000-000000000006")!,
                    repeatCount: 2,
                    workTargets: [
                        PrimitiveWorkTarget(metric: .duration, valueForm: .open, role: .observation),
                    ],
                    sets: [
                        PrimitiveSet(
                            id: setID,
                            timing: PrimitiveTiming(mode: .setBounded),
                            slots: [
                                PrimitiveSlot(
                                    id: slotID,
                                    exerciseID: UUID(uuidString: "50000000-0000-4000-8000-000000000006")!,
                                    workTargets: [
                                        PrimitiveWorkTarget(
                                            metric: .reps,
                                            valueForm: .single,
                                            value: 10,
                                            role: .completion
                                        ),
                                    ]
                                ),
                            ]
                        ),
                    ]
                ),
            ]
        )

        XCTAssertThrowsError(try PrimitiveSessionSeeder.seed(workout: workout)) { error in
            XCTAssertEqual(error as? PrimitiveSessionSeedError, .illegalRuntimeCell(setID: setID))
        }
    }

    func testRejectsMultipleAggregateResultSetsForPhaseOneRuntime() {
        let firstSetID = UUID(uuidString: "30000000-0000-4000-8000-000000000007")!
        let secondSetID = UUID(uuidString: "30000000-0000-4000-8000-000000000008")!
        let workout = PrimitiveWorkout(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000007")!,
            name: "Two Aggregates",
            blocks: [
                PrimitiveBlock(id: UUID(uuidString: "20000000-0000-4000-8000-000000000007")!, sets: [
                    PrimitiveSet(
                        id: firstSetID,
                        timing: PrimitiveTiming(mode: .capBounded, capSec: 300),
                        traversal: .amrap,
                        workTargets: [
                            PrimitiveWorkTarget(metric: .rounds, valueForm: .open, role: .observation),
                        ],
                        slots: []
                    ),
                    PrimitiveSet(
                        id: secondSetID,
                        timing: PrimitiveTiming(mode: .capBounded, capSec: 300),
                        traversal: .amrap,
                        workTargets: [
                            PrimitiveWorkTarget(metric: .rounds, valueForm: .open, role: .observation),
                        ],
                        slots: []
                    ),
                ]),
            ]
        )

        XCTAssertThrowsError(try PrimitiveSessionSeeder.seed(workout: workout)) { error in
            XCTAssertEqual(error as? PrimitiveSessionSeedError, .illegalRuntimeCell(setID: firstSetID))
        }
    }

    func testRejectsImplicitBodyweightLoadAtSeedTime() {
        let slotID = UUID(uuidString: "40000000-0000-4000-8000-000000000009")!
        let workout = PrimitiveWorkout(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000009")!,
            name: "Bodyweight Load",
            blocks: [
                PrimitiveBlock(id: UUID(uuidString: "20000000-0000-4000-8000-000000000009")!, sets: [
                    PrimitiveSet(
                        id: UUID(uuidString: "30000000-0000-4000-8000-000000000009")!,
                        timing: PrimitiveTiming(mode: .setBounded),
                        slots: [
                            PrimitiveSlot(
                                id: slotID,
                                exerciseID: UUID(uuidString: "50000000-0000-4000-8000-000000000009")!,
                                workTargets: [],
                                load: PrimitiveLoad(
                                    unit: .bodyweight,
                                    unitType: .implicitBodyweight
                                )
                            ),
                        ]
                    ),
                ]),
            ]
        )

        XCTAssertThrowsError(try PrimitiveSessionSeeder.seed(workout: workout)) { error in
            XCTAssertEqual(error as? PrimitiveSessionSeedError, .unsupportedRelativeLoad(slotID: slotID))
        }
    }
}
