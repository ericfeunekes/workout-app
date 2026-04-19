// ExecutionViewModel+PersistencePipeline.swift
//
// Serial persistence pipeline for the live session bytes. Every write
// (`save` and `clear`) funnels through a single ordered channel so that
// two bugs the v0 fire-and-forget `Task` approach allowed can't recur:
//
//   - Bug A: older snapshots landing AFTER `clear()` / `.complete` because
//     every `persist()` launched its own unstructured Task and they
//     resolved in arbitrary order.
//   - Bug A (related): `.save` followed by `clear()` racing to the store,
//     so `clear()` could win, then the save lands and leaves stale state
//     on disk.
//
// Design — why a chained-Task pipeline rather than a plain actor:
//   An `actor` on its own is NOT enough. Actor methods suspend on
//   `await store.save(…)`, and during that suspension the actor can
//   process OTHER enqueued ops reentrantly. That breaks the ordering
//   guarantee we need — a clear could acquire the actor, start its
//   sleep, then a still-running save's `self.payload = …` assignment
//   could land AFTER the clear set `self.payload = nil`. The fix is to
//   chain ops through awaited `Task<Void, Never>` handles: each new
//   op's Task awaits the previous op's Task to complete before running,
//   giving us true serial execution across suspension points. The
//   actor around the chain head is only to protect the `previous`
//   handle from concurrent writes from the main actor.
//
// Staleness rejection:
//   Each op carries a monotonic revision number stamped on the main
//   actor at enqueue time. The pipeline remembers the highest revision
//   it has acknowledged. Ops with a lower revision than the acknowledged
//   peak are dropped before touching the store. In practice this matters
//   when a `save(rev: N-1)` is still in flight while the VM already
//   enqueued `clear(rev: N)` — the earlier save is superseded and must
//   NOT re-write the bytes the clear wiped.
//
// The pipeline handle and revision counter live as stored properties
// on `ExecutionViewModel` itself (see the "Persistence pipeline" section
// of `ExecutionViewModel.swift`). Earlier revisions of this file kept
// them in a module-level `[ObjectIdentifier(self): …]` side-table so the
// main class body could stay untouched; that design stranded entries
// across VM lifetimes when the allocator reused a deallocated VM's heap
// address, letting a brand-new VM inherit a destroyed `SessionStore`
// and a stale revision peak from its predecessor. Storing the two
// properties on the VM itself ties their lifetime to the VM's.

import Foundation
import Persistence

// MARK: - Pipeline op

/// A single persistence operation. `save` carries the raw (unencoded)
/// snapshot so the pipeline can drop superseded saves WITHOUT paying the
/// JSON encode cost. `clear` wipes the store. The revision rides with
/// the op so the actor can reject stale writes without a second hop.
///
/// Deferring the encode into the pipeline is the load-bearing part of
/// perf-001's fix: N rapid `apply()` calls used to trigger N encodes +
/// N disk writes even though the pipeline already serialized them. Now
/// only the single save whose revision equals the pipeline's latest
/// observed save revision actually encodes and writes.
enum SessionPersistenceOp: Sendable {
    case save(SessionStateCodable)
    case clear
}

// MARK: - Pipeline actor

/// Ordered channel for session-store writes. Holds a reference to the
/// underlying `SessionStore` and processes enqueued ops one at a time
/// in strict submission order. A monotonic `ackRevision` tracks the
/// highest revision the pipeline has seen — any op submitted with a
/// lower revision is a stale write and is dropped before touching the
/// store.
///
/// Ordering is enforced by chaining Task handles: every enqueued op's
/// work runs inside a new `Task` that awaits the previous op's Task.
/// This prevents the actor-reentrancy hazard where two ops would
/// otherwise interleave their IO waits (e.g. save starts its write,
/// suspends, clear acquires the actor, runs through to completion,
/// then save resumes and overwrites the cleared bytes).
///
/// Not public — constructed and owned by `ExecutionViewModel` via the
/// associated-object handle below. Tests exercise it indirectly through
/// the VM's `persist()` / `clearPersistedSession()` path.
actor SessionPersistencePipeline {
    private let store: SessionStore
    private var ackRevision: UInt64 = 0
    /// Highest `.save` revision the pipeline has accepted at enqueue
    /// time. When a chained task wakes up to process a `.save`, it
    /// drops its op if its revision is below this — a newer save has
    /// been queued meanwhile and will overwrite the bytes anyway, so
    /// the older encode + disk write are wasted work.
    ///
    /// Clears do NOT bump this. The relationship between save and clear
    /// is pure FIFO ordering, not coalescing — a clear after a save
    /// still needs to run even if the save is current.
    private var latestSaveRevision: UInt64 = 0
    /// Test-visible counter of saves that actually reached `store.save`
    /// (i.e. were not coalesced away). Exposed via `encodeCount()` for
    /// the burst-coalesce regression in
    /// `ExecutionViewModelPersistencePipelineTests`. Not used outside
    /// tests.
    private var performedSaveCount: Int = 0
    /// Handle to the most recently enqueued op. The next enqueue awaits
    /// this handle before running, giving us strict FIFO execution even
    /// across the async `await store.save(…)` suspension points.
    private var tail: Task<Void, Never>?

    init(store: SessionStore) {
        self.store = store
    }

    /// Submit an op. Returns immediately — the returned Task completes
    /// when this op's work (or stale-rejection short-circuit) is done.
    /// Chained to the previous submission so ordering is preserved even
    /// when `store.save` / `store.clear` suspend.
    ///
    /// Coalescing: `.save` ops carry the raw snapshot, not encoded
    /// bytes. Before the chained task encodes + writes, it checks
    /// whether a newer save has been enqueued in the meantime. If so,
    /// this op is dropped without encoding — the newer save will
    /// encode+write the authoritative bytes. This is the perf-001 fix:
    /// rapid `apply()` bursts no longer translate into one JSON encode
    /// + one disk write per tap.
    ///
    /// Swallows errors. Persistence failure is never user-fatal — the
    /// in-memory state is authoritative for this session; the next tick
    /// retries.
    @discardableResult
    func enqueue(op: SessionPersistenceOp, revision: UInt64) -> Task<Void, Never> {
        // Update the latest-save watermark synchronously on the actor at
        // enqueue time. The chained task reads this later to decide
        // whether to drop itself as superseded. Must happen BEFORE the
        // Task is constructed so a subsequent enqueue that bumps the
        // watermark can still cause an already-chained (but not yet
        // running) task to skip its work.
        if case .save = op {
            if revision > latestSaveRevision {
                latestSaveRevision = revision
            }
        }
        let previous = tail
        let store = self.store
        let task = Task { [weak self] in
            // Wait for the preceding op to finish before starting ours.
            // This is what gives the pipeline its ordering guarantee —
            // an actor alone would reenter on `await`.
            await previous?.value
            // Fetch the up-to-date ack revision on our own actor before
            // deciding whether to run. Using a nested `await self?.…`
            // hop keeps the ackRevision read/write serialized.
            guard let self else { return }
            if await self.shouldRun(op: op, revision: revision) == false { return }
            do {
                switch op {
                case .save(let snapshot):
                    // Encode inside the pipeline — if a newer save has
                    // since been enqueued, `shouldRun` already dropped
                    // us before getting here, so we only pay the
                    // encode cost for writes that actually land.
                    let data = try JSONEncoder().encode(snapshot)
                    try await store.save(data)
                case .clear:
                    try await store.clear()
                }
            } catch {
                // Intentional: see doc comment above.
            }
        }
        tail = task
        return task
    }

    /// Gate helper run on the actor: advance `ackRevision` iff the
    /// incoming op is fresh AND, for saves, the op has not been
    /// superseded by a newer save enqueued after this one. Separated so
    /// the `Task` in `enqueue(op:…)` can decide-and-update atomically
    /// while holding the actor.
    private func shouldRun(op: SessionPersistenceOp, revision: UInt64) -> Bool {
        // Explicit stale-rejection (e.g. a test enqueueing a
        // hand-crafted older revision): drop if below the acked peak.
        guard revision >= ackRevision else { return false }
        // Coalesce saves: a save is superseded when a newer save has
        // been enqueued after it. The newer save will write the
        // authoritative bytes; this one would be immediately overwritten
        // and only burns CPU + I/O.
        if case .save = op {
            if revision < latestSaveRevision { return false }
        }
        ackRevision = revision
        if case .save = op {
            performedSaveCount &+= 1
        }
        return true
    }

    /// Test-only readout of the number of saves that actually reached
    /// `store.save`. Used to prove perf-001's coalescing: a burst of N
    /// `apply()` calls should yield a performed-save count ≪ N, not N.
    func performedSaveCountForTesting() -> Int {
        performedSaveCount
    }
}

// MARK: - VM handle

/// Pipeline-handle accessors for the VM. The backing storage
/// (`persistencePipeline` + `persistenceRevision`) is declared on the
/// main class body — see the "Persistence pipeline" section of
/// `ExecutionViewModel.swift`. Keeping the accessors here preserves the
/// separation between the class's public intent surface and the write-
/// ordering plumbing.
@MainActor
extension ExecutionViewModel {

    /// Bump the revision and return the new value. Every enqueue uses a
    /// fresh revision; the counter is strictly monotonic per VM.
    func nextPersistenceRevision() -> UInt64 {
        persistenceRevision &+= 1
        return persistenceRevision
    }

    /// Lazily materialize the pipeline for this VM. Returns nil when no
    /// store is wired (offline/test path that skips persistence). The
    /// handle is cached on the VM itself so subsequent calls reuse the
    /// same actor instance — re-constructing per call would reset the
    /// pipeline's internal `ackRevision` / `tail` and break both the
    /// stale-rejection gate and the FIFO ordering guarantee.
    func persistencePipelineHandle() -> SessionPersistencePipeline? {
        if let existing = persistencePipeline { return existing }
        guard let store = sessionStore else { return nil }
        let fresh = SessionPersistencePipeline(store: store)
        persistencePipeline = fresh
        return fresh
    }

    /// Drop the pipeline + revision bookkeeping for this VM. Kept as a
    /// method for parity with tests that wire up multiple VMs in a row
    /// and want a clean slate between them; with the fix that moved
    /// storage off of a process-global `[ObjectIdentifier: …]` table it
    /// is no longer needed for lifetime hygiene, but the call sites are
    /// harmless and resetting is cheap.
    func resetPersistencePipelineForTesting() {
        persistencePipeline = nil
        persistenceRevision = 0
    }
}
