#if DEBUG
import XCTest
import Shell

final class DebugLaunchRouteTests: XCTestCase {
    func testWorkoutKitProbeBypassesFirstRunWithoutDebugSeed() {
        let route = DebugLaunchRoute.classify(args: ["WorkoutDB", "--debug-workoutkit-push-probe"])

        XCTAssertTrue(route.bypassesFirstRun)
        XCTAssertFalse(route.usesDebugSeed)
        XCTAssertFalse(route.showsHealthKitProbe)
        XCTAssertFalse(route.runsWatchPushProbe)
        XCTAssertTrue(route.runsWorkoutKitPushProbe)
    }

    func testWatchPushProbeBypassesFirstRunWithoutDebugSeed() {
        let route = DebugLaunchRoute.classify(args: ["WorkoutDB", "--debug-watch-push"])

        XCTAssertTrue(route.bypassesFirstRun)
        XCTAssertFalse(route.usesDebugSeed)
        XCTAssertFalse(route.showsHealthKitProbe)
        XCTAssertTrue(route.runsWatchPushProbe)
        XCTAssertFalse(route.runsWorkoutKitPushProbe)
    }

    func testFixtureArgsStillUseDebugSeed() {
        let route = DebugLaunchRoute.classify(args: ["WorkoutDB", "--jump-rest"])

        XCTAssertTrue(route.bypassesFirstRun)
        XCTAssertTrue(route.usesDebugSeed)
        XCTAssertFalse(route.showsHealthKitProbe)
        XCTAssertFalse(route.runsWatchPushProbe)
        XCTAssertFalse(route.runsWorkoutKitPushProbe)
    }

    func testHealthKitProbeUsesDedicatedProbeRoute() {
        let route = DebugLaunchRoute.classify(args: ["WorkoutDB", "--healthkit-sim-spike"])

        XCTAssertTrue(route.bypassesFirstRun)
        XCTAssertFalse(route.usesDebugSeed)
        XCTAssertTrue(route.showsHealthKitProbe)
        XCTAssertFalse(route.runsWatchPushProbe)
        XCTAssertFalse(route.runsWorkoutKitPushProbe)
    }

    func testFixtureMayAlsoRunProbeExplicitly() {
        let route = DebugLaunchRoute.classify(args: [
            "WorkoutDB",
            "--start-active",
            "--debug-watch-push",
        ])

        XCTAssertTrue(route.bypassesFirstRun)
        XCTAssertTrue(route.usesDebugSeed)
        XCTAssertTrue(route.runsWatchPushProbe)
    }
}
#endif
