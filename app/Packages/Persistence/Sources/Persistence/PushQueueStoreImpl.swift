// PushQueueStoreImpl.swift
//
// SwiftData-backed `PushQueueStore`. The protocol lives in the Sync package
// so Sync can own its own vocabulary; Persistence implements it here so the
// dependency direction matches the graph in
// `docs/architecture/swift-packages.md` (Sync → Persistence, not the other
// way around).
//
// Payload encoding: `PushItem.Payload` is an enum that isn't Codable in
// the Sync package — Sync encodes payloads on the fly for the HTTP body.
// The envelope shape lives in `PushQueuePayloadCoding.swift`; this actor
// just calls into it.
//
// Performance (perf-002): `peek(max:)` asks SwiftData for the first `max`
// rows using a sorted `FetchDescriptor` with `fetchLimit` set — the old
// implementation fetched every row, decoded every payload, sorted in
// memory, and prefixed. That scaled linearly with queue depth on every
// flush and every dedup pass. Ordering uses the persisted `priority`
// column added in V4 so SwiftData handles the sort server-side (SQLite
// index) rather than us re-deriving it from the decoded payload.
//
// Dedup: `removeMatchingDedupKey` uses a scoped `FetchDescriptor`
// predicate against the persisted `dedupKey` column. One scoped fetch
// per enqueue instead of a full-table peek + decode. See
// `PushQueue+Dedup.swift` for the caller side.

import Foundation
import SwiftData
import CoreDomain
import CoreTelemetry
import Sync

@ModelActor
public actor PushQueueStoreImpl: PushQueueStore {

    public func enqueue(_ item: PushItem) async throws {
        let encoded = try PushQueuePayloadCoding.encode(item.payload)
        let id = item.id
        let descriptor = FetchDescriptor<PushItemModel>(
            predicate: #Predicate<PushItemModel> { $0.id == id }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            // Idempotent replace — keeps the contract matching
            // `FakePushQueueStore` (same id ⇒ update in place).
            existing.enqueuedAt = item.enqueuedAt
            existing.attempts = item.attempts
            existing.payloadJSON = encoded
            existing.priority = item.priority
            existing.dedupKey = item.dedupKey
        } else {
            modelContext.insert(PushItemModel(
                id: item.id,
                enqueuedAt: item.enqueuedAt,
                attempts: item.attempts,
                payloadJSON: encoded,
                priority: item.priority,
                dedupKey: item.dedupKey
            ))
        }
        try modelContext.save()
    }

    public func peek(max: Int) async throws -> [PushItem] {
        // Ask SwiftData for `max` rows sorted by (priority, enqueuedAt)
        // directly — no in-memory sort or whole-table decode. Priority
        // ascending (results=0 before events=1), enqueuedAt ascending
        // (FIFO within priority class). `priority` is persisted on the
        // row (V4 column) so the sort resolves against SQLite rather
        // than re-derivation from the decoded envelope.
        //
        // `fetchLimit: max` caps the decode pass at the batch size
        // regardless of queue depth — the perf-002 fix. The prior code
        // decoded the whole queue before prefixing.
        //
        // Unknown-envelope tolerance: each row's decode is wrapped in
        // `try?` and skipped on failure. A forward-versioned row (written
        // by a newer build of the app and left behind after a downgrade,
        // or a corrupted blob) must NOT stall the whole queue — silently
        // skipping the bad row lets the remaining valid payloads drain.
        // The row stays in the table; a future build that knows how to
        // decode it can pick it up. A persistent poison row keeps trying
        // every peek, but the steady-state cost is a single failed decode
        // per peek per row, which is negligible. `pruneUndecodableRows`
        // is the hygiene sweep that eventually removes them.
        var descriptor = FetchDescriptor<PushItemModel>()
        descriptor.sortBy = [
            SortDescriptor(\PushItemModel.priority),
            SortDescriptor(\PushItemModel.enqueuedAt),
        ]
        descriptor.fetchLimit = max
        let rows = try modelContext.fetch(descriptor)
        return rows.compactMap { row in
            guard let payload = try? PushQueuePayloadCoding.decode(row.payloadJSON) else {
                return nil
            }
            return PushItem(
                id: row.id,
                payload: payload,
                enqueuedAt: row.enqueuedAt,
                attempts: row.attempts
            )
        }
    }

    public func remove(ids: [PushItemID]) async throws {
        for id in ids {
            let descriptor = FetchDescriptor<PushItemModel>(
                predicate: #Predicate<PushItemModel> { $0.id == id }
            )
            if let row = try modelContext.fetch(descriptor).first {
                modelContext.delete(row)
            }
        }
        try modelContext.save()
    }

    public func update(_ item: PushItem) async throws {
        let id = item.id
        let descriptor = FetchDescriptor<PushItemModel>(
            predicate: #Predicate<PushItemModel> { $0.id == id }
        )
        guard let existing = try modelContext.fetch(descriptor).first else {
            // Matches the FakePushQueueStore semantic: unknown id is no-op.
            return
        }
        existing.enqueuedAt = item.enqueuedAt
        existing.attempts = item.attempts
        existing.payloadJSON = try PushQueuePayloadCoding.encode(item.payload)
        existing.priority = item.priority
        existing.dedupKey = item.dedupKey
        try modelContext.save()
    }

    public func removeMatchingDedupKey(_ key: String) async throws -> Int {
        // Scoped predicate fetch: SwiftData narrows to rows with the
        // matching `dedupKey` column — it does NOT decode every
        // `payloadJSON`. This is the perf-002 dedup fix. Prior behaviour
        // was a full-table peek that decoded every row and matched on
        // the decoded payload.
        let descriptor = FetchDescriptor<PushItemModel>(
            predicate: #Predicate<PushItemModel> { $0.dedupKey == key }
        )
        let rows = try modelContext.fetch(descriptor)
        guard !rows.isEmpty else { return 0 }
        for row in rows {
            modelContext.delete(row)
        }
        try modelContext.save()
        return rows.count
    }

    public func enqueue(_ item: PushItem, replacingDedupKeys keys: Set<String>) async throws {
        do {
            try stageEnqueue(item, replacingDedupKeys: keys)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func stageEnqueue(_ item: PushItem, replacingDedupKeys keys: Set<String>) throws {
        let encoded = try PushQueuePayloadCoding.encode(item.payload)
        var removedIDs = Set<PushItemID>()
        for key in keys {
            let descriptor = FetchDescriptor<PushItemModel>(
                predicate: #Predicate<PushItemModel> { $0.dedupKey == key }
            )
            for row in try modelContext.fetch(descriptor) {
                removedIDs.insert(row.id)
                modelContext.delete(row)
            }
        }

        if !removedIDs.contains(item.id) {
            let id = item.id
            let descriptor = FetchDescriptor<PushItemModel>(
                predicate: #Predicate<PushItemModel> { $0.id == id }
            )
            if let existing = try modelContext.fetch(descriptor).first {
                existing.enqueuedAt = item.enqueuedAt
                existing.attempts = item.attempts
                existing.payloadJSON = encoded
                existing.priority = item.priority
                existing.dedupKey = item.dedupKey
            } else {
                modelContext.insert(PushItemModel(
                    id: item.id,
                    enqueuedAt: item.enqueuedAt,
                    attempts: item.attempts,
                    payloadJSON: encoded,
                    priority: item.priority,
                    dedupKey: item.dedupKey
                ))
            }
        } else {
            modelContext.insert(PushItemModel(
                id: item.id,
                enqueuedAt: item.enqueuedAt,
                attempts: item.attempts,
                payloadJSON: encoded,
                priority: item.priority,
                dedupKey: item.dedupKey
            ))
        }
    }

    public func isEmpty() async throws -> Bool {
        var descriptor = FetchDescriptor<PushItemModel>()
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).isEmpty
    }

    public func clear() async throws {
        do {
            try modelContext.delete(model: PushItemModel.self)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Delete every row whose `payloadJSON` can no longer be decoded by
    /// `PushQueuePayloadCoding`. Returns the number of rows dropped.
    ///
    /// Why this exists: `peek(max:)` is deliberately tolerant — an unknown
    /// envelope is skipped so one bad row doesn't stall the queue. But the
    /// skipped row stays on disk and counts toward `isEmpty` / flush's
    /// `remaining` — the queue can never drain to zero once a poison row
    /// lands. In practice a poison row is a forward-versioned envelope left
    /// behind by a downgrade, or a corrupted blob; neither is recoverable
    /// in-place.
    ///
    /// Called once from `PersistenceFactory.prepareTelemetry()` on launch
    /// so the app starts the day with a clean queue. The sweep is
    /// destructive — the rows are gone after this returns. That is the
    /// point: a newer build's envelope that an older build can't read is
    /// dead weight on the older build, and there is no "downgrade window"
    /// in this single-user system where a build-N row should survive a
    /// build-N-1 launch.
    public func pruneUndecodableRows() async throws -> Int {
        let descriptor = FetchDescriptor<PushItemModel>()
        let rows = try modelContext.fetch(descriptor)
        var removed = 0
        for row in rows {
            do {
                _ = try PushQueuePayloadCoding.decode(row.payloadJSON)
            } catch {
                modelContext.delete(row)
                removed += 1
            }
        }
        if removed > 0 {
            try modelContext.save()
        }
        return removed
    }

    #if DEBUG
    /// Test-only: stage the same replacement mutation as `enqueue(_:replacingDedupKeys:)`,
    /// then throw before save and run the same rollback cleanup. This proves staged
    /// deletes/inserts cannot leak into the next successful save.
    internal func enqueueReplacingThenThrowForTests(
        _ item: PushItem,
        replacingDedupKeys keys: Set<String>
    ) throws {
        struct TestAbort: Error {}
        do {
            try stageEnqueue(item, replacingDedupKeys: keys)
            throw TestAbort()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
    #endif
}

public enum PersistenceError: Error, Equatable {
    case decode(String)
    case encode(String)
    case keychain(OSStatus)
    case connectionMissing
}
