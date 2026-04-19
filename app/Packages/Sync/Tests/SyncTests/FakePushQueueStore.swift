// FakePushQueueStore.swift
//
// In-memory `PushQueueStore`. Persistence will ship the SwiftData-backed
// production implementation; tests use this one so the queue can be inspected
// synchronously without dragging in a live SwiftData stack.

import Foundation
import Sync

actor FakePushQueueStore: PushQueueStore {
    private var items: [PushItem] = []

    func enqueue(_ item: PushItem) async throws {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item  // idempotent replace
        } else {
            items.append(item)
        }
    }

    func peek(max: Int) async throws -> [PushItem] {
        // Sort by priority first (results=0 drain before events=1), then
        // FIFO within a priority class. Mirrors the production
        // SwiftData-backed store so tests exercise the same ordering.
        let sorted = items.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            return lhs.enqueuedAt < rhs.enqueuedAt
        }
        return Array(sorted.prefix(max))
    }

    func remove(ids: [PushItemID]) async throws {
        let set = Set(ids)
        items.removeAll { set.contains($0.id) }
    }

    func update(_ item: PushItem) async throws {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item
        }
    }

    func isEmpty() async throws -> Bool {
        items.isEmpty
    }

    /// Test-only — peek without the max cap.
    func all() -> [PushItem] {
        items.sorted { $0.enqueuedAt < $1.enqueuedAt }
    }
}
