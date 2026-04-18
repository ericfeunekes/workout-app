// RestBlockDriverTests.swift
//
// Unit coverage for `RestBlockDriver`:
//   - restDuration reads `timing_config_json.duration_sec`
//   - restDuration defaults to 0 on missing / malformed config
//     (matches `StraightSetsDriver.restDuration`'s parse-failure fallback)
//   - activeContent returns nil (rest block has no Active screen)
//   - onSetLogged returns an empty outcome (rest block has no sets)
//
// Built against the `rest` timing mode with a zero-item block — the
// real-world shape for a standalone rest between work blocks.

import XCTest
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class RestBlockDriverTests: XCTestCase {

    // MARK: - Fixtures

    private func makeRestBlockContext(
        configJSON: String
    ) -> WorkoutContext {
        let workoutID = UUID()
        let userID = UUID()
        let blockID = UUID()
        let now = Date()

        let workout = Workout(
            id: workoutID, userID: userID, name: "rest-only",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: nil, timingMode: .rest,
            timingConfigJSON: configJSON,
            rounds: nil, roundsRepSchemeJSON: nil, notes: nil
        )
        return WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [[]],      // zero-item block
            exercises: [:]
        )
    }

    /// Build a SessionState whose cursor sits on block 0 (the rest block).
    /// Uses the seeder so the structure reflects the zero-item shape
    /// (`itemsPerBlock[0] == 0`).
    private func makeRestBlockState(configJSON: String) -> (WorkoutContext, SessionState) {
        let ctx = makeRestBlockContext(configJSON: configJSON)
        let seed = SessionSeeder.seed(context: ctx)
        return (ctx, seed)
    }

    // MARK: - restDuration

    func testRestDurationReadsDurationSec() {
        let (ctx, state) = makeRestBlockState(
            configJSON: #"{"duration_sec":30}"#
        )
        let driver = RestBlockDriver()
        XCTAssertEqual(driver.restDuration(state: state, context: ctx), 30)
    }

    func testRestDurationReadsFractionalSeconds() {
        let (ctx, state) = makeRestBlockState(
            configJSON: #"{"duration_sec":90.5}"#
        )
        let driver = RestBlockDriver()
        XCTAssertEqual(driver.restDuration(state: state, context: ctx), 90.5)
    }

    func testRestDurationDefaultsToZeroOnMissingKey() {
        // `duration_sec` is required per the parser; missing → parse failure.
        let (ctx, state) = makeRestBlockState(configJSON: "{}")
        let driver = RestBlockDriver()
        XCTAssertEqual(driver.restDuration(state: state, context: ctx), 0)
    }

    func testRestDurationDefaultsToZeroOnMalformedJSON() {
        let (ctx, state) = makeRestBlockState(configJSON: "not json at all")
        let driver = RestBlockDriver()
        XCTAssertEqual(driver.restDuration(state: state, context: ctx), 0)
    }

    // MARK: - activeContent

    func testActiveContentReturnsNilForRestBlock() {
        let (ctx, state) = makeRestBlockState(
            configJSON: #"{"duration_sec":30}"#
        )
        let driver = RestBlockDriver()
        XCTAssertNil(driver.activeContent(state: state, context: ctx))
    }

    // MARK: - onSetLogged

    func testOnSetLoggedReturnsEmptyOutcome() {
        let (ctx, state) = makeRestBlockState(
            configJSON: #"{"duration_sec":30}"#
        )
        let driver = RestBlockDriver()
        // Defensive call — shouldn't fire in production flow. Any itemID
        // works since there are no items in the block.
        let outcome = driver.onSetLogged(
            state: state,
            context: ctx,
            event: SetLogEvent(
                itemID: UUID(),
                setIndex: 1,
                loggedReps: 5,
                loggedRir: 2
            )
        )
        XCTAssertNil(outcome.proposal)
        XCTAssertTrue(outcome.mutations.isEmpty)
    }
}
