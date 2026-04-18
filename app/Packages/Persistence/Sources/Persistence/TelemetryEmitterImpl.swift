// TelemetryEmitterImpl.swift
//
// SwiftData-backed `TelemetryEmitter`. The protocol's `emit(_:)` is
// synchronous and fire-and-forget — callers never block on telemetry. We
// get there by marking `emit` nonisolated and spawning a detached Task
// that awaits the actor's real persistence work.
//
// Two side effects per emit:
//   1. Insert an `EventModel` row locally. Keeps a 10k ring buffer per the
//      MVP scope — oldest rows are pruned on overflow so an app that
//      emits steadily can't balloon the store.
//   2. Enqueue a `PushItem.Payload.events(...)` into the existing
//      `PushQueueStore`. The push queue drains on the normal foreground
//      cadence; we don't run our own flusher.
//
// Both happen inside the same actor turn so an emit is atomic with respect
// to other emits: we don't get interleaved "insert A, enqueue B, insert B,
// enqueue A" histories.

import Foundation
import SwiftData
import CoreTelemetry
import Sync

/// Hard cap on locally-retained event rows. Overflow prunes oldest first.
/// 10k events covers many-days-worth of normal use; durable storage isn't
/// where the event trail lives long-term (the server is).
private let kMaxLocalEvents = 10_000

@ModelActor
public actor TelemetryEmitterImpl: TelemetryEmitter {
    /// The push queue we hand batches to. `nil` skips the enqueue step —
    /// useful for tests or the very earliest stages of bootstrap where the
    /// queue isn't wired yet.
    private var pushQueueStore: PushQueueStore?

    /// Bind a push-queue store after construction. Called by
    /// `PersistenceFactory` once the composition root has the queue ready.
    public func attach(pushQueueStore: PushQueueStore) {
        self.pushQueueStore = pushQueueStore
    }

    // `emit` is nonisolated + non-throwing so callers match the
    // `TelemetryEmitter` protocol (fire-and-forget, no await). We hop onto
    // the actor via Task.detached — .detached keeps the caller's priority
    // out of the equation so a MainActor view model emitting events can't
    // accidentally raise our background persistence to user-initiated.
    public nonisolated func emit(_ event: CoreTelemetry.Event) {
        Task.detached { [weak self] in
            guard let self else { return }
            await self.persist(event)
        }
    }

    /// Actor-isolated persistence step. Silently swallows errors — telemetry
    /// must never surface a failure to the caller (we don't want a broken
    /// disk to break a workout). A failure here just means the event is
    /// lost locally; the server-side trail for a later session is still
    /// fine.
    private func persist(_ event: CoreTelemetry.Event) async {
        do {
            let model = EventModel(
                id: event.id,
                timestamp: event.timestamp,
                sessionID: event.sessionID,
                kind: event.kind,
                name: event.name,
                dataJSON: event.dataJSON,
                workoutID: event.workoutID,
                setLogID: event.setLogID
            )
            modelContext.insert(model)
            try modelContext.save()
            try pruneOverflow()
        } catch {
            // Intentionally swallow — see docstring.
            return
        }

        if let queue = pushQueueStore {
            try? await queue.enqueue(
                PushItem(
                    payload: .events([event]),
                    enqueuedAt: Date()
                )
            )
        }
    }

    /// Keep the local `EventModel` row count ≤ `kMaxLocalEvents` by
    /// pruning the oldest rows. Cheap in steady state because the row
    /// count only exceeds the cap by one or two after each insert.
    private func pruneOverflow() throws {
        var count = FetchDescriptor<EventModel>()
        count.includePendingChanges = true
        let total = try modelContext.fetchCount(count)
        if total <= kMaxLocalEvents {
            return
        }
        let excess = total - kMaxLocalEvents
        var oldest = FetchDescriptor<EventModel>()
        oldest.sortBy = [SortDescriptor(\EventModel.timestamp)]
        oldest.fetchLimit = excess
        let rows = try modelContext.fetch(oldest)
        for row in rows {
            modelContext.delete(row)
        }
        try modelContext.save()
    }
}
