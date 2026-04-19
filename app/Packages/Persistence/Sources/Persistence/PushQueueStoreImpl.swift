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
        } else {
            modelContext.insert(PushItemModel(
                id: item.id,
                enqueuedAt: item.enqueuedAt,
                attempts: item.attempts,
                payloadJSON: encoded
            ))
        }
        try modelContext.save()
    }

    public func peek(max: Int) async throws -> [PushItem] {
        // Priority is not persisted — it is derived from the decoded
        // payload (see `PushItem.init`). We pull *all* rows sorted by
        // `enqueuedAt`, decode, then sort by priority+enqueuedAt and cap
        // at `max`. That keeps the schema stable (no V4 migration for a
        // derived field) at the cost of decoding rows we might not ship
        // this cycle. The queue caps at thousands of rows in the worst
        // case (typical steady state is single digits), so the decode
        // overhead is negligible against the flush round-trip.
        //
        // Ordering rule: priority ascending (results=0 before events=1),
        // then enqueuedAt ascending (FIFO within priority class). This
        // prevents a verbose-mode telemetry burst from shoving a freshly-
        // logged set behind a long chronological tail.
        //
        // Unknown-envelope tolerance: each row's decode is wrapped in
        // `try?` and skipped on failure. A forward-versioned row (written
        // by a newer build of the app and left behind after a downgrade,
        // or a corrupted blob) must NOT stall the whole queue — silently
        // skipping the bad row lets the remaining valid payloads drain.
        // The row stays in the table; a future build that knows how to
        // decode it can pick it up. A persistent poison row keeps trying
        // every peek, but the steady-state cost is a single failed decode
        // per peek per row, which is negligible.
        var descriptor = FetchDescriptor<PushItemModel>()
        descriptor.sortBy = [SortDescriptor(\PushItemModel.enqueuedAt)]
        let rows = try modelContext.fetch(descriptor)
        let decoded: [PushItem] = rows.compactMap { row in
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
        let sorted = decoded.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            return lhs.enqueuedAt < rhs.enqueuedAt
        }
        return Array(sorted.prefix(max))
    }

    public func remove(ids: [PushItemID]) async throws {
        let idSet = Set(ids)
        let descriptor = FetchDescriptor<PushItemModel>()
        let rows = try modelContext.fetch(descriptor)
        for row in rows where idSet.contains(row.id) {
            modelContext.delete(row)
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
        try modelContext.save()
    }

    public func isEmpty() async throws -> Bool {
        var descriptor = FetchDescriptor<PushItemModel>()
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).isEmpty
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
}

public enum PersistenceError: Error, Equatable {
    case decode(String)
    case keychain(OSStatus)
    case connectionMissing
}
