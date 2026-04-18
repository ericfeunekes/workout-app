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
        var descriptor = FetchDescriptor<PushItemModel>()
        descriptor.sortBy = [SortDescriptor(\PushItemModel.enqueuedAt)]
        descriptor.fetchLimit = max
        let rows = try modelContext.fetch(descriptor)
        return try rows.map { row in
            PushItem(
                id: row.id,
                payload: try PushQueuePayloadCoding.decode(row.payloadJSON),
                enqueuedAt: row.enqueuedAt,
                attempts: row.attempts
            )
        }
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
}

public enum PersistenceError: Error, Equatable {
    case decode(String)
    case keychain(OSStatus)
    case connectionMissing
}
