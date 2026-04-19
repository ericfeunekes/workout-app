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
import CoreTelemetry
import FeaturesExecution
import FeaturesToday
import Persistence
import Sync
import WorkoutCoreFoundation
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
        XCTAssertEqual(executionVM.context.blocks.count, 1)
        XCTAssertEqual(executionVM.context.itemsByBlock.first?.count, 2)

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
        XCTAssertEqual(result, .empty)
    }

    // MARK: - Push path wired through the bootstrap

    /// The wired ExecutionViewModel must route a logged set into the
    /// shared PushQueueStore via its injected enqueuer. We observe the
    /// store directly — a single enqueue per logSet, with the
    /// corresponding SetLog shape.
    func testWiredExecutionViewModelEnqueuesSetLogOnLog() async throws {
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
        executionVM.logSet(reps: 5, rir: 2)

        // Push enqueue is fire-and-forget from the UI mutation path.
        // Give the detached Task a moment to reach the store.
        try await Task.sleep(nanoseconds: 100_000_000)

        let pending = try await factory.pushQueueStore.peek(max: 8)
        XCTAssertEqual(pending.count, 1)
        let item = try XCTUnwrap(pending.first)
        guard case .setLogs(let logs) = item.payload else {
            return XCTFail("expected setLogs payload, got \(item.payload)")
        }
        XCTAssertEqual(logs.count, 1)
        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.setIndex, 1)
        XCTAssertEqual(log.reps, 5)
        XCTAssertEqual(log.rir, 2)
        XCTAssertEqual(log.weight, 102.5)
        XCTAssertFalse(log.isWarmup)
    }

    // MARK: - Save & done writes completion to the local cache

    /// After the user logs every set and taps "Save & done", the wired
    /// view-model must write a `.completed` workout + its set_logs to the
    /// local WorkoutCache. Guards the History-tab-backfill invariant from
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
        // Drive the session to completion. Fixture: 1 block, 2 items
        // (4 sets, then 3 sets). The fixture's timing_config_json is
        // empty so `restDuration` is 0 and the view model auto-advances
        // after each `logSet` — no explicit `.advance()` calls needed.
        executionVM.start()
        for _ in 0..<4 {
            executionVM.logSet(reps: 5, rir: 2)
        }
        for _ in 0..<3 {
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

        let logs = try await factory.workoutCache.loadSetLogs(workoutID: saved.id)
        XCTAssertEqual(logs.count, 7)
        XCTAssertTrue(logs.allSatisfy { $0.reps != nil })
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
        for _ in 0..<4 { vm.logSet(reps: 5, rir: 2) }
        for _ in 0..<3 { vm.logSet(reps: 8, rir: 2) }
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
        XCTAssertEqual(result, .empty)

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

    // MARK: - Helpers

    private func uniqueService() -> String {
        "com.ericfeunekes.WorkoutDB.token.test.\(UUID().uuidString)"
    }
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
