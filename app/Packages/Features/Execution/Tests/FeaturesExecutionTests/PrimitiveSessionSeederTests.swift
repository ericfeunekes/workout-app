import XCTest
import CoreDomain
import CoreSession
import FeaturesExecution

final class PrimitiveSessionSeederTests: XCTestCase {
    func testSeedsEveryLegalTimingTraversalCell() throws {
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
            let workout = Self.workout(
                setID: Self.uuid(0x3000 + index),
                timing: entry.0,
                traversal: entry.1,
                setTargets: entry.2
            )

            let plan = try PrimitiveSessionSeeder.seed(workout: workout)

            XCTAssertEqual(plan.blocks[0].sets[0].timing, entry.0, "case \(index)")
            XCTAssertEqual(plan.blocks[0].sets[0].traversal, entry.1, "case \(index)")
        }
    }

    func testRejectsIllegalTimingTraversalCells() {
        let setBoundedAMRAP = Self.workout(
            setID: Self.uuid(0x3011),
            timing: .init(mode: .setBounded),
            traversal: .amrap
        )
        XCTAssertThrowsError(try PrimitiveSessionSeeder.seed(workout: setBoundedAMRAP)) { error in
            XCTAssertEqual(error as? PrimitiveSessionSeedError, .illegalRuntimeCell(setID: Self.uuid(0x3011)))
        }

        let targetBoundedAMRAP = Self.workout(
            setID: Self.uuid(0x3012),
            timing: .init(mode: .targetBounded),
            traversal: .amrap
        )
        XCTAssertThrowsError(try PrimitiveSessionSeeder.seed(workout: targetBoundedAMRAP)) { error in
            XCTAssertEqual(error as? PrimitiveSessionSeedError, .illegalRuntimeCell(setID: Self.uuid(0x3012)))
        }
    }

    func testRejectsMalformedTimedCells() {
        let missingInterval = Self.workout(
            setID: Self.uuid(0x3013),
            timing: .init(mode: .timeBounded, rounds: 3),
            traversal: .sequential
        )
        XCTAssertThrowsError(try PrimitiveSessionSeeder.seed(workout: missingInterval)) { error in
            XCTAssertEqual(error as? PrimitiveSessionSeedError, .invalidTiming(setID: Self.uuid(0x3013)))
        }

        let missingCap = Self.workout(
            setID: Self.uuid(0x3014),
            timing: .init(mode: .capBounded),
            traversal: .sequential,
            setTargets: [.init(metric: .duration, valueForm: .open, role: .observation)]
        )
        XCTAssertThrowsError(try PrimitiveSessionSeeder.seed(workout: missingCap)) { error in
            XCTAssertEqual(error as? PrimitiveSessionSeedError, .invalidTiming(setID: Self.uuid(0x3014)))
        }

        let amrapWithoutRoundsTarget = Self.workout(
            setID: Self.uuid(0x3015),
            timing: .init(mode: .capBounded, capSec: 300),
            traversal: .amrap
        )
        XCTAssertThrowsError(try PrimitiveSessionSeeder.seed(workout: amrapWithoutRoundsTarget)) { error in
            XCTAssertEqual(error as? PrimitiveSessionSeedError, .invalidTiming(setID: Self.uuid(0x3015)))
        }

        let capSequentialWithoutDurationTarget = Self.workout(
            setID: Self.uuid(0x3016),
            timing: .init(mode: .capBounded, capSec: 300),
            traversal: .sequential
        )
        XCTAssertThrowsError(try PrimitiveSessionSeeder.seed(workout: capSequentialWithoutDurationTarget)) { error in
            XCTAssertEqual(error as? PrimitiveSessionSeedError, .invalidTiming(setID: Self.uuid(0x3016)))
        }
    }

    func testLoadResolutionCoversAbsoluteRelativeImplicitAndCarriedLoad() throws {
        let exerciseID = Self.uuid(0x5001)
        let workout = PrimitiveWorkout(
            id: Self.uuid(0x1001),
            name: "Loads",
            blocks: [
                PrimitiveBlock(id: Self.uuid(0x2001), sets: [
                    PrimitiveSet(
                        id: Self.uuid(0x3001),
                        timing: .init(mode: .setBounded),
                        slots: [
                            PrimitiveSlot(
                                id: Self.uuid(0x4001),
                                exerciseID: exerciseID,
                                workTargets: [.init(metric: .reps, valueForm: .single, value: 5, role: .completion)],
                                load: .init(value: 100, unit: .kg, unitType: .absolute)
                            ),
                            PrimitiveSlot(
                                id: Self.uuid(0x4002),
                                exerciseID: exerciseID,
                                workTargets: [.init(metric: .reps, valueForm: .single, value: 5, role: .completion)],
                                load: .init(value: 200, unit: .lb, unitType: .absolute)
                            ),
                            PrimitiveSlot(
                                id: Self.uuid(0x4003),
                                exerciseID: exerciseID,
                                workTargets: [.init(metric: .reps, valueForm: .single, value: 5, role: .completion)],
                                load: .init(value: 0.8, unit: .oneRepMax, unitType: .relative)
                            ),
                            PrimitiveSlot(
                                id: Self.uuid(0x4004),
                                exerciseID: exerciseID,
                                workTargets: [.init(metric: .reps, valueForm: .single, value: 5, role: .completion)],
                                load: .init(value: 1.25, unit: .bodyweight, unitType: .relative)
                            ),
                            PrimitiveSlot(
                                id: Self.uuid(0x4005),
                                exerciseID: exerciseID,
                                workTargets: [.init(metric: .completion, valueForm: .open, role: .completion)],
                                load: .init(unit: .bodyweight, unitType: .implicitBodyweight)
                            ),
                            PrimitiveSlot(
                                id: Self.uuid(0x4006),
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

        let plan = try PrimitiveSessionSeeder.seed(
            workout: workout,
            userParameters: [
                "one_rep_max_\(exerciseID.uuidString.lowercased())_kg": 150,
                "bodyweight_kg": 80,
            ]
        )
        let slots = plan.blocks[0].sets[0].slots

        XCTAssertEqual(slots[0].loadKg, 100)
        XCTAssertEqual(slots[0].loadUnit, .kg)
        XCTAssertEqual(try XCTUnwrap(slots[1].loadKg), 90.718474, accuracy: 0.000001)
        XCTAssertEqual(slots[1].loadUnit, .lb)
        XCTAssertEqual(slots[2].loadKg, 120)
        XCTAssertEqual(slots[2].loadUnit, .kg)
        XCTAssertEqual(slots[3].loadKg, 100)
        XCTAssertEqual(slots[3].loadUnit, .kg)
        XCTAssertNil(slots[4].loadKg)
        XCTAssertNil(slots[4].loadUnit)
        XCTAssertEqual(slots[5].workTargets.map(\.metric), [.distance, .loadCarried])
        XCTAssertEqual(try XCTUnwrap(slots[5].loadKg), 27.2155422, accuracy: 0.000001)
    }

    func testMetricRolePreservesNonRepSlotResults() throws {
        let workout = Self.workout(
            setID: Self.uuid(0x3020),
            timing: .init(mode: .setBounded),
            traversal: .sequential,
            slotTargets: [
                .init(metric: .distance, valueForm: .single, value: 1_000, role: .completion),
                .init(metric: .duration, valueForm: .open, role: .observation),
                .init(metric: .loadCarried, valueForm: .single, value: 60, role: .observation),
            ],
            load: .init(value: 60, unit: .lb, unitType: .absolute)
        )
        let plan = try PrimitiveSessionSeeder.seed(workout: workout)
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

        XCTAssertEqual(slot.workTargets.map(\.role), [.completion, .observation, .observation])
        XCTAssertEqual(log.role, .slot)
        XCTAssertEqual(log.distanceM, 1_000)
        XCTAssertEqual(log.durationSec, 360)
        XCTAssertNil(log.reps)
        XCTAssertEqual(try XCTUnwrap(log.weight), 60, accuracy: 0.000001)
        XCTAssertEqual(log.weightUnit, .lb)
    }

    func testResultIdentityAndRepeatCoordinatesAreDeterministic() throws {
        let workout = Self.workout(
            setID: Self.uuid(0x3030),
            timing: .init(mode: .capBounded, capSec: 300),
            traversal: .amrap,
            setTargets: [.init(metric: .rounds, valueForm: .open, role: .observation)]
        )
        let plan = try PrimitiveSessionSeeder.seed(workout: workout)
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
        let next = slot.slotLog(
            workoutID: workout.id,
            blockRepeatIndex: 1,
            setRepeatIndex: 2,
            setIndex: 4,
            reps: 10,
            rir: 2,
            completedAt: completedAt
        )
        let aggregate = PrimitiveSessionSeeder.setResultLog(
            plan: plan,
            blockIndex: 0,
            setIndexInBlock: 0,
            blockRepeatIndex: 1,
            setRepeatIndex: 2,
            reps: 4,
            rounds: 7,
            durationSec: 300,
            completedAt: completedAt
        )

        XCTAssertEqual(first.id, same.id, "same coordinate is a same-UUID correction target")
        XCTAssertNotEqual(first.id, next.id)
        XCTAssertNotEqual(first.id, aggregate.id)
        XCTAssertEqual(aggregate.role, .setResult)
        XCTAssertEqual(aggregate.blockRepeatIndex, 1)
        XCTAssertEqual(aggregate.setRepeatIndex, 2)
        XCTAssertEqual(aggregate.setIndex, 0)
    }

    // MARK: - Fixtures

    private static func workout(
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
            id: uuid(0x1000),
            name: "Primitive",
            blocks: [
                PrimitiveBlock(id: uuid(0x2000), sets: [
                    PrimitiveSet(
                        id: setID,
                        timing: timing,
                        traversal: traversal,
                        workTargets: setTargets,
                        slots: [
                            PrimitiveSlot(
                                id: uuid(0x4000),
                                exerciseID: uuid(0x5000),
                                workTargets: slotTargets,
                                load: load
                            ),
                        ]
                    ),
                ]),
            ]
        )
    }

    private static func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", suffix))!
    }
}
