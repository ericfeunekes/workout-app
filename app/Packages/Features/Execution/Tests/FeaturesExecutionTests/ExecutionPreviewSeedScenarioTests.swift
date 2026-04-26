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

    func testUnknownScenarioReturnsNil() {
        XCTAssertNil(ExecutionPreviewSeed.qaScenario("not_a_scenario"))
    }
}

#endif
