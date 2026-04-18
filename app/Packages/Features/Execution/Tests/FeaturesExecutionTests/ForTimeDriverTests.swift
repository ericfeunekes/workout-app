// ForTimeDriverTests.swift
//
// Unit coverage for `ForTimeDriver`:
//   - restDuration always returns 0 (for_time is continuous effort)
//   - activeContent resolves reps from `rounds_rep_scheme[round - 1]`
//     when the scheme is authored on the block
//   - activeContent falls back to the item's authored prescription when
//     the scheme is absent or malformed
//   - activeContent returns nil when the cursor is out of range
//   - onSetLogged returns an empty outcome (no autoreg on for_time)
//
// Built against the `for_time` timing mode with a chipper shape — 3 rounds
// of thrusters + pull-ups, per docs/prescription.md § "Fran".

import XCTest
import CoreAutoreg
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation
@testable import FeaturesExecution

@MainActor
final class ForTimeDriverTests: XCTestCase {

    // MARK: - Fixtures

    private struct Fixture {
        let context: WorkoutContext
        let thrusterItemID: UUID
        let pullupItemID: UUID
    }

    /// Fran-style chipper: 3 rounds of (thruster @ 43 kg, pull-up).
    /// `roundsRepSchemeJSON` is parameterized so tests can exercise the
    /// scheme-present, scheme-absent, and scheme-malformed branches.
    private func makeFixture(
        timeCapSec: Int? = 600,
        rounds: Int? = 3,
        roundsRepSchemeJSON: String? = #"[21, 15, 9]"#,
        thrusterPrescription: String = #"{"load_kg":43}"#,
        pullupPrescription: String = "{}"
    ) -> Fixture {
        let workoutID = UUID()
        let userID = UUID()
        let blockID = UUID()
        let thrusterID = UUID()
        let pullupID = UUID()
        let thrusterItemID = UUID()
        let pullupItemID = UUID()
        let now = Date()

        let workout = Workout(
            id: workoutID, userID: userID, name: "Fran",
            scheduledDate: now, status: .planned, source: .claude,
            notes: nil, createdAt: now, updatedAt: now,
            completedAt: nil, tagsJSON: nil
        )
        let configJSON: String = {
            if let cap = timeCapSec {
                return #"{"time_cap_sec":\#(cap)}"#
            }
            return "{}"
        }()
        let block = Block(
            id: blockID, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: "Metcon", timingMode: .forTime,
            timingConfigJSON: configJSON,
            rounds: rounds, roundsRepSchemeJSON: roundsRepSchemeJSON, notes: nil
        )
        let thruster = WorkoutItem(
            id: thrusterItemID, blockID: blockID, position: 0,
            exerciseID: thrusterID,
            prescriptionJSON: thrusterPrescription
        )
        let pullup = WorkoutItem(
            id: pullupItemID, blockID: blockID, position: 1,
            exerciseID: pullupID,
            prescriptionJSON: pullupPrescription
        )
        let context = WorkoutContext(
            workout: workout,
            blocks: [block],
            itemsByBlock: [[thruster, pullup]],
            exercises: [
                thrusterID: Exercise(id: thrusterID, name: "Thruster"),
                pullupID: Exercise(id: pullupID, name: "Pull-up"),
            ],
            lastPerformed: [:]
        )
        return Fixture(
            context: context,
            thrusterItemID: thrusterItemID,
            pullupItemID: pullupItemID
        )
    }

    /// Build a SessionState whose cursor sits at (block=0, itemIndex, round).
    /// The driver reads reps/load from the block scheme + item prescription,
    /// not from `itemLog.sets`, so a seeder-produced itemLog (with whatever
    /// SetPlan rows fall out of the for_time prescription parse) is fine —
    /// we just need the itemLog to exist and the cursor to point at the
    /// right place.
    private func makeState(
        context: WorkoutContext,
        itemIndex: Int,
        round: Int
    ) -> SessionState {
        let seed = SessionSeeder.seed(context: context)
        return SessionState(
            workoutID: seed.workoutID,
            route: .active,
            cursor: SessionState.Cursor(
                blockIndex: 0,
                itemIndex: itemIndex,
                setIndex: round
            ),
            items: seed.items,
            restEndsAt: nil,
            note: "",
            structure: seed.structure
        )
    }

    // MARK: - restDuration

    func testRestDurationIsZero() {
        let fixture = makeFixture()
        let state = makeState(context: fixture.context, itemIndex: 0, round: 1)
        let driver = ForTimeDriver()
        XCTAssertEqual(driver.restDuration(state: state, context: fixture.context), 0)
    }

    func testRestDurationIsZeroWithoutTimeCap() {
        let fixture = makeFixture(timeCapSec: nil)
        let state = makeState(context: fixture.context, itemIndex: 0, round: 1)
        let driver = ForTimeDriver()
        XCTAssertEqual(driver.restDuration(state: state, context: fixture.context), 0)
    }

    func testRestDurationIsZeroOnMalformedConfig() {
        // Even if the timing config is malformed, for_time is continuous —
        // the driver always returns 0.
        var fixture = makeFixture()
        let workoutID = fixture.context.workout.id
        let b = fixture.context.blocks[0]
        let malformedBlock = Block(
            id: b.id, workoutID: workoutID, parentBlockID: nil,
            position: 0, name: b.name, timingMode: .forTime,
            timingConfigJSON: "not json",
            rounds: b.rounds, roundsRepSchemeJSON: b.roundsRepSchemeJSON, notes: nil
        )
        fixture = Fixture(
            context: WorkoutContext(
                workout: fixture.context.workout,
                blocks: [malformedBlock],
                itemsByBlock: fixture.context.itemsByBlock,
                exercises: fixture.context.exercises,
                lastPerformed: fixture.context.lastPerformed
            ),
            thrusterItemID: fixture.thrusterItemID,
            pullupItemID: fixture.pullupItemID
        )
        let state = makeState(context: fixture.context, itemIndex: 0, round: 1)
        let driver = ForTimeDriver()
        XCTAssertEqual(driver.restDuration(state: state, context: fixture.context), 0)
    }

    // MARK: - activeContent — scheme present

    func testActiveContentResolvesRepsFromSchemeRoundOne() {
        let fixture = makeFixture()
        let state = makeState(context: fixture.context, itemIndex: 0, round: 1)
        let driver = ForTimeDriver()
        let content = driver.activeContent(state: state, context: fixture.context)
        XCTAssertNotNil(content)
        XCTAssertEqual(content?.reps, 21)
        XCTAssertEqual(content?.repsDisplay, "21")
        XCTAssertEqual(content?.setIndex, 1)
        XCTAssertEqual(content?.totalSets, 3)
        XCTAssertEqual(content?.exerciseName, "Thruster")
        XCTAssertEqual(content?.loadKg, 43)
        XCTAssertEqual(content?.loadDisplay, "43 kg")
        XCTAssertNil(content?.adjustGlyph)
    }

    func testActiveContentResolvesRepsFromSchemeRoundTwo() {
        let fixture = makeFixture()
        let state = makeState(context: fixture.context, itemIndex: 0, round: 2)
        let driver = ForTimeDriver()
        let content = driver.activeContent(state: state, context: fixture.context)
        XCTAssertEqual(content?.reps, 15)
        XCTAssertEqual(content?.setIndex, 2)
    }

    func testActiveContentResolvesRepsFromSchemeRoundThree() {
        let fixture = makeFixture()
        let state = makeState(context: fixture.context, itemIndex: 0, round: 3)
        let driver = ForTimeDriver()
        let content = driver.activeContent(state: state, context: fixture.context)
        XCTAssertEqual(content?.reps, 9)
        XCTAssertEqual(content?.setIndex, 3)
    }

    func testActiveContentSchemeAppliesAcrossItemsInSameRound() {
        // In round 1 with scheme [21, 15, 9], BOTH items should display 21
        // reps — the scheme indexes by round, not by item.
        let fixture = makeFixture()
        let state = makeState(context: fixture.context, itemIndex: 1, round: 1)
        let driver = ForTimeDriver()
        let content = driver.activeContent(state: state, context: fixture.context)
        XCTAssertEqual(content?.reps, 21)
        XCTAssertEqual(content?.exerciseName, "Pull-up")
        XCTAssertEqual(content?.loadDisplay, "BW") // pull-up has no load_kg
        XCTAssertNil(content?.loadKg)
    }

    // MARK: - activeContent — scheme absent

    func testActiveContentFallsBackToItemPrescriptionWhenSchemeAbsent() {
        // No scheme — item's prescription carries reps directly.
        let fixture = makeFixture(
            roundsRepSchemeJSON: nil,
            thrusterPrescription: #"{"reps":10,"load_kg":43}"#
        )
        let state = makeState(context: fixture.context, itemIndex: 0, round: 1)
        let driver = ForTimeDriver()
        let content = driver.activeContent(state: state, context: fixture.context)
        XCTAssertEqual(content?.reps, 10)
        XCTAssertEqual(content?.repsDisplay, "10")
        XCTAssertEqual(content?.loadKg, 43)
    }

    func testActiveContentFallsBackToItemPrescriptionWhenSchemeMalformed() {
        let fixture = makeFixture(
            roundsRepSchemeJSON: "not json at all",
            thrusterPrescription: #"{"reps":7,"load_kg":43}"#
        )
        let state = makeState(context: fixture.context, itemIndex: 0, round: 1)
        let driver = ForTimeDriver()
        let content = driver.activeContent(state: state, context: fixture.context)
        XCTAssertEqual(content?.reps, 7)
    }

    func testActiveContentFallsBackWhenSchemeIsNotArray() {
        let fixture = makeFixture(
            roundsRepSchemeJSON: #"{"not":"an array"}"#,
            thrusterPrescription: #"{"reps":12,"load_kg":43}"#
        )
        let state = makeState(context: fixture.context, itemIndex: 0, round: 1)
        let driver = ForTimeDriver()
        let content = driver.activeContent(state: state, context: fixture.context)
        XCTAssertEqual(content?.reps, 12)
    }

    func testActiveContentFallsBackWhenSchemeIsShorterThanRound() {
        // Scheme has 2 entries but we ask for round 3 → fall back to item.
        let fixture = makeFixture(
            roundsRepSchemeJSON: "[21, 15]",
            thrusterPrescription: #"{"reps":4,"load_kg":43}"#
        )
        let state = makeState(context: fixture.context, itemIndex: 0, round: 3)
        let driver = ForTimeDriver()
        let content = driver.activeContent(state: state, context: fixture.context)
        XCTAssertEqual(content?.reps, 4)
    }

    func testActiveContentFallsBackToZeroWhenNothingAuthored() {
        // No scheme, empty prescription — the driver produces a renderable
        // content with reps=0 rather than crashing.
        let fixture = makeFixture(
            roundsRepSchemeJSON: nil,
            thrusterPrescription: "{}"
        )
        let state = makeState(context: fixture.context, itemIndex: 0, round: 1)
        let driver = ForTimeDriver()
        let content = driver.activeContent(state: state, context: fixture.context)
        XCTAssertEqual(content?.reps, 0)
    }

    // MARK: - activeContent — out-of-range cursor

    func testActiveContentReturnsNilWhenBlockIndexOutOfRange() {
        let fixture = makeFixture()
        let seed = SessionSeeder.seed(context: fixture.context)
        let state = SessionState(
            workoutID: seed.workoutID,
            route: .active,
            cursor: SessionState.Cursor(blockIndex: 42, itemIndex: 0, setIndex: 1),
            items: seed.items,
            restEndsAt: nil,
            note: "",
            structure: seed.structure
        )
        let driver = ForTimeDriver()
        XCTAssertNil(driver.activeContent(state: state, context: fixture.context))
    }

    func testActiveContentReturnsNilWhenItemIndexOutOfRange() {
        let fixture = makeFixture()
        let state = makeState(context: fixture.context, itemIndex: 99, round: 1)
        let driver = ForTimeDriver()
        XCTAssertNil(driver.activeContent(state: state, context: fixture.context))
    }

    // MARK: - onSetLogged

    func testOnSetLoggedReturnsEmptyOutcome() {
        let fixture = makeFixture()
        let state = makeState(context: fixture.context, itemIndex: 0, round: 1)
        let driver = ForTimeDriver()
        let outcome = driver.onSetLogged(
            state: state,
            context: fixture.context,
            event: SetLogEvent(
                itemID: fixture.thrusterItemID,
                setIndex: 1,
                loggedReps: 21,
                loggedRir: nil
            )
        )
        XCTAssertNil(outcome.proposal)
        XCTAssertTrue(outcome.mutations.isEmpty)
    }
}
