// FakePushQueueStore.swift
//
// In-memory `PushQueueStore`. Persistence ships the SwiftData-backed
// production implementation; tests use this one so the queue can be inspected
// synchronously without dragging in a live SwiftData stack.
//
// Instrumentation: `peekCallCount` + `removeMatchingDedupKeyCallCount` let
// tests prove that dedup passes use the scoped dedup-key call, not a
// full-table `peek`. The perf-002 regression guard is "one enqueue ⇒ one
// scoped dedup fetch ⇒ zero full-table peeks".

import Foundation
import Sync

actor FakePushQueueStore: PushQueueStore {
    private var items: [PushItem] = []
    /// Number of times `peek(max:)` has been invoked. Incremented on every
    /// call, regardless of how many rows are returned. perf-002 test uses
    /// this to assert that dedup does NOT peek the whole queue.
    private(set) var peekCallCount = 0
    /// Number of times `removeMatchingDedupKey` has been invoked.
    /// perf-002 test uses this to assert that each primitive-log enqueue /
    /// `enqueueStatusUpdate` / `enqueueUserParameter` drives exactly one
    /// scoped dedup call.
    private(set) var removeMatchingDedupKeyCallCount = 0
    /// Record of every dedup key passed to `removeMatchingDedupKey`, in
    /// call order. Useful for debugging a failing regression test — if
    /// the key shape drifts the assertion can show what we actually saw.
    private(set) var removeMatchingDedupKeyCalls: [String] = []
    private(set) var enqueueReplacingDedupKeysCalls: [Set<String>] = []

    func enqueue(_ item: PushItem) async throws {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item  // idempotent replace
        } else {
            items.append(item)
        }
    }

    func peek(max: Int) async throws -> [PushItem] {
        peekCallCount += 1
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

    func removeMatchingDedupKey(_ key: String) async throws -> Int {
        removeMatchingDedupKeyCallCount += 1
        removeMatchingDedupKeyCalls.append(key)
        let before = items.count
        items.removeAll { $0.dedupKey == key }
        return before - items.count
    }

    func enqueue(_ item: PushItem, replacingDedupKeys keys: Set<String>) async throws {
        enqueueReplacingDedupKeysCalls.append(keys)
        items.removeAll { existing in
            guard let key = existing.dedupKey else { return false }
            return keys.contains(key)
        }
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item
        } else {
            items.append(item)
        }
    }

    func isEmpty() async throws -> Bool {
        items.isEmpty
    }

    func clear() async throws {
        items.removeAll()
    }

    /// Test-only — peek without the max cap.
    func all() -> [PushItem] {
        items.sorted { $0.enqueuedAt < $1.enqueuedAt }
    }
}
