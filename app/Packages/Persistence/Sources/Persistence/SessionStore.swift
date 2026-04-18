// SessionStore.swift
//
// Live-session persistence. Survives cold start, background kill, and iOS
// memory eviction so reopening the app mid-workout restores the same state
// (see `app/README.md` § "Persistence (local session)" and the
// `SessionState` file header in Core/Session).
//
// Boundary note: Persistence does not import CoreSession (per
// `docs/architecture/boundaries.md` — the cell is forbidden). So the store
// takes a raw `Data` payload: Features encodes the Core/Session
// `SessionState` (which is `Sendable + Equatable + Codable` at the Features
// boundary) to JSON and hands the bytes over. Persistence is the opaque
// bucket. This keeps the runtime-state type out of the storage layer.
//
// The store is one-row-ever: there is only one live session per user per
// device. Saving replaces; loading returns the row or nil.

import Foundation
import SwiftData

public protocol SessionStore: Sendable {
    /// Returns the encoded session payload if one is stored; nil otherwise.
    /// Callers decode JSON → SessionState themselves (the type lives in
    /// Core/Session, not here — see file header).
    func load() async throws -> Data?

    /// Replace the stored payload with the given encoded bytes.
    func save(_ payload: Data) async throws

    /// Remove the stored payload (called on workout complete / cancel).
    func clear() async throws
}

@ModelActor
public actor SessionStoreImpl: SessionStore {

    public func load() async throws -> Data? {
        let descriptor = FetchDescriptor<SessionSnapshotModel>()
        let rows = try modelContext.fetch(descriptor)
        return rows.first?.encodedJSON
    }

    public func save(_ payload: Data) async throws {
        let descriptor = FetchDescriptor<SessionSnapshotModel>()
        let rows = try modelContext.fetch(descriptor)
        let now = Date()
        if let existing = rows.first {
            existing.encodedJSON = payload
            existing.savedAt = now
        } else {
            modelContext.insert(SessionSnapshotModel(encodedJSON: payload, savedAt: now))
        }
        try modelContext.save()
    }

    public func clear() async throws {
        try modelContext.delete(model: SessionSnapshotModel.self)
        try modelContext.save()
    }
}
