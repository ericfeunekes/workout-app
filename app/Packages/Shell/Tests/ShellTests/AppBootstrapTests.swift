// AppBootstrapTests.swift
//
// Exercises `AppBootstrap.bootstrap(...)` across the four outcomes listed
// in `AppBootstrap.swift`'s file header:
//
//   1. Successful pull → cache populated → TodayContext has the workout.
//   2. Pull throws 401 → bootstrap raises `AppBootstrapError.tokenRejected`
//      (shell will clear the connection).
//   3. Pull throws network → cache empty → `.empty` result.
//   4. Pull throws network → cache populated → `.ready` from cache.
//
// Uses a hand-rolled `ScriptedTransport` so the test fixture is a JSON
// blob — same pipe the real URLSessionTransport feeds. The in-memory
// PersistenceFactory gives a real WorkoutCache (SwiftData in-memory) so
// the pull → save → load round-trip is exercised end to end.

import XCTest
import CoreDomain
import CoreSession
import CoreTelemetry
import FeaturesHistory
import FeaturesToday
import Persistence
import Sync
import WorkoutCoreFoundation
import WorkoutDBSchema
@testable import FeaturesExecution
@testable import Shell

@MainActor
final class AppBootstrapTests: XCTestCase {

    // MARK: - Happy path

    func testBootstrapPullsAndBuildsContexts() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let fixture = Fixtures.sampleWorkoutPayload()
        let transport = ScriptedTransport(
            getOutcomes: [.ok(fixture.json)]
        )

        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: fixture.scheduledDate,
            transportBuilder: { _ in transport }
        )

        guard case let .ready(todayVM, executionHolder, _) = result else {
            return XCTFail("expected .ready, got \(result)")
        }

        XCTAssertEqual(todayVM.programName, "Push A")
        XCTAssertEqual(todayVM.exercises.count, 2)
        let executionVM = try XCTUnwrap(executionHolder.vm)
        XCTAssertEqual(executionVM.context.workout.name, "Push A")
        XCTAssertEqual(executionVM.context.primitiveExecutionPlan?.blocks.count, 1)
        XCTAssertEqual(executionVM.context.primitiveExecutionPlan?.blocks.first?.sets.count, 2)

        // lastSyncAt must be recorded for the next launch's `since`.
        let stored = await factory.syncMetadataStore.getLastSyncAt()
        XCTAssertEqual(stored, fixture.serverTime)

        // Cache must be primed — a second bootstrap with a failing
        // transport should still return .ready.
        let failingTransport = ScriptedTransport(
            getOutcomes: [.error(.network("simulated"))]
        )
        let second = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: fixture.scheduledDate,
            transportBuilder: { _ in failingTransport }
        )
        guard case .ready = second else {
            return XCTFail("expected .ready from cache, got \(second)")
        }
    }

    func testInvalidPrimitivePullFallsBackWithoutDeletingCachedPrimitiveWorkout() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let fixture = Fixtures.sampleWorkoutPayload()
        let baseURL = try XCTUnwrap(URL(string: "https://example.test"))

        let initialTransport = ScriptedTransport(getOutcomes: [.ok(fixture.json)])
        let initial = try await AppBootstrap.bootstrap(
            connection: (url: baseURL, token: "tok"),
            persistence: factory,
            now: fixture.scheduledDate,
            transportBuilder: { _ in initialTransport }
        )
        guard case .ready = initial else {
            return XCTFail("expected initial .ready, got \(initial)")
        }
        let cachedBefore = try await factory.workoutCache.loadPrimitiveWorkouts()
        XCTAssertEqual(cachedBefore.count, 1)

        let invalidTransport = ScriptedTransport(getOutcomes: [
            .ok(try emptyPrimitiveBlocksJSON(from: fixture.json)),
        ])
        let fallback = try await AppBootstrap.bootstrap(
            connection: (url: baseURL, token: "tok"),
            persistence: factory,
            now: fixture.scheduledDate,
            transportBuilder: { _ in invalidTransport }
        )
        guard case .ready = fallback else {
            return XCTFail("expected cached .ready after invalid pull, got \(fallback)")
        }

        let cachedAfter = try await factory.workoutCache.loadPrimitiveWorkouts()
        XCTAssertEqual(
            cachedAfter,
            cachedBefore,
            "decode failures must not be interpreted as primitive tombstones"
        )
    }

    func testBootstrapLeavesHistoryCorrectionDisabledInProductionWiring() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let fixture = Fixtures.sampleWorkoutPayload()
        let historyVM = HistoryViewModel(cache: factory.workoutCache)
        let transport = ScriptedTransport(getOutcomes: [.ok(fixture.json)])

        _ = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: fixture.scheduledDate,
            transportBuilder: { _ in transport },
            historyViewModel: historyVM
        )

        XCTAssertFalse(
            historyVM.canEditPastSets,
            "production bootstrap must not wire legacy SetLog correction during primitive cutover"
        )
    }

    func testTodayRefreshRunsPullAndKeepsReadyState() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let fixture = Fixtures.sampleWorkoutPayload()
        let transport = ScriptedTransport(
            getOutcomes: [.ok(fixture.json), .ok(fixture.json)]
        )

        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: fixture.scheduledDate,
            transportBuilder: { _ in transport }
        )

        guard case let .ready(todayVM, executionHolder, _) = result else {
            return XCTFail("expected .ready, got \(result)")
        }
        XCTAssertTrue(todayVM.canRefresh)

        await todayVM.refresh()

        XCTAssertEqual(todayVM.refreshState, .idle)
        XCTAssertNotNil(executionHolder.vm)
        let paths = await transport.store.snapshotGetPaths()
        XCTAssertEqual(paths, ["/api/sync/pull", "/api/sync/pull"])
    }

    func testTodayRefreshRoutesTokenRejected() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let fixture = Fixtures.sampleWorkoutPayload()
        let transport = ScriptedTransport(
            getOutcomes: [.ok(fixture.json), .error(.tokenRejected)]
        )
        var routedToFirstRun = false

        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: fixture.scheduledDate,
            transportBuilder: { _ in transport },
            onManualRefreshTokenRejected: {
                routedToFirstRun = true
            }
        )

        guard case let .ready(todayVM, _, _) = result else {
            return XCTFail("expected .ready, got \(result)")
        }

        await todayVM.refresh()

        XCTAssertTrue(routedToFirstRun)
        XCTAssertEqual(todayVM.refreshState, .failed)
        let paths = await transport.store.snapshotGetPaths()
        XCTAssertEqual(paths, ["/api/sync/pull", "/api/sync/pull"])
    }

    func testForegroundPullReloadsTodayWithoutReplacingActiveExecution() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let fixture = Fixtures.sampleWorkoutPayload()
        let transport = ScriptedTransport(
            getOutcomes: [.ok(fixture.json), .ok(emptyPullJSON(serverTime: fixture.serverTime))]
        )
        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: fixture.scheduledDate,
            transportBuilder: { _ in transport }
        )
        guard case let .ready(todayVM, holder, appSync) = result else {
            return XCTFail("expected .ready, got \(result)")
        }
        let initialVM = try XCTUnwrap(holder.vm)
        initialVM.start()
        XCTAssertEqual(initialVM.state.route, .active)
        let updatedWorkout = Workout(
            id: fixture.domainWorkout.id,
            userID: fixture.domainWorkout.userID,
            name: "Push A Reloaded",
            scheduledDate: fixture.domainWorkout.scheduledDate,
            status: fixture.domainWorkout.status,
            source: fixture.domainWorkout.source,
            notes: fixture.domainWorkout.notes,
            createdAt: fixture.domainWorkout.createdAt,
            updatedAt: fixture.domainWorkout.updatedAt,
            completedAt: fixture.domainWorkout.completedAt,
            tagsJSON: fixture.domainWorkout.tagsJSON
        )
        try await factory.workoutCache.save(PulledDataset(
            workouts: [updatedWorkout],
            blocks: fixture.domainBlocks,
            items: fixture.domainItems,
            alternatives: [],
            exercises: fixture.domainExercises,
            userParameters: []
        ))

        _ = await appSync.enterForeground()

        XCTAssertEqual(todayVM.programName, "Push A Reloaded")
        XCTAssertTrue(holder.vm === initialVM)
        XCTAssertEqual(holder.vm?.state.route, .active)
    }

    // MARK: - 401 → shell must send user back to FirstRun

    func testBootstrapRaisesTokenRejected() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let transport = ScriptedTransport(
            getOutcomes: [.error(.tokenRejected)]
        )

        do {
            _ = try await AppBootstrap.bootstrap(
                connection: (url: URL(string: "https://example.test")!, token: "tok"),
                persistence: factory,
                now: Date(),
                transportBuilder: { _ in transport }
            )
            XCTFail("expected throw")
        } catch let err as AppBootstrapError {
            XCTAssertEqual(err, .tokenRejected)
        }
    }

    // MARK: - Offline + empty cache → .empty

    func testBootstrapWithEmptyCacheReturnsEmpty() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let transport = ScriptedTransport(
            getOutcomes: [.error(.network("dns"))]
        )

        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: Date(),
            transportBuilder: { _ in transport }
        )
        assertEmpty(result)
    }

    /// Regression guard for qa-027: the same `.empty` path above still
    /// fires when the cache has no workouts of any status. Truly-empty
    /// caches are the only condition that justifies the full-screen
    /// "No workouts yet" shell prompt that hides History.
    func testColdLaunchWithTrulyEmptyCacheGoesToEmpty() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        // No seed, no pull — cache stays empty.
        let transport = ScriptedTransport(
            getOutcomes: [.error(.network("dns"))]
        )

        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: Date(),
            transportBuilder: { _ in transport }
        )
        assertEmpty(result)

        // Belt + braces: confirm the cache really had nothing in it at the
        // time of the decision. If this starts failing, a seed leaked in.
        let anyWorkouts = try await factory.workoutCache.loadWorkouts(
            status: nil, since: nil
        )
        XCTAssertTrue(anyWorkouts.isEmpty)
    }

    /// qa-039 regression: a fresh install whose first `/api/sync/pull`
    /// succeeds with an EMPTY body (no workouts, no exercises, no
    /// user_parameters, no last_performed — server just hasn't had
    /// anything pushed to it yet) MUST land on `.empty`. This is the
    /// shell's cue to render the full-screen "no workouts yet" state
    /// with the "change server" escape hatch (S10 of `bootstrap.md`).
    ///
    /// `resolveNoPlannedWorkout` now keys on completed history (not
    /// "any workout at all"), so an empty cache + empty pull correctly
    /// drops to `.empty` without the stale-planned-workout hazard the
    /// prior "any status" check carried.
    ///
    /// Distinct from `testBootstrapWithEmptyCacheReturnsEmpty` above:
    /// that test exercises the OFFLINE path (pull throws network). This
    /// one exercises the SUCCESSFUL-but-EMPTY pull path — which would
    /// otherwise not be covered and is exactly the qa-039 repro.
    func testTrulyEmptyCacheGoesToEmptyPhaseAfterPull() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let emptyPull = """
        {
          "workouts": [],
          "exercises": [],
          "user_parameters": [],
          "last_performed": [],
          "server_time": "2026-04-19T12:00:00Z"
        }
        """.data(using: .utf8)!

        let transport = ScriptedTransport(
            getOutcomes: [.ok(emptyPull)]
        )

        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: Date(),
            transportBuilder: { _ in transport }
        )
        assertEmpty(
            result,
            "fresh install + empty successful pull must land on .empty " +
            "so the shell renders the change-server escape hatch"
        )

        // Belt + braces: confirm the cache is still empty after the
        // save-pull path ran. `savePull` with empty arrays should be a
        // no-op; if a migration-era quirk started writing an empty-row
        // marker, that would trip `resolveNoPlannedWorkout`'s "anyCached"
        // branch and resurrect the qa-039 behaviour.
        let anyWorkouts = try await factory.workoutCache.loadWorkouts(
            status: nil, since: nil
        )
        XCTAssertTrue(
            anyWorkouts.isEmpty,
            "empty pull must not leave any WorkoutModel rows in the cache"
        )
    }

    /// qa-039 investigation-option-2 guard: a successful pull that
    /// brings non-workout payload (exercises, user_parameters — e.g. a
    /// server that has a Claude-curated catalog but no workouts pushed
    /// yet) must STILL land on `.empty`. `resolveNoPlannedWorkout` now
    /// queries `loadWorkouts(status: .completed, since: nil)`;
    /// exercises and user_parameters live in different model classes
    /// and the completed-row count is zero for a catalog-only pull. If
    /// a future refactor seeds phantom completed-workout rows from a
    /// user_parameters sync, this test goes red first.
    func testPullWithOnlyExercisesAndParamsStillLandsInEmpty() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let exerciseID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
        let userID = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!
        let paramID = UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!
        let pullWithCatalogOnly = """
        {
          "workouts": [],
          "exercises": [
            {
              "id": "\(exerciseID.uuidString.lowercased())",
              "name": "Barbell Bench Press",
              "notes": null,
              "demo_url": null
            }
          ],
          "user_parameters": [
            {
              "id": "\(paramID.uuidString.lowercased())",
              "user_id": "\(userID.uuidString.lowercased())",
              "key": "bodyweight_kg",
              "value": "82.5",
              "updated_at": "2026-04-19T10:00:00Z",
              "source": "manual"
            }
          ],
          "last_performed": [],
          "server_time": "2026-04-19T12:00:00Z"
        }
        """.data(using: .utf8)!

        let transport = ScriptedTransport(
            getOutcomes: [.ok(pullWithCatalogOnly)]
        )

        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: Date(),
            transportBuilder: { _ in transport }
        )
        assertEmpty(
            result,
            "catalog-only pull (no workouts) must still land on .empty — " +
            "the WorkoutModel table is what drives the anyCached check"
        )

        // Sanity: the pull actually wrote the catalog rows. If this
        // fails, we're not actually exercising the "non-workout data
        // arrived" scenario.
        let exercises = try await factory.workoutCache.loadExercises()
        XCTAssertEqual(exercises.count, 1)
        let params = try await factory.workoutCache.loadUserParameters(key: "bodyweight_kg")
        XCTAssertEqual(params.count, 1)
    }

    func testBuildWorkoutContextIncludesPrimitivePlanFromCache() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let workoutID = UUID(uuidString: "10000000-0000-4000-8000-000000000061")!
        let userID = UUID(uuidString: "01000000-0000-4000-8000-000000000061")!
        let blockID = UUID(uuidString: "20000000-0000-4000-8000-000000000061")!
        let setID = UUID(uuidString: "30000000-0000-4000-8000-000000000061")!
        let slotID = UUID(uuidString: "40000000-0000-4000-8000-000000000061")!
        let exerciseID = UUID(uuidString: "50000000-0000-4000-8000-000000000061")!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = Workout(
            id: workoutID,
            userID: userID,
            name: "Primitive Cached",
            scheduledDate: now,
            status: .planned,
            source: .claude,
            createdAt: now,
            updatedAt: now
        )
        let primitive = PrimitiveWorkout(
            id: workoutID,
            name: "Primitive Cached",
            blocks: [
                PrimitiveBlock(id: blockID, sets: [
                    PrimitiveSet(
                        id: setID,
                        timing: PrimitiveTiming(mode: .capBounded, capSec: 300),
                        traversal: .amrap,
                        workTargets: [
                            PrimitiveWorkTarget(
                                metric: .rounds,
                                valueForm: .open,
                                role: .observation
                            ),
                        ],
                        slots: [
                            PrimitiveSlot(
                                id: slotID,
                                exerciseID: exerciseID,
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
        try await factory.workoutCache.save(PulledDataset(
            workouts: [workout],
            primitiveWorkouts: [primitive],
            exercises: [Exercise(id: exerciseID, name: "Push-up")]
        ))

        let context = try await AppBootstrap.buildWorkoutContext(
            for: workout,
            cache: factory.workoutCache
        )

        XCTAssertEqual(context.primitiveWorkout, primitive)
        XCTAssertEqual(context.primitiveExecutionPlan?.workoutID, workoutID)
        XCTAssertEqual(context.primitiveExecutionPlan?.blocks[0].sets[0].traversal, .amrap)
        XCTAssertEqual(context.exercises[exerciseID]?.name, "Push-up")
    }

    func testBuildWorkoutContextFailsWhenCachedPrimitiveWorkoutIsInvalid() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let workoutID = UUID(uuidString: "10000000-0000-4000-8000-000000000063")!
        let userID = UUID(uuidString: "01000000-0000-4000-8000-000000000063")!
        let exerciseID = UUID(uuidString: "30000000-0000-4000-8000-000000000063")!
        let blockID = UUID(uuidString: "20000000-0000-4000-8000-000000000063")!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = Workout(
            id: workoutID,
            userID: userID,
            name: "Invalid primitive cached",
            scheduledDate: now,
            status: .planned,
            source: .claude,
            createdAt: now,
            updatedAt: now
        )
        let primitive = PrimitiveWorkout(
            id: workoutID,
            name: workout.name,
            blocks: [
                PrimitiveBlock(id: blockID, sets: [
                    PrimitiveSet(
                        id: UUID(uuidString: "40000000-0000-4000-8000-000000000063")!,
                        timing: PrimitiveTiming(mode: .setBounded),
                        traversal: .amrap,
                        slots: [
                            PrimitiveSlot(id: UUID(), exerciseID: exerciseID, workTargets: []),
                        ]
                    ),
                ]),
            ]
        )
        try await factory.workoutCache.save(PulledDataset(
            workouts: [workout],
            primitiveWorkouts: [primitive],
            exercises: [Exercise(id: exerciseID, name: "Push-up")]
        ))

        do {
            _ = try await AppBootstrap.buildWorkoutContext(
                for: workout,
                cache: factory.workoutCache
            )
            XCTFail("buildWorkoutContext must surface invalid primitive cache state")
        } catch {
            XCTAssertTrue(error is PrimitiveSemanticError)
        }
    }

    func testBuildWorkoutContextFailsWhenUserParameterReadFails() async throws {
        let fixture = Fixtures.sampleWorkoutPayload()
        let cache = ThrowingUserParameterCache(
            base: EmptyWorkoutContextCache(workout: fixture.domainWorkout),
            error: TestError.userParameters
        )

        do {
            _ = try await AppBootstrap.buildWorkoutContext(
                for: fixture.domainWorkout,
                cache: cache
            )
            XCTFail("buildWorkoutContext must surface user-parameter storage failures")
        } catch {
            XCTAssertTrue(error is TestError)
        }
    }

    func testSavePullPropagatesPrimitiveTombstoneToCache() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let workoutID = UUID(uuidString: "10000000-0000-4000-8000-000000000062")!
        let userID = UUID(uuidString: "01000000-0000-4000-8000-000000000062")!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = Workout(
            id: workoutID,
            userID: userID,
            name: "Primitive Removed",
            scheduledDate: now,
            status: .planned,
            source: .claude,
            createdAt: now,
            updatedAt: now
        )
        let primitive = PrimitiveWorkout(
            id: workoutID,
            name: "Primitive Removed",
            blocks: [
                PrimitiveBlock(id: UUID(uuidString: "20000000-0000-4000-8000-000000000062")!, sets: [
                    PrimitiveSet(
                        id: UUID(uuidString: "30000000-0000-4000-8000-000000000062")!,
                        timing: PrimitiveTiming(mode: .setBounded),
                        slots: []
                    ),
                ]),
            ]
        )
        try await factory.workoutCache.save(PulledDataset(
            workouts: [workout],
            primitiveWorkouts: [primitive]
        ))

        let result = PullResult(
            serverTime: now,
            exercises: [],
            userParameters: [],
            workouts: [
                MappedWorkout(
                    workout: workout,
                    blocks: [],
                    items: [],
                    alternatives: []
                ),
            ],
            primitiveWorkoutIDsToDelete: [workoutID],
            lastPerformed: []
        )
        try await AppBootstrap.savePull(result, into: factory.workoutCache)

        let primitiveWorkouts = try await factory.workoutCache.loadPrimitiveWorkouts()
        XCTAssertTrue(primitiveWorkouts.isEmpty)
        let workouts = try await factory.workoutCache.loadWorkouts(status: nil, since: nil)
        XCTAssertEqual(workouts.map(\.id), [workoutID])
    }

    // MARK: - qa-027 · completed-only cache stays in .ready

    /// qa-027: cold-launch after the user has completed all planned
    /// workouts (cache has completed rows but no planned ones) must
    /// resolve to `.ready` with an empty-glance TodayViewModel — not
    /// `.empty`. The full-screen `.empty` shell hides the History tab
    /// entirely, which stranded the user from their own logged sessions.
    /// Contract: shell stays on the tabbed root; Today renders
    /// `isEmpty == true` (the qa-008 empty-glance path); History
    /// resolves via its own load path.
    func testColdLaunchWithCompletedOnlyWorkoutsStaysInReady() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )

        // Seed the cache with a single COMPLETED workout (no planned
        // rows). Mirrors the post-"save & done all" end-state the qa-027
        // repro describes: every planned workout has been finished and
        // persisted locally.
        let userID = UUID()
        let workoutID = UUID()
        let completedAt = ISO8601DateFormatter().date(from: "2026-04-17T09:00:00Z")!
        let completedWorkout = Workout(
            id: workoutID,
            userID: userID,
            name: "Push A (completed)",
            scheduledDate: completedAt,
            status: .completed,
            source: .claude,
            notes: nil,
            createdAt: completedAt,
            updatedAt: completedAt,
            completedAt: completedAt,
            tagsJSON: nil
        )
        try await factory.workoutCache.saveWorkout(completedWorkout)

        // Bootstrap with a failing transport so the pull can't refill the
        // cache with a planned row. TodayLoader then returns nil
        // (`.planned` filter hits no rows), and the fix path must still
        // land in `.ready`.
        let transport = ScriptedTransport(
            getOutcomes: [.error(.network("dns"))]
        )
        var didRequestBootstrapRerun = false
        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: completedAt,
            transportBuilder: { _ in transport },
            onEmptyTodayRefresh: {
                didRequestBootstrapRerun = true
                return true
            }
        )

        guard case let .ready(todayVM, executionHolder, _) = result else {
            return XCTFail("expected .ready for completed-only cache, got \(result)")
        }

        // Today is in its empty-glance state — the qa-008 contract guards
        // the start button so there's no nil-VM dispatch risk.
        XCTAssertTrue(
            todayVM.isEmpty,
            "empty-glance VM must have isEmpty == true"
        )
        XCTAssertFalse(
            todayVM.showsStartButton,
            "empty-glance VM must hide the start button (qa-008)"
        )
        XCTAssertNil(todayVM.workoutID)
        XCTAssertTrue(todayVM.exercises.isEmpty)
        XCTAssertTrue(todayVM.canRefresh)

        await todayVM.refresh()

        XCTAssertTrue(didRequestBootstrapRerun)
        XCTAssertEqual(todayVM.refreshState, .idle)

        // `RootTabView` reads `holder.vm` — nil routes to `TodayView`
        // which renders the empty glance. No ExecutionViewModel is built
        // here because there's no WorkoutContext to anchor one to.
        XCTAssertNil(
            executionHolder.vm,
            "no planned workout → no execution VM; History is still reachable"
        )

        // Confirm the cache actually holds the completed workout — this
        // is the whole signal that drove us into `.ready` instead of
        // `.empty`.
        let completed = try await factory.workoutCache.loadCompletedWorkouts(
            limit: 10, offset: 0
        )
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(completed.first?.id, workoutID)
    }

    // MARK: - Push path wired through the bootstrap

    /// The wired ExecutionViewModel must route a logged primitive set into the
    /// shared PushQueueStore via its injected enqueuer. We observe the
    /// store directly — a single enqueue per logSet, with the
    /// corresponding PrimitiveSetLog shape.
    func testWiredExecutionViewModelEnqueuesPrimitiveSetLogOnLog() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let fixture = Fixtures.sampleWorkoutPayload()
        let transport = ScriptedTransport(
            getOutcomes: [.ok(fixture.json)]
        )

        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: fixture.scheduledDate,
            transportBuilder: { _ in transport }
        )
        guard case let .ready(_, executionHolder, _) = result else {
            return XCTFail("expected .ready, got \(result)")
        }

        let executionVM = try XCTUnwrap(executionHolder.vm)
        executionVM.start()
        executionVM.startCurrentSet()
        executionVM.logSet(reps: 5, rir: 2)

        // Push enqueue is fire-and-forget from the UI mutation path.
        // Give the detached Task a moment to reach the store.
        try await Task.sleep(nanoseconds: 100_000_000)

        let pending = try await factory.pushQueueStore.peek(max: 8)
        XCTAssertEqual(pending.count, 1)
        let item = try XCTUnwrap(pending.first)
        guard case .primitiveSetLogs(let logs) = item.payload else {
            return XCTFail("expected primitiveSetLogs payload, got \(item.payload)")
        }
        XCTAssertEqual(logs.count, 1)
        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.role, .slot)
        XCTAssertEqual(log.setIndex, 0)
        XCTAssertEqual(log.reps, 5)
        XCTAssertEqual(log.rir, 2)
        XCTAssertEqual(log.weight, 102.5)
        XCTAssertFalse(log.isWarmup)
    }

    // MARK: - Save & done writes completion to the local cache

    /// After the user logs every set and taps "Save & done", the wired
    /// view-model must write a `.completed` workout + its primitive result logs
    /// to the local WorkoutCache. Guards the History-tab-backfill invariant from
    /// `docs/open-questions.md` § "Execution `save & done` doesn't persist
    /// the completed workout to local cache".
    func testSaveAndDoneWritesCompletedWorkoutToLocalCache() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let fixture = Fixtures.sampleWorkoutPayload()
        let transport = ScriptedTransport(
            getOutcomes: [.ok(fixture.json)]
        )
        let telemetry = ShellTelemetryRecorder()

        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: fixture.scheduledDate,
            transportBuilder: { _ in transport },
            telemetryEmitter: telemetry
        )
        guard case let .ready(_, executionHolder, _) = result else {
            return XCTFail("expected .ready, got \(result)")
        }

        let executionVM = try XCTUnwrap(executionHolder.vm)
        // Drive the session to completion. Fixture: 1 block, 2 items
        // (4 sets, then 3 sets). The fixture's timing_config_json is
        // empty so `restDuration` is 0 and the view model auto-advances
        // after each `logSet` — no explicit `.advance()` calls needed.
        // Each set still needs the user-visible Set Start boundary first.
        executionVM.start()
        for _ in 0..<4 {
            executionVM.startCurrentSet()
            executionVM.logSet(reps: 5, rir: 2)
        }
        for _ in 0..<3 {
            executionVM.startCurrentSet()
            executionVM.logSet(reps: 8, rir: 2)
        }
        XCTAssertEqual(executionVM.state.route, .complete)

        executionVM.saveAndDone()

        // Fire-and-forget: give the detached Task a moment to reach the
        // cache actor.
        try await Task.sleep(nanoseconds: 100_000_000)

        let completed = try await factory.workoutCache.loadCompletedWorkouts(limit: 10, offset: 0)
        XCTAssertEqual(completed.count, 1)
        let saved = try XCTUnwrap(completed.first)
        XCTAssertEqual(saved.id, fixture.domainWorkout.id)
        XCTAssertEqual(saved.status, .completed)
        XCTAssertNotNil(saved.completedAt)

        let logs = try await factory.workoutCache.loadPrimitiveSetLogs(workoutID: saved.id)
        XCTAssertEqual(logs.count, 7)
        XCTAssertTrue(logs.allSatisfy { $0.reps != nil })

        let postPaths = await transport.store.snapshotPostPaths()
        XCTAssertTrue(postPaths.contains("/api/sync/results"))
        let resultBodies = await transport.store.snapshotPostBodies()
        let syncResultsPayloads = resultBodies.compactMap { body in
            try? JSONDecoder.workoutDB().decode(SyncResultsPayload.self, from: body)
        }
        XCTAssertEqual(
            syncResultsPayloads.filter { $0.primitiveSetLogs.isEmpty && !$0.statusUpdates.isEmpty }.count,
            0,
            "Save & Done must not emit a second standalone status-only results push"
        )
        let completionPayload = try XCTUnwrap(
            syncResultsPayloads.first { !$0.primitiveSetLogs.isEmpty && !$0.statusUpdates.isEmpty }
        )
        XCTAssertEqual(completionPayload.primitiveSetLogs.count, 7)
        XCTAssertEqual(completionPayload.statusUpdates.count, 1)
        XCTAssertEqual(
            completionPayload.statusUpdates[0].workoutId,
            fixture.domainWorkout.id.uuidString.lowercased()
        )
        XCTAssertEqual(completionPayload.statusUpdates[0].status, WorkoutDBSchema.WorkoutStatus.completed)

        let completionEvents = telemetry.events.filter {
            $0.name.hasPrefix("execution.completion_")
        }
        XCTAssertEqual(
            completionEvents.map(\.name),
            [
                "execution.completion_record_built",
                "execution.completion_publish_finished",
                "execution.completion_local_cache_write_succeeded",
                "execution.completion_local_writer_completed",
            ]
        )
        XCTAssertTrue(
            completionEvents.allSatisfy { $0.workoutID == fixture.domainWorkout.id },
            "every completion proof event must carry the completed workout id"
        )
        let payloads = try completionEvents.map(Self.decodeTelemetryPayload)
        let workoutID = fixture.domainWorkout.id.uuidString.lowercased()
        XCTAssertTrue(payloads.allSatisfy { $0["workout_id"] as? String == workoutID })
        XCTAssertTrue(payloads.allSatisfy { $0["set_log_count"] as? Int == 0 })
        XCTAssertTrue(payloads.allSatisfy { $0["primitive_set_log_count"] as? Int == 7 })
        XCTAssertTrue(payloads.allSatisfy { $0["has_note"] as? Bool == false })
        XCTAssertEqual(payloads[1]["publisher_installed"] as? Bool, true)
    }

    // MARK: - Post-save VM rebuild (qa-002 / qa-003)

    /// Regression test for qa-002 / qa-003. After the user completes
    /// workout A and taps Save & Done, the shell MUST install a fresh
    /// `ExecutionViewModel` on the holder pointing at workout B. The
    /// old pre-rebuild behavior re-used the just-emptied VM from A —
    /// tapping Start on B flipped that VM to `.active` with no items
    /// and ActiveView rendered its "no active set" defensive fallback.
    ///
    /// This test drives A to completion through the wired bootstrap
    /// path, fires `saveAndDone`, waits for the detached completion
    /// writer to run, and asserts:
    ///   1. `holder.vm` is a DIFFERENT instance than the one that
    ///      completed workout A.
    ///   2. The new VM's context points at workout B (not A).
    ///   3. Starting the new VM produces a non-nil `activeContent` —
    ///      proof the VM is backed by real items, not the empty
    ///      post-save structure.
    func testSaveAndDoneRebuildsExecutionViewModelForNextWorkout() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let (workoutA, workoutB) = Fixtures.twoPlannedWorkouts()
        // Prime the cache with both workouts. Offline path — no transport
        // fetch needed, bootstrap falls through to the cache.
        try await factory.workoutCache.save(
            PulledDataset(
                workouts: [workoutA.workout, workoutB.workout],
                blocks: workoutA.blocks + workoutB.blocks,
                items: workoutA.items + workoutB.items,
                alternatives: [],
                exercises: workoutA.exercises + workoutB.exercises,
                userParameters: []
            )
        )

        let transport = ScriptedTransport(getOutcomes: [.error(.network("dns"))])
        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: workoutA.workout.scheduledDate!,
            transportBuilder: { _ in transport }
        )
        guard case let .ready(_, holder, _) = result else {
            return XCTFail("expected .ready, got \(result)")
        }

        let vmA = try XCTUnwrap(holder.vm)
        XCTAssertEqual(
            vmA.context.workout.id, workoutA.workout.id,
            "bootstrap should select workout A (earlier scheduled date)"
        )

        // Drive A to completion via the same path the UI takes.
        vmA.start()
        // Workout A has 1 block × 1 item × 1 set — single logSet completes.
        vmA.startCurrentSet()
        vmA.logSet(reps: 5, rir: 2)
        XCTAssertEqual(vmA.state.route, .complete, "A should be on Complete")

        vmA.saveAndDone()

        // The completion writer runs on a detached Task — it writes the
        // cache, reloads Today, then rebuilds the VM. Give it a window
        // longer than the write + reload path.
        try await Task.sleep(nanoseconds: 400_000_000)

        let vmB = try XCTUnwrap(holder.vm, "holder.vm must not be nil after save")
        XCTAssertFalse(
            vmB === vmA,
            "post-save VM must be a new instance — re-using vmA is the qa-002 bug"
        )
        XCTAssertEqual(
            vmB.context.workout.id, workoutB.workout.id,
            "post-save VM must be built for the next workout (B)"
        )
        XCTAssertEqual(vmB.state.route, .today, "fresh VM starts on Today route")

        // Start the new VM and verify it has real content. The old bug
        // surfaced as `activeContent == nil` → ActiveView "no active set".
        vmB.start()
        XCTAssertEqual(vmB.state.route, .active)
        XCTAssertNotNil(
            vmB.activeContent,
            "new VM must produce non-nil activeContent — nil is the qa-002 symptom"
        )
    }

    func testTodayCanStartNonSelectedPlannedWorkout() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let (workoutA, workoutB) = Fixtures.twoPlannedWorkouts()
        try await factory.workoutCache.save(
            PulledDataset(
                workouts: [workoutA.workout, workoutB.workout],
                blocks: workoutA.blocks + workoutB.blocks,
                items: workoutA.items + workoutB.items,
                alternatives: [],
                exercises: workoutA.exercises + workoutB.exercises,
                userParameters: []
            )
        )

        let transport = ScriptedTransport(getOutcomes: [.error(.network("dns"))])
        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: workoutA.workout.scheduledDate!,
            transportBuilder: { _ in transport }
        )
        guard case let .ready(todayVM, holder, _) = result else {
            return XCTFail("expected .ready, got \(result)")
        }
        let vmA = try XCTUnwrap(holder.vm)
        XCTAssertEqual(vmA.context.workout.id, workoutA.workout.id)

        await todayVM.start(workoutID: workoutB.workout.id)

        let vmB = try XCTUnwrap(holder.vm)
        XCTAssertFalse(vmB === vmA)
        XCTAssertEqual(vmB.context.workout.id, workoutB.workout.id)
        XCTAssertEqual(vmB.state.route, .active)
        XCTAssertNotNil(vmB.activeContent)
    }

    func testTodayStartNonSelectedPlannedWorkoutRebuildsPrimitivePlanFromCache() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let (workoutA, workoutB) = Fixtures.twoPlannedWorkouts()
        let parameterKey = "one_rep_max_\(workoutB.exercises[0].id.uuidString.lowercased())_kg"
        let primitiveB = PrimitiveWorkout(
            id: workoutB.workout.id,
            name: workoutB.workout.name,
            blocks: [
                PrimitiveBlock(id: workoutB.blocks[0].id, sets: [
                    PrimitiveSet(
                        id: UUID(uuidString: "b4000000-0000-0000-0000-000000000000")!,
                        timing: PrimitiveTiming(mode: .setBounded),
                        slots: [
                            PrimitiveSlot(
                                id: UUID(uuidString: "b5000000-0000-0000-0000-000000000000")!,
                                exerciseID: workoutB.exercises[0].id,
                                workTargets: [
                                    PrimitiveWorkTarget(
                                        metric: .reps,
                                        valueForm: .single,
                                        value: 3,
                                        role: .completion
                                    ),
                                ],
                                load: PrimitiveLoad(value: 0.8, unit: .oneRepMax, unitType: .relative)
                            ),
                        ]
                    ),
                ]),
            ]
        )
        try await factory.workoutCache.save(
            PulledDataset(
                workouts: [workoutA.workout, workoutB.workout],
                primitiveWorkouts: [primitiveB],
                blocks: workoutA.blocks + workoutB.blocks,
                items: workoutA.items + workoutB.items,
                alternatives: [],
                exercises: workoutA.exercises + workoutB.exercises,
                userParameters: [
                    UserParameter(
                        id: UUID(uuidString: "b6000000-0000-0000-0000-000000000000")!,
                        userID: workoutB.workout.userID,
                        key: parameterKey,
                        value: "140",
                        updatedAt: workoutB.workout.scheduledDate ?? Date(timeIntervalSince1970: 0),
                        source: .manual
                    ),
                ]
            )
        )

        let transport = ScriptedTransport(getOutcomes: [.error(.network("dns"))])
        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: workoutA.workout.scheduledDate!,
            transportBuilder: { _ in transport }
        )
        guard case let .ready(todayVM, holder, _) = result else {
            return XCTFail("expected .ready, got \(result)")
        }
        let vmA = try XCTUnwrap(holder.vm)
        XCTAssertEqual(vmA.context.workout.id, workoutA.workout.id)

        await todayVM.start(workoutID: workoutB.workout.id)

        let vmB = try XCTUnwrap(holder.vm)
        XCTAssertFalse(vmB === vmA)
        XCTAssertEqual(vmB.context.workout.id, workoutB.workout.id)
        XCTAssertEqual(vmB.context.primitiveWorkout, primitiveB)
        XCTAssertEqual(vmB.context.primitiveExecutionPlan?.workoutID, workoutB.workout.id)
        XCTAssertEqual(vmB.context.primitiveExecutionPlan?.blocks[0].sets[0].slots[0].loadKg, 112)
        XCTAssertEqual(vmB.context.primitiveExecutionPlan?.blocks[0].sets[0].slots[0].loadUnit, .kg)
        XCTAssertEqual(vmB.state.route, .active)
        XCTAssertNotNil(vmB.activeContent)
    }

    /// qa-030 root-cause regression: after the post-save VM rebuild, the
    /// newly-installed `ExecutionViewModel` must still carry the
    /// `onUserParameterChanged` hook so a bodyweight typed on workout
    /// B's Complete screen lands in `user_parameters`. Fix-it L
    /// introduced the rebuild path (`rebuildExecutionVMForNextWorkout`)
    /// and the hazard was that the hook wire-up only lived on the initial
    /// VM; the rebuild factory needs to capture every field of
    /// `ExecutionPushHooks`, not just the set-log hook.
    ///
    /// Methodology: drive workout A to completion, save, wait for the
    /// rebuild, then save workout B with a bodyweight. The test's
    /// `onUserParameterChanged` recorder must see the push — if the hook
    /// got dropped on rebuild, the recorder stays empty.
    func testRebuildExecutionVMRetainsOnUserParameterChangedHook() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let (workoutA, workoutB) = Fixtures.twoPlannedWorkouts()
        try await factory.workoutCache.save(
            PulledDataset(
                workouts: [workoutA.workout, workoutB.workout],
                blocks: workoutA.blocks + workoutB.blocks,
                items: workoutA.items + workoutB.items,
                alternatives: [],
                exercises: workoutA.exercises + workoutB.exercises,
                userParameters: []
            )
        )

        let transport = ScriptedTransport(getOutcomes: [.error(.network("dns"))])
        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: workoutA.workout.scheduledDate!,
            transportBuilder: { _ in transport }
        )
        guard case let .ready(_, holder, _) = result else {
            return XCTFail("expected .ready, got \(result)")
        }

        // Drive A to completion and save. Bodyweight omitted — that's
        // the pre-rebuild push path, which already has dedicated
        // coverage in `testSaveAndDoneEnqueuesBodyweightUserParameter`.
        let vmA = try XCTUnwrap(holder.vm)
        vmA.start()
        vmA.startCurrentSet()
        vmA.logSet(reps: 5, rir: 2)
        vmA.saveAndDone()
        try await Task.sleep(nanoseconds: 400_000_000)

        let vmB = try XCTUnwrap(holder.vm, "holder must carry the rebuilt VM for workout B")
        XCTAssertFalse(vmB === vmA, "precondition: rebuild produced a new VM")
        XCTAssertNotNil(
            vmB.push.onUserParameterChanged,
            "rebuilt VM must retain the onUserParameterChanged hook — " +
            "dropping it is the qa-030 regression hazard"
        )
        XCTAssertNotNil(
            vmB.push.onPrimitiveSetLogged,
            "rebuilt VM must retain onPrimitiveSetLogged (sanity: the whole hooks " +
            "bundle must survive the rebuild, not just one field)"
        )
        XCTAssertNotNil(
            vmB.push.onWorkoutCompleted,
            "rebuilt VM must retain onWorkoutCompleted"
        )
        XCTAssertNotNil(
            vmB.push.onPushKick,
            "rebuilt VM must retain onPushKick so post-save flush still fires"
        )

        // Behavior check: drive B through completion with a bodyweight,
        // then assert a bodyweight row landed in the local cache. The
        // shell-wired `onUserParameterChanged` writes to WorkoutCache
        // before enqueuing the push — the cache is the ground truth for
        // "the hook fired".
        vmB.start()
        vmB.startCurrentSet()
        vmB.logSet(reps: 5, rir: 2)
        vmB.saveAndDone(bodyweightKg: 82.5)
        try await Task.sleep(nanoseconds: 400_000_000)

        let cachedRows = try await factory.workoutCache.loadUserParameters(
            key: "bodyweight_kg"
        )
        XCTAssertEqual(
            cachedRows.count, 1,
            "bodyweight on the rebuilt VM must reach the cache via the " +
            "retained onUserParameterChanged hook"
        )
        XCTAssertEqual(cachedRows.first?.value, "82.5")
    }

    /// Regression test for the terminal "no more planned workouts" path.
    /// When the user completes their last queued workout, `TodayLoader`
    /// returns `nil` and the completion writer must set `holder.vm = nil`
    /// (rather than leaving the emptied VM in place). Today's empty state
    /// (isEmpty == true) guards the start button so the nil VM is never
    /// dispatched to (qa-008 interaction).
    func testSaveAndDoneLeavesHolderNilWhenNoNextWorkout() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let fixture = Fixtures.sampleWorkoutPayload()
        let transport = ScriptedTransport(getOutcomes: [.ok(fixture.json)])
        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: fixture.scheduledDate,
            transportBuilder: { _ in transport }
        )
        guard case let .ready(_, holder, _) = result else {
            return XCTFail("expected .ready, got \(result)")
        }

        let vm = try XCTUnwrap(holder.vm)
        vm.start()
        // Fixture: 4 sets + 3 sets = 7 logs to finish.
        for _ in 0..<4 {
            vm.startCurrentSet()
            vm.logSet(reps: 5, rir: 2)
        }
        for _ in 0..<3 {
            vm.startCurrentSet()
            vm.logSet(reps: 8, rir: 2)
        }
        XCTAssertEqual(vm.state.route, .complete)

        vm.saveAndDone()
        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertNil(
            holder.vm,
            "holder.vm must be nil when no next planned workout remains"
        )
    }

    // MARK: - Offline + populated cache → .ready from cache

    func testBootstrapWithFailedPullFallsBackToCache() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )

        // Prime the cache manually — same shape the pull would have
        // produced.
        let fixture = Fixtures.sampleWorkoutPayload()
        try await factory.workoutCache.save(
            PulledDataset(
                workouts: [fixture.domainWorkout],
                blocks: fixture.domainBlocks,
                items: fixture.domainItems,
                alternatives: [],
                exercises: fixture.domainExercises,
                userParameters: []
            )
        )

        let transport = ScriptedTransport(
            getOutcomes: [.error(.network("dns"))]
        )

        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: fixture.scheduledDate,
            transportBuilder: { _ in transport }
        )
        guard case let .ready(_, executionHolder, _) = result else {
            return XCTFail("expected .ready from cache, got \(result)")
        }
        let executionVM = try XCTUnwrap(executionHolder.vm)
        XCTAssertEqual(executionVM.context.workout.name, "Push A")
    }

    // MARK: - Early-launch telemetry reaches the push queue

    /// Regression: the very first `bootstrap.start` event must enqueue
    /// into the push queue, not just land in the local `EventModel` row.
    ///
    /// Old behaviour: `PersistenceFactory.init` fired
    /// `Task { await emitter.attach(pushQueueStore: ...) }` and returned.
    /// `AppBootstrap.bootstrap` then emitted `bootstrap.start` on the very
    /// next MainActor tick — before that detached task had reached the
    /// actor. The event persisted locally but the emitter's
    /// `pushQueueStore` was still nil, so `emit` skipped the enqueue
    /// branch. Events stranded on disk indefinitely, never reached the
    /// server, and telemetry for launch-time failures (the ones you most
    /// need to see) disappeared.
    ///
    /// Fix: `bootstrap(...)` awaits `persistence.prepareTelemetry()`
    /// before the first emit. Calling the same method twice is a no-op.
    /// This test drives a bootstrap that will produce `.empty` (failing
    /// pull on an empty cache) and confirms the push queue nonetheless
    /// holds a telemetry event — proof the attach completed before emit.
    func testBootstrapStartEventEnqueuedBeforeFirstEmit() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        // Network failure + empty cache → .empty. The path is irrelevant;
        // what matters is that bootstrap emits at least one event before
        // returning. `bootstrap.start` fires first, `bootstrap.empty`
        // after the pull-failure catch and TodayLoader.load returns nil.
        let transport = ScriptedTransport(
            getOutcomes: [.error(.network("dns"))]
        )

        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: Date(),
            transportBuilder: { _ in transport },
            telemetryEmitter: factory.telemetryEmitter()
        )
        assertEmpty(result)

        // Emit is fire-and-forget from the caller's perspective — the
        // TelemetryEmitterImpl hops onto its actor via Task.detached.
        // Give the actor a chance to land both the local persist AND the
        // enqueue before we assert. A small sleep is the simplest way
        // that mirrors how the app itself doesn't block on telemetry.
        try await Task.sleep(nanoseconds: 300_000_000)

        let pending = try await factory.pushQueueStore.peek(max: 32)
        let eventItems = pending.filter {
            if case .events = $0.payload { return true }
            return false
        }
        XCTAssertGreaterThanOrEqual(
            eventItems.count,
            1,
            "expected bootstrap.* events to reach the push queue; " +
            "found \(eventItems.count) of \(pending.count) total items"
        )

        // The very first emit (`bootstrap.start`) must be among them.
        var names: [String] = []
        for item in eventItems {
            if case .events(let events) = item.payload {
                names.append(contentsOf: events.map { $0.name })
            }
        }
        XCTAssertTrue(
            names.contains("bootstrap.start"),
            "expected bootstrap.start in push queue, got \(names)"
        )
    }

    // MARK: - qa-001 / qa-020 — lastPerformed threaded pull → UI

    /// When the pull carries a `last_performed` snapshot, the bootstrap
    /// must (a) persist it into the `LastPerformedStore` for offline
    /// restart, (b) thread the resulting `[UUID: String]` map onto the
    /// initial `TodayViewModel.exercises[*].lastTime` chips, and (c)
    /// surface the same map on `ExecutionViewModel.context.lastPerformed`
    /// so SwapSheet's "LAST · …" row resolves per-alternative. The
    /// threading was missing even though `PullService.lastPerformed`
    /// decoded correctly (bug-009 era); the pulled snapshot landed
    /// nowhere and both UI surfaces rendered blank.
    func testBootstrapThreadsLastPerformedToTodayAndExecution() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let fixture = Fixtures.sampleWorkoutPayload(includeLastPerformed: true)
        let transport = ScriptedTransport(
            getOutcomes: [.ok(fixture.json)]
        )

        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: fixture.scheduledDate,
            transportBuilder: { _ in transport }
        )
        guard case let .ready(todayVM, executionHolder, _) = result else {
            return XCTFail("expected .ready, got \(result)")
        }

        // Fixture emits lastPerformed for both Push A exercises: bench
        // (1 set × 5 @ 100 kg · RIR 2 → single working set) and row
        // (3 working sets × 8 @ 77.5 kg · RIR 1). The formatter picks
        // the heaviest working set as the representative line, so both
        // rows should surface non-nil chip strings.
        let benchID = fixture.domainExercises[0].id
        let rowID = fixture.domainExercises[1].id
        let todayBench = todayVM.exercises.first { $0.name == "Barbell Bench Press" }
        let todayRow = todayVM.exercises.first { $0.name == "Barbell Row" }
        XCTAssertEqual(todayBench?.lastTime, "1×5 @ 100 kg · RIR 2")
        XCTAssertEqual(todayRow?.lastTime, "3×8 @ 77.5 kg · RIR 1")

        // The ExecutionViewModel's context carries the same map.
        let executionVM = try XCTUnwrap(executionHolder.vm)
        XCTAssertEqual(
            executionVM.context.lastPerformed[benchID],
            "1×5 @ 100 kg · RIR 2"
        )
        XCTAssertEqual(
            executionVM.context.lastPerformed[rowID],
            "3×8 @ 77.5 kg · RIR 1"
        )

        // Persisted copy survives into the store so an offline restart
        // (pull fails, cache hydrates) still renders the chips.
        let stored = await factory.lastPerformedStore.load()
        XCTAssertEqual(stored[benchID], "1×5 @ 100 kg · RIR 2")
        XCTAssertEqual(stored[rowID], "3×8 @ 77.5 kg · RIR 1")
    }

    /// Offline restart after a previous successful pull. The bootstrap's
    /// transport throws `.network`, but the cache + lastPerformed store
    /// are both populated from a prior run. The chips must still render.
    func testBootstrapHydratesLastPerformedFromStoreWhenOffline() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let fixture = Fixtures.sampleWorkoutPayload()
        // Prime the cache with the workout shape only — last_performed
        // payload on the fixture is unused here because we're writing
        // the store directly (mirrors what a prior successful bootstrap
        // would have left on disk).
        try await factory.workoutCache.save(
            PulledDataset(
                workouts: [fixture.domainWorkout],
                blocks: fixture.domainBlocks,
                items: fixture.domainItems,
                alternatives: [],
                exercises: fixture.domainExercises,
                userParameters: []
            )
        )
        let benchID = fixture.domainExercises[0].id
        await factory.lastPerformedStore.save([
            benchID: "4×5 @ 100 kg · RIR 2",
        ])

        let transport = ScriptedTransport(
            getOutcomes: [.error(.network("dns"))]
        )
        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: fixture.scheduledDate,
            transportBuilder: { _ in transport }
        )
        guard case let .ready(todayVM, executionHolder, _) = result else {
            return XCTFail("expected .ready from cache, got \(result)")
        }

        let benchRow = todayVM.exercises.first { $0.name == "Barbell Bench Press" }
        XCTAssertEqual(benchRow?.lastTime, "4×5 @ 100 kg · RIR 2")

        let executionVM = try XCTUnwrap(executionHolder.vm)
        XCTAssertEqual(
            executionVM.context.lastPerformed[benchID],
            "4×5 @ 100 kg · RIR 2"
        )
    }

    /// qa-001 reopen regression — an incremental pull that returns an EMPTY
    /// `last_performed` array (e.g. a pre-fix server that scoped it to the
    /// delta, or a transient server regression) must NOT erase the chips
    /// the store already has. The previous behavior overwrote the store
    /// with whatever the pull returned, so the first empty response wiped
    /// every "LAST TIME" chip on the next Today render.
    ///
    /// This test seeds the store, runs a successful pull whose payload has
    /// `last_performed: []`, and asserts the store (and the VM) still
    /// surface the prior chip. Server-side fix in `api/sync.py` should
    /// make `[]` rare in practice, but the client stays defensive.
    func testBootstrapKeepsExistingLastPerformedWhenPullReturnsEmpty() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        // includeLastPerformed: false → fixture.json carries "last_performed": []
        let fixture = Fixtures.sampleWorkoutPayload()
        let benchID = fixture.domainExercises[0].id

        // Seed the store as if a prior successful pull had populated it.
        await factory.lastPerformedStore.save([
            benchID: "4×5 @ 100 kg · RIR 2",
        ])

        let transport = ScriptedTransport(
            getOutcomes: [.ok(fixture.json)]
        )
        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: fixture.scheduledDate,
            transportBuilder: { _ in transport }
        )
        guard case let .ready(todayVM, _, _) = result else {
            return XCTFail("expected .ready, got \(result)")
        }

        // The seeded chip survives the pull — the empty response does NOT
        // overwrite the store.
        let stored = await factory.lastPerformedStore.load()
        XCTAssertEqual(
            stored[benchID],
            "4×5 @ 100 kg · RIR 2",
            "empty last_performed in pull must not erase prior chip map"
        )
        let benchRow = todayVM.exercises.first { $0.name == "Barbell Bench Press" }
        XCTAssertEqual(
            benchRow?.lastTime,
            "4×5 @ 100 kg · RIR 2",
            "Today VM must render the prior chip when the pull returned []"
        )
    }

    // MARK: - qa-024 · cold-relaunch session restore

    /// Cold-launch with a persisted snapshot whose `route == .active` must
    /// land the user directly on the Execution surface for the restored
    /// cursor, NOT on Today. Pre-fix: `AppBootstrap.buildReady` constructed
    /// a fresh `ExecutionViewModel` and returned it without ever calling
    /// `restoreIfPossible`, so the seeded-from-context state always won
    /// and tapping Start on Today overwrote the snapshot. See
    /// `scratch/qa-runs/_investigations/qa-002-crash.md` § "Hypothesis 4".
    func testColdRelaunchRestoresActiveRoute() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let fixture = Fixtures.sampleWorkoutPayload()

        // Prime the cache so the offline bootstrap has a workout to
        // build its context around — same path as a prior successful
        // pull would have populated.
        try await factory.workoutCache.save(
            PulledDataset(
                workouts: [fixture.domainWorkout],
                blocks: fixture.domainBlocks,
                items: fixture.domainItems,
                alternatives: [],
                exercises: fixture.domainExercises,
                userParameters: []
            )
        )

        // Handcraft a mid-workout snapshot: route=.active, cursor on the
        // second set of the first item (user has logged set 1, is back in
        // .active for set 2). The structure mirrors the fixture: one
        // block, two items (4 sets + 3 sets).
        let snapshotState = SessionState(
            workoutID: fixture.domainWorkout.id,
            route: .active,
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 2),
            items: [],
            structure: SessionState.Structure(
                itemsPerBlock: [2],
                setsPerItem: [[4, 3]]
            )
        )
        let bytes = try JSONEncoder().encode(SessionStateCodable(state: snapshotState))
        try await factory.sessionStore.save(bytes)

        // Bootstrap with a failing transport so the cache fallback path
        // kicks in (pull isn't the subject here — restore is).
        let transport = ScriptedTransport(
            getOutcomes: [.error(.network("dns"))]
        )
        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: fixture.scheduledDate,
            transportBuilder: { _ in transport }
        )
        guard case let .ready(_, executionHolder, _) = result else {
            return XCTFail("expected .ready, got \(result)")
        }

        let executionVM = try XCTUnwrap(executionHolder.vm)
        // Route is the restored `.active` — RootTabView routes off this
        // directly to ExecutionView, skipping Today.
        XCTAssertEqual(executionVM.state.route, .active)
        // Cursor reflects the persisted mid-workout position, NOT the
        // seeded `(0, 0, 1)` an unrestored VM would carry.
        XCTAssertEqual(executionVM.state.cursor.blockIndex, 0)
        XCTAssertEqual(executionVM.state.cursor.itemIndex, 0)
        XCTAssertEqual(executionVM.state.cursor.setIndex, 2)
        // WorkoutID matches — the restore applied the correct snapshot.
        XCTAssertEqual(executionVM.state.workoutID, fixture.domainWorkout.id)
    }

    /// Cold-launch with a persisted snapshot whose `route == .rest` and
    /// an absolute `restEndsAt` must preserve the anchor — no "recompute
    /// from now - then" drift. The ring's remaining time derives from
    /// `restEndsAt - clock.now` at render time (per
    /// `docs/features/persistence.md` § S2). Here we only assert the
    /// absolute anchor survives the round-trip unchanged.
    func testColdRelaunchRestoresRestRouteWithRestEndsAt() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let fixture = Fixtures.sampleWorkoutPayload()
        try await factory.workoutCache.save(
            PulledDataset(
                workouts: [fixture.domainWorkout],
                blocks: fixture.domainBlocks,
                items: fixture.domainItems,
                alternatives: [],
                exercises: fixture.domainExercises,
                userParameters: []
            )
        )

        // Snapshot: mid-rest. `restEndsAt` is an absolute Date ~60s in
        // the future relative to some fixed reference; the bootstrap
        // path does NOT recompute it — the view reads it as-is and
        // renders `restEndsAt - now()`.
        let restEndsAt = Date(timeIntervalSince1970: 1_800_000_000 + 60)
        let snapshotState = SessionState(
            workoutID: fixture.domainWorkout.id,
            route: .rest,
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
            items: [],
            restEndsAt: restEndsAt,
            structure: SessionState.Structure(
                itemsPerBlock: [2],
                setsPerItem: [[4, 3]]
            )
        )
        let bytes = try JSONEncoder().encode(SessionStateCodable(state: snapshotState))
        try await factory.sessionStore.save(bytes)

        let transport = ScriptedTransport(
            getOutcomes: [.error(.network("dns"))]
        )
        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: fixture.scheduledDate,
            transportBuilder: { _ in transport }
        )
        guard case let .ready(_, executionHolder, _) = result else {
            return XCTFail("expected .ready, got \(result)")
        }

        let executionVM = try XCTUnwrap(executionHolder.vm)
        XCTAssertEqual(executionVM.state.route, .rest)
        XCTAssertEqual(
            executionVM.state.restEndsAt?.timeIntervalSince1970,
            restEndsAt.timeIntervalSince1970,
            "absolute restEndsAt must survive restore unchanged — " +
            "no 'recompute from now - then' drift per persistence.md § S2"
        )
    }

    /// Regression guard: cold-launch with NO persisted snapshot must
    /// behave like a first launch — route is `.today`, seeded cursor,
    /// no crash. The restore call is a silent no-op when `SessionStore.load()`
    /// returns nil.
    func testColdRelaunchWithNoSnapshotBehavesNormally() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let fixture = Fixtures.sampleWorkoutPayload()
        let transport = ScriptedTransport(
            getOutcomes: [.ok(fixture.json)]
        )

        // No snapshot seeded — SessionStore.load() returns nil.
        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: fixture.scheduledDate,
            transportBuilder: { _ in transport }
        )
        guard case let .ready(_, executionHolder, _) = result else {
            return XCTFail("expected .ready, got \(result)")
        }

        let executionVM = try XCTUnwrap(executionHolder.vm)
        XCTAssertEqual(
            executionVM.state.route, .today,
            "no snapshot → seeded state stands → route .today"
        )
        XCTAssertEqual(executionVM.state.workoutID, fixture.domainWorkout.id)
    }

    /// Cold-launch with a post-save snapshot (the state written by the
    /// reducer's `.save`: route=.today, items=[], structure=empty,
    /// workoutID preserved) must land on Today — not crash, not resurrect
    /// a bogus session. This is the race covered by
    /// `docs/features/persistence.md` § S16: save+clear are both in
    /// flight and the snapshot MAY reflect the emptied post-save state
    /// if the clear hasn't landed yet.
    ///
    /// The normalization guard in `normalizeRestoredState` short-circuits
    /// on route=.today — so the restored state is applied verbatim and
    /// RootTabView routes to Today.
    func testColdRelaunchWithPostSaveSnapshotLandsOnToday() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let fixture = Fixtures.sampleWorkoutPayload()
        try await factory.workoutCache.save(
            PulledDataset(
                workouts: [fixture.domainWorkout],
                blocks: fixture.domainBlocks,
                items: fixture.domainItems,
                alternatives: [],
                exercises: fixture.domainExercises,
                userParameters: []
            )
        )

        // Post-save snapshot: exactly what the reducer's `.save`
        // handler writes — route=.today, items=[], empty structure,
        // workoutID preserved for the completed workout.
        let postSaveState = SessionState(
            workoutID: fixture.domainWorkout.id,
            route: .today,
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 1),
            items: [],
            structure: SessionState.Structure(
                itemsPerBlock: [],
                setsPerItem: []
            )
        )
        let bytes = try JSONEncoder().encode(SessionStateCodable(state: postSaveState))
        try await factory.sessionStore.save(bytes)

        let transport = ScriptedTransport(
            getOutcomes: [.error(.network("dns"))]
        )
        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: fixture.scheduledDate,
            transportBuilder: { _ in transport }
        )
        guard case let .ready(_, executionHolder, _) = result else {
            return XCTFail("expected .ready, got \(result)")
        }

        let executionVM = try XCTUnwrap(executionHolder.vm)
        XCTAssertEqual(
            executionVM.state.route, .today,
            "post-save snapshot has route=.today — restore lands on Today"
        )
    }

    /// Guard against a stale snapshot whose `workoutID` doesn't match the
    /// TodayLoader-selected workout (e.g. cross-day relaunch where the
    /// in-flight workout was yesterday's but today's `.planned` row now
    /// outranks it). Applying such a snapshot onto a different workout's
    /// context would index `state.structure` into the wrong block shape
    /// and corrupt timer anchors. The guard in `restoreIfPossible`
    /// discards the mismatched snapshot and the freshly-seeded state for
    /// the selected workout stands.
    func testColdRelaunchDiscardsSnapshotForDifferentWorkout() async throws {
        let factory = try PersistenceFactory.makeInMemory(
            tokenServiceName: uniqueService()
        )
        let fixture = Fixtures.sampleWorkoutPayload()
        try await factory.workoutCache.save(
            PulledDataset(
                workouts: [fixture.domainWorkout],
                blocks: fixture.domainBlocks,
                items: fixture.domainItems,
                alternatives: [],
                exercises: fixture.domainExercises,
                userParameters: []
            )
        )

        // Snapshot for a COMPLETELY DIFFERENT workoutID — the TodayLoader
        // will pick the fixture's workout, but the snapshot claims a
        // different one. The guard must discard.
        let strangerID = UUID()
        let snapshotState = SessionState(
            workoutID: strangerID,
            route: .active,
            cursor: SessionState.Cursor(blockIndex: 0, itemIndex: 0, setIndex: 2),
            items: [],
            structure: SessionState.Structure(
                itemsPerBlock: [1],
                setsPerItem: [[5]]
            )
        )
        let bytes = try JSONEncoder().encode(SessionStateCodable(state: snapshotState))
        try await factory.sessionStore.save(bytes)

        let transport = ScriptedTransport(
            getOutcomes: [.error(.network("dns"))]
        )
        let result = try await AppBootstrap.bootstrap(
            connection: (url: URL(string: "https://example.test")!, token: "tok"),
            persistence: factory,
            now: fixture.scheduledDate,
            transportBuilder: { _ in transport }
        )
        guard case let .ready(_, executionHolder, _) = result else {
            return XCTFail("expected .ready, got \(result)")
        }

        let executionVM = try XCTUnwrap(executionHolder.vm)
        // Freshly-seeded state stands: route=.today, workoutID matches
        // the TodayLoader-selected workout, NOT the stranger ID.
        XCTAssertEqual(executionVM.state.route, .today)
        XCTAssertEqual(executionVM.state.workoutID, fixture.domainWorkout.id)
        XCTAssertNotEqual(executionVM.state.workoutID, strangerID)
    }

    // MARK: - Helpers

    private func uniqueService() -> String {
        "com.ericfeunekes.WorkoutDB.token.test.\(UUID().uuidString)"
    }

    private func emptyPullJSON(serverTime: Date) -> Data {
        let serverTimeString = ISO8601DateFormatter().string(from: serverTime)
        return """
        {
          "workouts": [],
          "exercises": [],
          "user_parameters": [],
          "last_performed": [],
          "server_time": "\(serverTimeString)"
        }
        """.data(using: .utf8)!
    }

    private func emptyPrimitiveBlocksJSON(from payload: Data) throws -> Data {
        let decoded = try JSONSerialization.jsonObject(with: payload)
        var root = try XCTUnwrap(decoded as? [String: Any])
        var workouts = try XCTUnwrap(root["workouts"] as? [[String: Any]])
        workouts[0]["primitive_blocks"] = []
        root["workouts"] = workouts
        return try JSONSerialization.data(withJSONObject: root)
    }

    private func assertEmpty(
        _ result: BootstrapResult,
        _ message: String = "expected .empty"
    ) {
        guard case .empty = result else {
            return XCTFail("\(message), got \(result)")
        }
    }

    private static func decodeTelemetryPayload(
        _ event: Event
    ) throws -> [String: Any] {
        let raw = try XCTUnwrap(event.dataJSON)
        let data = try XCTUnwrap(raw.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(decoded as? [String: Any])
    }
}

final class ShellTelemetryRecorder: TelemetryEmitter, @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [Event] = []

    var events: [Event] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func emit(_ event: Event) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(event)
    }
}

private typealias DomainWorkout = CoreDomain.Workout
private typealias DomainWorkoutStatus = CoreDomain.WorkoutStatus
private typealias DomainPrimitiveWorkout = CoreDomain.PrimitiveWorkout
private typealias DomainBlock = CoreDomain.Block
private typealias DomainWorkoutItem = CoreDomain.WorkoutItem
private typealias DomainExerciseAlternative = CoreDomain.ExerciseAlternative
private typealias DomainExercise = CoreDomain.Exercise
private typealias DomainUserParameter = CoreDomain.UserParameter
private typealias DomainSetLog = CoreDomain.SetLog
private typealias DomainPrimitiveSetLog = CoreDomain.PrimitiveSetLog

private final class EmptyWorkoutContextCache: WorkoutCache, @unchecked Sendable {
    private let workout: DomainWorkout

    init(workout: DomainWorkout) {
        self.workout = workout
    }

    func save(_ dataset: PulledDataset) async throws {}
    func loadWorkouts(status: DomainWorkoutStatus?, since: Date?) async throws -> [DomainWorkout] { [workout] }
    func loadPrimitiveWorkouts() async throws -> [DomainPrimitiveWorkout] { [] }
    func loadBlocks(workoutID: WorkoutID) async throws -> [DomainBlock] { [] }
    func loadItems(blockID: BlockID) async throws -> [DomainWorkoutItem] { [] }
    func loadItems(workoutIDs: [WorkoutID]) async throws -> [WorkoutID: [DomainWorkoutItem]] { [:] }
    func loadAlternatives(workoutItemID: WorkoutItemID) async throws -> [DomainExerciseAlternative] { [] }
    func loadExercises() async throws -> [DomainExercise] { [] }
    func loadUserParametersLatest() async throws -> [String: DomainUserParameter] { [:] }
    func loadUserParameters(key: String) async throws -> [DomainUserParameter] { [] }
    func loadCompletedWorkouts(limit: Int, offset: Int) async throws -> [DomainWorkout] { [] }
    func loadSetLogs(workoutID: WorkoutID) async throws -> [DomainSetLog] { [] }
    func loadPrimitiveSetLogs(workoutID: WorkoutID) async throws -> [DomainPrimitiveSetLog] { [] }
    func loadSetLogs(exerciseID: ExerciseID, limit: Int) async throws -> [DomainSetLog] { [] }
    func loadOrphanedSetLogs() async throws -> [DomainSetLog] { [] }
    func saveSetLogs(_ setLogs: [DomainSetLog], workoutID: WorkoutID) async throws {}
    func savePrimitiveSetLogs(_ setLogs: [DomainPrimitiveSetLog], workoutID: WorkoutID) async throws {}
    func resetWorkout(workoutID: WorkoutID) async throws {}
    func saveWorkout(_ workout: DomainWorkout) async throws {}
    func saveUserParameter(_ param: DomainUserParameter) async throws {}
    func clear() async throws {}
}

private final class ThrowingUserParameterCache: WorkoutCache, @unchecked Sendable {
    private let base: WorkoutCache
    private let error: Error

    init(base: WorkoutCache, error: Error) {
        self.base = base
        self.error = error
    }

    func save(_ dataset: PulledDataset) async throws { try await base.save(dataset) }
    func loadWorkouts(status: DomainWorkoutStatus?, since: Date?) async throws -> [DomainWorkout] {
        try await base.loadWorkouts(status: status, since: since)
    }
    func loadPrimitiveWorkouts() async throws -> [DomainPrimitiveWorkout] {
        try await base.loadPrimitiveWorkouts()
    }
    func loadBlocks(workoutID: WorkoutID) async throws -> [DomainBlock] {
        try await base.loadBlocks(workoutID: workoutID)
    }
    func loadItems(blockID: BlockID) async throws -> [DomainWorkoutItem] {
        try await base.loadItems(blockID: blockID)
    }
    func loadItems(workoutIDs: [WorkoutID]) async throws -> [WorkoutID: [DomainWorkoutItem]] {
        try await base.loadItems(workoutIDs: workoutIDs)
    }
    func loadAlternatives(workoutItemID: WorkoutItemID) async throws -> [DomainExerciseAlternative] {
        try await base.loadAlternatives(workoutItemID: workoutItemID)
    }
    func loadExercises() async throws -> [DomainExercise] { try await base.loadExercises() }
    func loadUserParametersLatest() async throws -> [String: DomainUserParameter] { throw error }
    func loadUserParameters(key: String) async throws -> [DomainUserParameter] {
        try await base.loadUserParameters(key: key)
    }
    func loadCompletedWorkouts(limit: Int, offset: Int) async throws -> [DomainWorkout] {
        try await base.loadCompletedWorkouts(limit: limit, offset: offset)
    }
    func loadSetLogs(workoutID: WorkoutID) async throws -> [DomainSetLog] {
        try await base.loadSetLogs(workoutID: workoutID)
    }
    func loadPrimitiveSetLogs(workoutID: WorkoutID) async throws -> [DomainPrimitiveSetLog] {
        try await base.loadPrimitiveSetLogs(workoutID: workoutID)
    }
    func loadSetLogs(exerciseID: ExerciseID, limit: Int) async throws -> [DomainSetLog] {
        try await base.loadSetLogs(exerciseID: exerciseID, limit: limit)
    }
    func loadOrphanedSetLogs() async throws -> [DomainSetLog] {
        try await base.loadOrphanedSetLogs()
    }
    func saveSetLogs(_ setLogs: [DomainSetLog], workoutID: WorkoutID) async throws {
        try await base.saveSetLogs(setLogs, workoutID: workoutID)
    }
    func savePrimitiveSetLogs(_ setLogs: [DomainPrimitiveSetLog], workoutID: WorkoutID) async throws {
        try await base.savePrimitiveSetLogs(setLogs, workoutID: workoutID)
    }
    func resetWorkout(workoutID: WorkoutID) async throws {
        try await base.resetWorkout(workoutID: workoutID)
    }
    func saveWorkout(_ workout: DomainWorkout) async throws { try await base.saveWorkout(workout) }
    func saveUserParameter(_ param: DomainUserParameter) async throws {
        try await base.saveUserParameter(param)
    }
    func clear() async throws { try await base.clear() }
}

private enum TestError: Error {
    case userParameters
}

// Equatable on BootstrapResult for `.empty` assertions only — the
// `.ready` case holds @MainActor view models and isn't structurally
// comparable. Restrict the conformance to the test bundle.
extension BootstrapResult: Equatable {
    public static func == (lhs: BootstrapResult, rhs: BootstrapResult) -> Bool {
        switch (lhs, rhs) {
        case (.empty, .empty): return true
        case (.ready, .ready): return true
        default: return false
        }
    }
}
