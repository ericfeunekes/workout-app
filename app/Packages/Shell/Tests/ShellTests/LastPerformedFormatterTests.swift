// LastPerformedFormatterTests.swift
//
// Pins the per-exercise "LAST · …" summary shape consumed by Today's
// chip and SwapSheet's alternative row. The formatter is the only
// place that turns the pulled set_logs into the pre-formatted display
// string (qa-001 + qa-020) — chip drift across the two views is
// prevented by both views reading the same map.

import XCTest
import CoreDomain
import Sync
import WorkoutCoreFoundation
@testable import Shell

final class LastPerformedFormatterTests: XCTestCase {

    // MARK: - Happy path: straight-sets logs

    func testFormatsTopWorkingSetWithRIR() {
        let exerciseID = UUID()
        let workoutItemID = UUID()
        let snapshot = LastPerformed(
            exerciseID: exerciseID,
            lastSetLogs: [
                setLog(
                    workoutItemID: workoutItemID, setIndex: 1,
                    reps: 5, weight: 100.0, weightUnit: .kg, rir: 2
                ),
                setLog(
                    workoutItemID: workoutItemID, setIndex: 2,
                    reps: 5, weight: 100.0, weightUnit: .kg, rir: 2
                ),
                setLog(
                    workoutItemID: workoutItemID, setIndex: 3,
                    reps: 5, weight: 100.0, weightUnit: .kg, rir: 2
                ),
            ]
        )
        let line = LastPerformedFormatter.format(snapshot: snapshot)
        XCTAssertEqual(line, "3×5 @ 100 kg · RIR 2")
    }

    // MARK: - Unit defaults to lb when the server omits weight_unit

    func testDefaultsToPoundsWhenWeightUnitNil() {
        let snapshot = LastPerformed(
            exerciseID: UUID(),
            lastSetLogs: [
                setLog(
                    workoutItemID: UUID(), setIndex: 1,
                    reps: 5, weight: 225.0, weightUnit: nil, rir: 2
                ),
            ]
        )
        XCTAssertEqual(
            LastPerformedFormatter.format(snapshot: snapshot),
            "1×5 @ 225 lb · RIR 2"
        )
    }

    // MARK: - Heaviest-set pick (top-set is what the user cares about)

    func testPicksHeaviestWorkingSetAsRepresentative() {
        let snapshot = LastPerformed(
            exerciseID: UUID(),
            lastSetLogs: [
                setLog(
                    workoutItemID: UUID(), setIndex: 1,
                    reps: 5, weight: 100.0, weightUnit: .kg, rir: 3
                ),
                setLog(
                    workoutItemID: UUID(), setIndex: 2,
                    reps: 3, weight: 110.0, weightUnit: .kg, rir: 1
                ),
                setLog(
                    workoutItemID: UUID(), setIndex: 3,
                    reps: 5, weight: 100.0, weightUnit: .kg, rir: 2
                ),
            ]
        )
        // 3 working sets; heaviest is 110×3 RIR 1. Count is all three.
        XCTAssertEqual(
            LastPerformedFormatter.format(snapshot: snapshot),
            "3×3 @ 110 kg · RIR 1"
        )
    }

    // MARK: - Warmups excluded from count + representative pick

    func testWarmupsExcludedFromCountAndPick() {
        let snapshot = LastPerformed(
            exerciseID: UUID(),
            lastSetLogs: [
                setLog(
                    workoutItemID: UUID(), setIndex: 1,
                    reps: 5, weight: 50.0, weightUnit: .kg,
                    rir: 5, isWarmup: true
                ),
                setLog(
                    workoutItemID: UUID(), setIndex: 2,
                    reps: 5, weight: 100.0, weightUnit: .kg, rir: 2
                ),
                setLog(
                    workoutItemID: UUID(), setIndex: 3,
                    reps: 5, weight: 100.0, weightUnit: .kg, rir: 2
                ),
            ]
        )
        XCTAssertEqual(
            LastPerformedFormatter.format(snapshot: snapshot),
            "2×5 @ 100 kg · RIR 2"
        )
    }

    // MARK: - Bodyweight / cardio edge cases

    func testRendersBWWhenWeightIsNil() {
        let snapshot = LastPerformed(
            exerciseID: UUID(),
            lastSetLogs: [
                setLog(
                    workoutItemID: UUID(), setIndex: 1,
                    reps: 12, weight: nil, weightUnit: nil, rir: 2
                ),
                setLog(
                    workoutItemID: UUID(), setIndex: 2,
                    reps: 10, weight: nil, weightUnit: nil, rir: 1
                ),
            ]
        )
        // Heaviest tied at 0 → ties resolve on setIndex ascending,
        // picking the first set (reps 12, RIR 2).
        XCTAssertEqual(
            LastPerformedFormatter.format(snapshot: snapshot),
            "2×12 BW · RIR 2"
        )
    }

    func testOmitsRIRSegmentWhenNil() {
        let snapshot = LastPerformed(
            exerciseID: UUID(),
            lastSetLogs: [
                setLog(
                    workoutItemID: UUID(), setIndex: 1,
                    reps: 5, weight: 100.0, weightUnit: .kg, rir: nil
                ),
            ]
        )
        XCTAssertEqual(
            LastPerformedFormatter.format(snapshot: snapshot),
            "1×5 @ 100 kg"
        )
    }

    // MARK: - Empty / warmups-only snapshots return nil

    func testReturnsNilWhenSetLogsEmpty() {
        let snapshot = LastPerformed(
            exerciseID: UUID(),
            lastSetLogs: []
        )
        XCTAssertNil(LastPerformedFormatter.format(snapshot: snapshot))
    }

    func testReturnsNilWhenOnlyWarmups() {
        let snapshot = LastPerformed(
            exerciseID: UUID(),
            lastSetLogs: [
                setLog(
                    workoutItemID: UUID(), setIndex: 1,
                    reps: 5, weight: 40.0, weightUnit: .kg,
                    rir: 5, isWarmup: true
                ),
            ]
        )
        XCTAssertNil(LastPerformedFormatter.format(snapshot: snapshot))
    }

    // MARK: - Map construction skips unusable snapshots

    func testBuildMapSkipsSnapshotsThatProduceNoSummary() {
        let usable = UUID()
        let empty = UUID()
        let snapshots = [
            LastPerformed(
                exerciseID: usable,
                lastSetLogs: [
                    setLog(
                        workoutItemID: UUID(), setIndex: 1,
                        reps: 5, weight: 100.0, weightUnit: .kg, rir: 2
                    ),
                ]
            ),
            LastPerformed(
                exerciseID: empty,
                lastSetLogs: []
            ),
        ]
        let map = LastPerformedFormatter.buildMap(from: snapshots)
        XCTAssertEqual(map[usable], "1×5 @ 100 kg · RIR 2")
        XCTAssertNil(map[empty])
        XCTAssertEqual(map.count, 1)
    }

    // MARK: - Helpers

    private func setLog(
        workoutItemID: UUID,
        setIndex: Int,
        reps: Int?,
        weight: Double?,
        weightUnit: WeightUnit?,
        rir: Int?,
        isWarmup: Bool = false
    ) -> SetLog {
        SetLog(
            id: UUID(),
            workoutItemID: workoutItemID,
            performedExerciseID: nil,
            setIndex: setIndex,
            reps: reps,
            weight: weight,
            weightUnit: weightUnit,
            durationSec: nil,
            distanceM: nil,
            rir: rir,
            isWarmup: isWarmup,
            startedAt: nil,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            hrAvgBpm: nil,
            hrMaxBpm: nil,
            cadenceAvgSpm: nil,
            motionSamplesRef: nil,
            notes: nil
        )
    }
}
