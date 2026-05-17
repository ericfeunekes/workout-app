// ExecutionPreviewSeedScenarioTests.swift
//
// Regression coverage for DEBUG simulator QA fixtures. These scenarios
// are launch-arg entry points, so the test only needs to prove the seeded
// workout shape covers the intended timer composition.

#if DEBUG

import XCTest
import CoreDomain
@testable import FeaturesExecution

final class ExecutionPreviewSeedScenarioTests: XCTestCase {

    func testStrengthGauntletComposesRestStraightSupersetAndCircuit() throws {
        let context = try XCTUnwrap(ExecutionPreviewSeed.qaScenario("timer_gauntlet_strength"))

        XCTAssertEqual(context.workout.name, "QA Timer Gauntlet · Strength")
        XCTAssertEqual(context.blocks.map(\.timingMode), [
            .rest,
            .straightSets,
            .superset,
            .circuit,
        ])
        XCTAssertEqual(context.itemsByBlock.map(\.count), [0, 1, 2, 3])
    }

    func testClockedGauntletComposesCapAndIntervalModes() throws {
        let context = try XCTUnwrap(ExecutionPreviewSeed.qaScenario("timer_gauntlet_clocked"))

        XCTAssertEqual(context.blocks.map(\.timingMode), [
            .emom,
            .amrap,
            .forTime,
            .tabata,
        ])
        XCTAssertEqual(context.itemsByBlock.map(\.count), [2, 2, 2, 1])
        XCTAssertEqual(context.blocks[2].roundsRepSchemeJSON, "[21,15,9]")
    }

    func testEnduranceGauntletComposesCardioAndCustomModes() throws {
        let context = try XCTUnwrap(ExecutionPreviewSeed.qaScenario("timer_gauntlet_endurance"))

        XCTAssertEqual(context.blocks.map(\.timingMode), [
            .intervals,
            .continuous,
            .custom,
            .accumulate,
            .rest,
        ])
        XCTAssertEqual(context.itemsByBlock.map(\.count), [1, 1, 1, 1, 0])
    }

    func testPrimitiveScenariosCarryPrimitiveExecutionPlans() throws {
        let scenarioNames = [
            "primitive_strength",
            "primitive_circuit",
            "primitive_for_time",
            "primitive_amrap",
            "primitive_capstone",
            "primitive_capstone_fast",
            "primitive_chipper",
            "primitive_intervals",
            "primitive_carry_circuit",
            "primitive_strength_density",
        ]

        for name in scenarioNames {
            let context = try XCTUnwrap(ExecutionPreviewSeed.qaScenario(name))
            XCTAssertNotNil(context.primitiveWorkout, name)
            XCTAssertNotNil(context.primitiveExecutionPlan, name)
            XCTAssertEqual(context.primitiveWorkout?.id, context.workout.id, name)
            XCTAssertEqual(context.primitiveExecutionPlan?.workoutID, context.workout.id, name)
        }
    }

    func testPrimitiveCapstoneCombinesRepsLoadDistancePaceAndCap() throws {
        let context = try XCTUnwrap(ExecutionPreviewSeed.qaScenario("primitive_capstone"))
        let primitive = try XCTUnwrap(context.primitiveWorkout)
        let block = try XCTUnwrap(primitive.blocks.first)
        let set = try XCTUnwrap(block.sets.first)

        XCTAssertEqual(context.workout.name, "QA Primitive · 20 min Mixed AMRAP")
        XCTAssertEqual(context.blocks.first?.timingMode, .amrap)
        XCTAssertTrue(context.blocks.first?.timingConfigJSON.contains(#""time_cap_sec":1200"#) == true)
        XCTAssertEqual(context.itemsByBlock.first?.map { context.exerciseName(for: $0) }, [
            "Burpee",
            "Weighted Pull-Up",
            "Burpee",
            "Weighted Pull-Up",
            "Burpee",
            "Weighted Pull-Up",
            "Run",
        ])
        XCTAssertEqual(set.timing.mode, .capBounded)
        XCTAssertEqual(set.timing.capSec, 20 * 60)
        XCTAssertEqual(set.traversal, .amrap)
        XCTAssertEqual(set.slots.count, 7)
        XCTAssertTrue(set.workTargets.contains {
            $0.metric == .rounds && $0.role == .observation
        })
        XCTAssertTrue(set.workTargets.contains {
            $0.metric == .distance && $0.role == .observation
        })
        XCTAssertEqual(set.slots[1].load, PrimitiveLoad(value: 10, unit: .kg, unitType: .absolute))
        XCTAssertEqual(set.slots[3].load, PrimitiveLoad(value: 10, unit: .kg, unitType: .absolute))
        XCTAssertEqual(set.slots[5].load, PrimitiveLoad(value: 10, unit: .kg, unitType: .absolute))
        XCTAssertEqual(set.slots[0].exerciseID, set.slots[2].exerciseID)
        XCTAssertEqual(set.slots[2].exerciseID, set.slots[4].exerciseID)
        XCTAssertEqual(set.slots[1].exerciseID, set.slots[3].exerciseID)
        XCTAssertEqual(set.slots[3].exerciseID, set.slots[5].exerciseID)
        XCTAssertTrue(set.slots[6].workTargets.contains {
            $0.metric == .distance && $0.value == 1_000
        })
        XCTAssertTrue(set.slots[6].workTargets.contains {
            $0.metric == .duration && $0.value == 360 && $0.role == .observation
        })
    }

    func testPrimitiveStressScenariosCoverChipperIntervalsCarriesAndDensity() throws {
        let chipper = try XCTUnwrap(ExecutionPreviewSeed.qaScenario("primitive_chipper"))
        XCTAssertEqual(chipper.workout.name, "QA Primitive · For Time Chipper")
        XCTAssertEqual(chipper.blocks.first?.timingMode, .forTime)
        XCTAssertEqual(chipper.itemsByBlock.first?.map { chipper.exerciseName(for: $0) }, [
            "Row",
            "Thruster",
            "Pull-Up",
            "Run",
        ])
        let chipperSet = try firstPrimitiveSet(chipper)
        XCTAssertEqual(chipperSet.timing.mode, .capBounded)
        XCTAssertTrue(chipperSet.slots[0].workTargets.contains {
            $0.metric == .distance && $0.value == 500 && $0.role == .completion
        })
        XCTAssertEqual(chipperSet.slots[1].load, PrimitiveLoad(value: 35, unit: .kg, unitType: .absolute))
        XCTAssertTrue(chipperSet.slots[3].workTargets.contains {
            $0.metric == .duration && $0.value == 120 && $0.role == .observation
        })

        let intervals = try XCTUnwrap(ExecutionPreviewSeed.qaScenario("primitive_intervals"))
        XCTAssertEqual(intervals.blocks.first?.timingMode, .intervals)
        XCTAssertEqual(intervals.itemsByBlock.first?.map { intervals.exerciseName(for: $0) }, [
            "Run",
            "Shuttle Run",
            "Plank",
        ])
        let intervalSet = try firstPrimitiveSet(intervals)
        XCTAssertEqual(intervalSet.timing.mode, .timeBounded)
        XCTAssertEqual(intervalSet.timing.intervalSec, 12)
        XCTAssertEqual(intervalSet.timing.rounds, 3)
        XCTAssertEqual(intervalSet.traversal, .roundRobin)
        XCTAssertTrue(intervalSet.slots[2].workTargets.contains {
            $0.metric == .duration && $0.value == 20 && $0.role == .completion
        })

        let carries = try XCTUnwrap(ExecutionPreviewSeed.qaScenario("primitive_carry_circuit"))
        XCTAssertEqual(carries.blocks.first?.timingMode, .circuit)
        XCTAssertEqual(carries.blocks.first?.rounds, 2)
        let carrySet = try firstPrimitiveSet(carries)
        XCTAssertEqual(carrySet.traversal, .roundRobin)
        XCTAssertTrue(carrySet.slots[0].workTargets.contains {
            $0.metric == .loadCarried && $0.value == 32
        })
        XCTAssertTrue(carrySet.slots[3].workTargets.contains {
            $0.metric == .distance && $0.value == 20
        })
        XCTAssertEqual(carrySet.slots[3].load, PrimitiveLoad(value: 60, unit: .kg, unitType: .absolute))

        let density = try XCTUnwrap(ExecutionPreviewSeed.qaScenario("primitive_strength_density"))
        XCTAssertEqual(density.blocks.first?.timingMode, .emom)
        let densitySet = try firstPrimitiveSet(density)
        XCTAssertEqual(densitySet.timing.mode, .timeBounded)
        XCTAssertEqual(densitySet.timing.intervalSec, 20)
        XCTAssertEqual(densitySet.timing.rounds, 3)
        XCTAssertEqual(densitySet.traversal, .roundRobin)
        XCTAssertEqual(densitySet.slots[0].load, PrimitiveLoad(value: 140, unit: .kg, unitType: .absolute))
        XCTAssertTrue(densitySet.slots[2].workTargets.contains {
            $0.metric == .duration && $0.value == 12 && $0.role == .completion
        })
    }

    func testTransitionSetupCoversRepeatedExerciseAndMultiSetCarry() throws {
        let context = try XCTUnwrap(ExecutionPreviewSeed.qaScenario("transition_setup"))

        XCTAssertEqual(context.blocks.map(\.name), [
            "Press primer",
            "Press repeat",
            "Carry test",
        ])
        XCTAssertEqual(context.itemsByBlock.map(\.count), [1, 1, 1])

        let firstBench = try XCTUnwrap(context.itemsByBlock[0].first)
        let secondBench = try XCTUnwrap(context.itemsByBlock[1].first)
        let carry = try XCTUnwrap(context.itemsByBlock[2].first)

        XCTAssertEqual(
            firstBench.exerciseID,
            secondBench.exerciseID,
            "same exercise name repeated across blocks must reuse one exercise identity"
        )
        XCTAssertNotEqual(firstBench.id, secondBench.id)
        XCTAssertTrue(carry.prescriptionJSON.contains(#""sets":3"#))
    }

    func testUnknownScenarioReturnsNil() {
        XCTAssertNil(ExecutionPreviewSeed.qaScenario("not_a_scenario"))
    }

    private func firstPrimitiveSet(_ context: WorkoutContext) throws -> PrimitiveSet {
        let primitive = try XCTUnwrap(context.primitiveWorkout)
        let block = try XCTUnwrap(primitive.blocks.first)
        return try XCTUnwrap(block.sets.first)
    }
}

#endif
