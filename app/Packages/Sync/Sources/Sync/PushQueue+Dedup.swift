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
//
// Performance: every dedup pass issues exactly one scoped fetch against
// the store's `dedupKey` index — NOT a full-table peek + decode. The
// store persists `PushItem.Payload.dedupKey` as a column on
// `PushItemModel`, so the `FetchDescriptor` predicate narrows to rows
// carrying that one logical identity. This is the perf-002 fix: the
// pre-perf-002 code decoded the entire queue on every enqueue, which
// scaled linearly with queue depth.

import Foundation
import CoreDomain
import WorkoutCoreFoundation

extension PushQueue {

    /// Drop every queued row whose payload is a single-log `.setLogs`
    /// carrying `id`. Batch payloads (multi-log arrays) are NOT deduped —
    /// a workout-completion batch is a distinct logical unit and
    /// shouldn't shadow individual single-log enqueues. The batch payload
    /// never gets a persisted `dedupKey` (see `Payload.dedupKey`) so the
    /// scoped fetch below cannot accidentally catch it.
    func dropExistingSetLog(id: UUID) async throws {
        let key = "setLog:\(id.uuidString.lowercased())"
        _ = try await store.removeMatchingDedupKey(key)
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
        let key = "status:\(workoutID.uuidString.lowercased()):\(status.rawValue)"
        _ = try await store.removeMatchingDedupKey(key)
    }

    /// Drop every queued reset for the same workout. Reset is terminal
    /// for the user's intent: multiple taps should collapse into one
    /// server-side delete/replan operation.
    func dropExistingWorkoutReset(workoutID: WorkoutID) async throws {
        let key = "reset:\(workoutID.uuidString.lowercased())"
        _ = try await store.removeMatchingDedupKey(key)
    }

    /// Drop every queued row whose payload is a `.userParameter` with the
    /// given `id`. Trigger: user edits the bodyweight again before the
    /// first push flushes — we want the latest value to win, not a
    /// stale-then-fresh sequence that transiently overwrites the server.
    func dropExistingUserParameter(id: UUID) async throws {
        let key = "userParam:\(id.uuidString.lowercased())"
        _ = try await store.removeMatchingDedupKey(key)
    }
}
