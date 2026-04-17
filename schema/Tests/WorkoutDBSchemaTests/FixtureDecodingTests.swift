// Canonical fixture decoding tests.
//
// These JSON files under schema/fixtures/ are the cross-stack truth-set —
// both Swift and Python decode them successfully. If a fixture stops decoding
// here or in the Python contract tests, the wire format drifted.

import Foundation
import Testing

@testable import WorkoutDBSchema

struct FixtureDecodingTests {

    static var fixtureRoot: URL {
        // Tests run from schema/.build/..., so walk up to the package dir.
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "schema" && url.path != "/" {
            url.deleteLastPathComponent()
        }
        return url.appendingPathComponent("fixtures")
    }

    let decoder = JSONDecoder.workoutDB()

    @Test func workoutCreateFixture() throws {
        let url = Self.fixtureRoot.appendingPathComponent("workout_create.json")
        let data = try Data(contentsOf: url)
        let workout = try decoder.decode(Workout.self, from: data)
        #expect(workout.name == "Tuesday Legs")
        #expect(workout.status == .planned)
        #expect(workout.blocks.count == 1)
        #expect(workout.blocks[0].timingMode == .straightSets)
        #expect(workout.blocks[0].workoutItems.count == 1)
        #expect(workout.blocks[0].workoutItems[0].alternatives.count == 1)
        #expect(workout.tagsJson == "[\"hypertrophy_block_2\", \"week_3\"]")
    }

    @Test func syncPullResponseFixture() throws {
        let url = Self.fixtureRoot.appendingPathComponent("sync_pull_response.json")
        let data = try Data(contentsOf: url)
        let response = try decoder.decode(SyncPullResponse.self, from: data)
        #expect(response.exercises.count == 1)
        #expect(response.exercises[0].id == "back-squat")
        #expect(response.userParameters.count == 1)
        #expect(response.userParameters[0].source == .claude)
        #expect(response.lastPerformed.count == 1)
        let first = response.lastPerformed[0]
        #expect(first.exerciseId == "back-squat")
        #expect(first.lastSetLogs.first?.weight == 100.0)
        #expect(first.lastSetLogs.first?.hrAvgBpm == 142)
    }
}
