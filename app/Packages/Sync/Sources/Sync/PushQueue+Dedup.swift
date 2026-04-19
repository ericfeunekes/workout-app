// PushQueue+Dedup.swift
//
// Logical-identity dedup helpers for `PushQueue`. Split out of
// `PushQueue.swift` so the actor body stays under SwiftLint's
// `type_body_length` cap. These helpers are called from the public
// `enqueue*` entry points and drop any existing queued row that shares
// the logical identity of the payload about to be inserted — same
// SetLog.id, same (workoutID, status) pair, or same UserParameter.id.
//
// Why dedup at enqueue time, not at flush time? Two back-to-back
// enqueues without a flush in between would otherwise leave a stale and
// a fresh copy of the same logical row side-by-side in the queue; on
// flush the stale copy ships first and the server transiently holds the
// stale bytes until the second push resolves. For single-user /
// single-device this window is usually milliseconds — but it still
// violates the invariant that the freshest enqueue is the one that
// wins. See PushQueue.swift header for the full correctness argument.

import Foundation
import CoreDomain
import WorkoutCoreFoundation

extension PushQueue {

    /// Cap used for the unbounded peek that each dedup pass issues. The
    /// queue is bounded in practice (single digits of rows in steady
    /// state, thousands in the pathological recovery case) so one fetch
    /// per enqueue is negligible next to the push round-trip. The peek
    /// is tolerant (`PushQueueStoreImpl.peek` skips undecodable rows),
    /// so a forward-versioned poison row cannot stall the dedup pass.
    static var dedupPeekCap: Int { 10_000 }

    /// Drop every queued row whose payload is a single-log `.setLogs`
    /// carrying `id`. Batch payloads (multi-log arrays) are NOT deduped —
    /// a workout-completion batch is a distinct logical unit and
    /// shouldn't shadow individual single-log enqueues.
    func dropExistingSetLog(id: UUID) async throws {
        let all = try await store.peek(max: Self.dedupPeekCap)
        var doomed: [PushItemID] = []
        for item in all {
            if case .setLogs(let logs) = item.payload,
               logs.count == 1,
               logs[0].id == id {
                doomed.append(item.id)
            }
        }
        if !doomed.isEmpty {
            try await store.remove(ids: doomed)
        }
    }

    /// Drop every queued row whose payload is a `.statusUpdate` matching
    /// the given (workoutID, status) pair. `completedAt` is intentionally
    /// NOT part of the identity — a re-send with a fresher completedAt
    /// should replace the older one. Real-world trigger: user taps End,
    /// then Save & Done — without dedup we'd queue two identical updates.
    func dropExistingStatusUpdate(
        workoutID: WorkoutID,
        status: CoreDomain.WorkoutStatus
    ) async throws {
        let all = try await store.peek(max: Self.dedupPeekCap)
        var doomed: [PushItemID] = []
        for item in all {
            if case .statusUpdate(let queuedID, let queuedStatus, _, _) = item.payload,
               queuedID == workoutID,
               queuedStatus == status {
                doomed.append(item.id)
            }
        }
        if !doomed.isEmpty {
            try await store.remove(ids: doomed)
        }
    }

    /// Drop every queued row whose payload is a `.userParameter` with the
    /// given `id`. Trigger: user edits the bodyweight again before the
    /// first push flushes — we want the latest value to win, not a
    /// stale-then-fresh sequence that transiently overwrites the server.
    func dropExistingUserParameter(id: UUID) async throws {
        let all = try await store.peek(max: Self.dedupPeekCap)
        var doomed: [PushItemID] = []
        for item in all {
            if case .userParameter(let param) = item.payload, param.id == id {
                doomed.append(item.id)
            }
        }
        if !doomed.isEmpty {
            try await store.remove(ids: doomed)
        }
    }
}
