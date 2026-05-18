// PersistenceFactory.swift
//
// Composition root. Builds one `ModelContainer` and hands out the three
// @ModelActor stores bound to it (plus the `TokenStore`, which has no
// SwiftData dependency). Features and Sync take protocols via init, never
// concrete types.
//
// One container per process — SwiftData's own docs recommend it. The stores
// each get their own `ModelContext` via the `@ModelActor` expansion, which
// is what gives us actor isolation without losing the shared container.

import Foundation
import SwiftData
import CoreTelemetry
import Sync

public struct PersistenceFactory {
    public let container: ModelContainer
    public let workoutCache: WorkoutCache
    public let sessionStore: SessionStore
    public let pushQueueStore: PushQueueStore
    public let tokenStore: TokenStore
    public let syncMetadataStore: SyncMetadataStore
    /// Pre-formatted per-exercise "LAST · …" summary map. Populated by
    /// the Shell composition after a successful pull; read back by
    /// `TodayLoader` and by `AppBootstrap.buildWorkoutContext` so the
    /// chips survive offline restarts (qa-001 + qa-020).
    public let lastPerformedStore: LastPerformedStore
    /// Telemetry emitter. Shell gets it via `telemetryEmitter()` and threads
    /// it into `AppBootstrap.bootstrap` so view models receive it. The
    /// emitter is wired to the same `pushQueueStore` so every emitted event
    /// joins the regular foreground-flush cadence. The attach step is NOT
    /// fired from `init` — `AppBootstrap.bootstrap` awaits
    /// `prepareTelemetry()` before the first `emit`, which is what
    /// prevents early-launch events (e.g. `bootstrap.start`) from
    /// stranding off-queue. The old code used a fire-and-forget
    /// `Task { await emitter.attach(...) }` from `init` and lost the race
    /// against the first emit when the app was built on the same run loop
    /// tick. See `docs/features/telemetry.md` § "Attach ordering".
    private let telemetryEmitterImpl: TelemetryEmitterImpl
    /// Reference-boxed (actor) so `prepareTelemetry()` — running on a
    /// `struct` value — can flip the "attached" flag without the whole
    /// struct being `mutating`. The box is constructed once per factory;
    /// the stored emitter pointer never changes, only its attach state.
    private let telemetryAttachState: TelemetryAttachState
    /// Concrete push-queue store reference, retained so
    /// `prepareTelemetry()` can call the implementation-only
    /// `pruneUndecodableRows()` without widening the `PushQueueStore`
    /// protocol (which lives in Sync) with a persistence-hygiene hook.
    /// The protocol-typed `pushQueueStore` above is still the wiring
    /// handed to callers; this is the same object, just retained at its
    /// concrete type for the one-off launch prune.
    private let pushQueueStoreImpl: PushQueueStoreImpl

    /// Build a factory backed by the on-disk SwiftData store. The default
    /// application-support location is fine; tests use `makeInMemory()`.
    public static func makeDefault(
        tokenServiceName: String = "com.ericfeunekes.WorkoutDB.token"
    ) throws -> PersistenceFactory {
        let schema = Schema(versionedSchema: WorkoutDBSchemaV7.self)
        let storeURL = try defaultStoreURL()
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: schema,
                migrationPlan: nil,
                configurations: [configuration]
            )
        } catch {
            container = try ModelContainer(
                for: schema,
                migrationPlan: WorkoutDBMigrationPlan.self,
                configurations: [configuration]
            )
        }
        try runPostMigrationBackfills(on: container)
        return PersistenceFactory(
            container: container,
            tokenStore: TokenStoreImpl(serviceName: tokenServiceName),
            syncMetadataStore: SyncMetadataStoreImpl(),
            lastPerformedStore: LastPerformedStoreImpl()
        )
    }

    private static func defaultStoreURL() throws -> URL {
        try FileManager.default
            .url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appendingPathComponent("default.store")
    }

    /// In-memory container, used for tests and previews.
    public static func makeInMemory(
        tokenServiceName: String = "com.ericfeunekes.WorkoutDB.token.test"
    ) throws -> PersistenceFactory {
        let schema = Schema(versionedSchema: WorkoutDBSchemaV7.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: WorkoutDBMigrationPlan.self,
            configurations: [configuration]
        )
        try runPostMigrationBackfills(on: container)
        // Use a unique defaults suite so tests don't share the lastSyncAt
        // key with the process-wide UserDefaults.
        let suiteName = "com.ericfeunekes.WorkoutDB.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        return PersistenceFactory(
            container: container,
            tokenStore: TokenStoreImpl(serviceName: tokenServiceName),
            syncMetadataStore: SyncMetadataStoreImpl(defaults: defaults),
            lastPerformedStore: LastPerformedStoreImpl(defaults: defaults)
        )
    }

    /// Run the post-migration backfills once on container open. Both
    /// helpers are idempotent — rows that already carry the new columns
    /// are skipped — so calling on every launch is safe.
    ///
    /// Backfills that run here:
    ///   • V2→V3 SetLog denormalization (`workoutID`, `plannedExerciseID`).
    ///   • V3→V4 PushItem drain priority + dedup key (perf-002).
    ///
    /// Called from both `makeDefault` and `makeInMemory` so a production
    /// store and a test container behave identically at the moment
    /// `PersistenceFactory` hands out actors.
    private static func runPostMigrationBackfills(on container: ModelContainer) throws {
        let context = ModelContext(container)
        try backfillSetLogDenormalization(context: context)
        try backfillPushItemPriorityAndDedupKey(context: context)
    }

    public init(
        container: ModelContainer,
        tokenStore: TokenStore,
        syncMetadataStore: SyncMetadataStore = SyncMetadataStoreImpl(),
        lastPerformedStore: LastPerformedStore = LastPerformedStoreImpl()
    ) {
        self.container = container
        self.workoutCache = WorkoutCacheImpl(modelContainer: container)
        self.sessionStore = SessionStoreImpl(modelContainer: container)
        let pushQueueStore = PushQueueStoreImpl(modelContainer: container)
        self.pushQueueStore = pushQueueStore
        self.pushQueueStoreImpl = pushQueueStore
        self.tokenStore = tokenStore
        self.syncMetadataStore = syncMetadataStore
        self.lastPerformedStore = lastPerformedStore
        // Build the emitter but do NOT attach from init. The old code fired
        // a detached `Task { await emitter.attach(...) }` and returned, which
        // meant any caller that ran `emit(_:)` *before* that detached task
        // reached the actor persisted the event locally but missed the
        // enqueue step (the emitter's `pushQueueStore` was still nil). The
        // bug was most visible on `bootstrap.start`: the shell builds the
        // factory and calls `bootstrap(...)` on the next MainActor tick, so
        // the window was real. Attach is now performed lazily and
        // awaitably from `telemetryEmitter()` — the first caller serializes
        // the wire-up before the first `emit`.
        let emitter = TelemetryEmitterImpl(modelContainer: container)
        self.telemetryEmitterImpl = emitter
        self.telemetryAttachState = TelemetryAttachState(
            emitter: emitter,
            pushQueueStore: pushQueueStore
        )
    }

    /// Return a reference to the process-wide telemetry emitter. Sync so
    /// synchronous callers (SwiftUI `@State` initializers, view-model
    /// constructors) can thread it through without a `Task` hop.
    ///
    /// IMPORTANT: the emitter is only safe to `emit(_:)` against after
    /// `prepareTelemetry()` has returned at least once. Handing out the
    /// reference is fine (the emitter will queue the local EventModel row
    /// unconditionally) — what stays stranded off-queue before attach is
    /// the push-queue enqueue step. Production callers always run through
    /// `AppBootstrap.bootstrap`, which calls `prepareTelemetry()` before
    /// the first `emit`; tests that exercise the bootstrap path inherit
    /// the same ordering for free.
    public func telemetryEmitter() -> TelemetryEmitter {
        telemetryEmitterImpl
    }

    /// Complete the telemetry emitter → push queue wire-up. Idempotent —
    /// calling more than once is a cheap no-op after the first call.
    /// `AppBootstrap.bootstrap` awaits this before emitting
    /// `bootstrap.start` so the first event lands in the push queue along
    /// with the local EventModel row. Without this, early-launch events
    /// persisted locally but never enqueued (attach fired as a detached
    /// task and the first emit won the race).
    ///
    /// Also sweeps any undecodable rows out of the push queue so a
    /// forward-versioned envelope left behind by a downgrade doesn't
    /// keep the queue's `remaining` counter above zero forever. See
    /// `PushQueueStoreImpl.pruneUndecodableRows` for the rationale. Prune
    /// errors are swallowed — a failed sweep is hygiene, not correctness,
    /// and the peek path is already tolerant of poison rows.
    public func prepareTelemetry() async {
        await telemetryAttachState.ensureAttached()
        _ = try? await pushQueueStoreImpl.pruneUndecodableRows()
    }
}

/// Reference box that owns the "has the emitter been attached?" state so
/// `PersistenceFactory.prepareTelemetry()` can be both `async` and safe to
/// call from a struct value. One `TelemetryEmitterImpl` lives for the
/// lifetime of the factory; we only need to make sure `attach(_:)` runs
/// exactly once before any caller emits.
final actor TelemetryAttachState {
    private let emitter: TelemetryEmitterImpl
    private let pushQueueStore: PushQueueStore
    private var didAttach = false

    init(emitter: TelemetryEmitterImpl, pushQueueStore: PushQueueStore) {
        self.emitter = emitter
        self.pushQueueStore = pushQueueStore
    }

    /// Run `emitter.attach(pushQueueStore:)` exactly once. Concurrent
    /// callers that hit this at the same time serialize on this actor;
    /// only the first one pays the actor hop to the emitter.
    func ensureAttached() async {
        if didAttach { return }
        didAttach = true
        await emitter.attach(pushQueueStore: pushQueueStore)
    }
}
