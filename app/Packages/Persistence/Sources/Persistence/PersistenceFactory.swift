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
    /// Telemetry emitter. Shell gets it via `telemetryEmitter()` and threads
    /// it into `AppBootstrap.bootstrap` so view models receive it. The
    /// emitter is wired to the same `pushQueueStore` so every emitted event
    /// joins the regular foreground-flush cadence.
    private let telemetryEmitterImpl: TelemetryEmitterImpl

    /// Build a factory backed by the on-disk SwiftData store. The default
    /// application-support location is fine; tests use `makeInMemory()`.
    public static func makeDefault(
        tokenServiceName: String = "com.ericfeunekes.WorkoutDB.token"
    ) throws -> PersistenceFactory {
        let schema = Schema(versionedSchema: WorkoutDBSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: WorkoutDBMigrationPlan.self,
            configurations: [configuration]
        )
        return PersistenceFactory(
            container: container,
            tokenStore: TokenStoreImpl(serviceName: tokenServiceName),
            syncMetadataStore: SyncMetadataStoreImpl()
        )
    }

    /// In-memory container, used for tests and previews.
    public static func makeInMemory(
        tokenServiceName: String = "com.ericfeunekes.WorkoutDB.token.test"
    ) throws -> PersistenceFactory {
        let schema = Schema(versionedSchema: WorkoutDBSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: WorkoutDBMigrationPlan.self,
            configurations: [configuration]
        )
        // Use a unique defaults suite so tests don't share the lastSyncAt
        // key with the process-wide UserDefaults.
        let suiteName = "com.ericfeunekes.WorkoutDB.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        return PersistenceFactory(
            container: container,
            tokenStore: TokenStoreImpl(serviceName: tokenServiceName),
            syncMetadataStore: SyncMetadataStoreImpl(defaults: defaults)
        )
    }

    public init(
        container: ModelContainer,
        tokenStore: TokenStore,
        syncMetadataStore: SyncMetadataStore = SyncMetadataStoreImpl()
    ) {
        self.container = container
        self.workoutCache = WorkoutCacheImpl(modelContainer: container)
        self.sessionStore = SessionStoreImpl(modelContainer: container)
        let pushQueueStore = PushQueueStoreImpl(modelContainer: container)
        self.pushQueueStore = pushQueueStore
        self.tokenStore = tokenStore
        self.syncMetadataStore = syncMetadataStore
        // Wire the emitter to the same container + push queue. `attach` is
        // async-in-actor; the factory returns eagerly and callers await the
        // first `telemetryEmitter()` access which completes the binding.
        let emitter = TelemetryEmitterImpl(modelContainer: container)
        self.telemetryEmitterImpl = emitter
        // Fire-and-forget bind — actors preserve message order, so the first
        // emit queued after factory construction can never arrive before
        // this attach message reaches the actor.
        // swiftlint:disable:next no_direct_task_unstructured
        Task { await emitter.attach(pushQueueStore: pushQueueStore) }
    }

    /// Return the process-wide telemetry emitter. Safe to call from any
    /// isolation context; the underlying actor serializes emits.
    public func telemetryEmitter() -> TelemetryEmitter {
        telemetryEmitterImpl
    }
}
