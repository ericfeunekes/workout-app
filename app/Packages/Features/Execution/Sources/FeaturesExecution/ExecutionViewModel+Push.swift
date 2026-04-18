// ExecutionViewModel+Push.swift
//
// Push-enqueue helpers split out of `ExecutionViewModel.swift` so the
// class body stays under SwiftLint's `type_body_length` cap. These are
// fire-and-forget — they never gate the UI mutation path on network
// latency. See `docs/sync.md` § "Push protocol" and the file header on
// `ExecutionViewModel.swift` for the semantics.
//
// Deterministic set-log UUIDs:
//   `enqueueLoggedSet` and `enqueueEditedSet` BOTH derive the pushed
//   `SetLog.id` from `(itemID, setIndex)` via `setLogID(item:setIndex:)`.
//   Given the same `(itemID, setIndex)` pair, the function returns the
//   same UUID every time — so an original log push and any subsequent
//   past-set-edit push carry the SAME id. The server's set_log upsert
//   keys on UUID (see `docs/sync.md` § "Push protocol · idempotent
//   UUIDs"), so the edit lands as an update in place, not a second row.
//   Why deterministic instead of storing the UUID on SetPlan: avoids a
//   CoreSession schema change that would collide with parallel work on
//   `SessionState.ItemLog`. The (itemID, setIndex) tuple is unique per
//   session and stable across re-launches, which is all idempotency
//   needs.

import CryptoKit
import Foundation
import CoreDomain
import CoreSession
import CoreTelemetry
import WorkoutCoreFoundation

extension ExecutionViewModel {

    /// Derive a stable `SetLog.id` for a given `(itemID, setIndex)`.
    ///
    /// MD5 of the canonical string `"\(itemID.uuidString)|\(setIndex)"`
    /// feeds the 16-byte digest directly into `UUID(uuid:)` — the result
    /// is a UUID v3-style name-based UUID (RFC 4122 layout; we do not
    /// stamp the version/variant bits because we control both ends and
    /// only need stability, not RFC conformance).
    ///
    /// Collision space: 2^128; within a single session the namespace is
    /// `itemID × setIndex` (small integer), so practical collision risk
    /// is zero. `Insecure.MD5` is used deliberately — the hash is not
    /// a security primitive here, just a deterministic 128-bit derivation.
    static func setLogID(itemID: UUID, setIndex: Int) -> UUID {
        let canonical = "\(itemID.uuidString.lowercased())|\(setIndex)"
        let digest = Insecure.MD5.hash(data: Data(canonical.utf8))
        var bytes = [UInt8]()
        bytes.reserveCapacity(16)
        for byte in digest { bytes.append(byte) }
        let tuple: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: tuple)
    }

    /// Trim whitespace + empty-collapse a note string to nil. Exposed as
    /// `static` so the view layer can canonicalize before calling
    /// `saveAndDone` and tests can lock the behavior.
    static func normalizeNote(_ note: String?) -> String? {
        guard let note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The real body of `saveAndDone`. Extracted so the public entry
    /// point stays a 1-line dispatch and the class body stays under
    /// SwiftLint's `type_body_length` cap.
    ///
    /// Ordering matters here:
    /// 1. Enqueue the terminal status_update FIRST — the push queue
    ///    carries the `completed` flip even on the auto-advance path.
    /// 2. Hand the completed workout + set_logs to the local cache writer
    ///    (History reads it immediately).
    /// 3. Fire the bodyweight user_parameter (if any) through the push
    ///    hook — the shell wires this to both cache + push queue.
    /// 4. Dispatch `.save` through the reducer to wipe the in-memory
    ///    session and flip the route to `.today`.
    /// 5. Fire-and-forget the persisted-session clear.
    func performSaveAndDone(note: String?, bodyweightKg: Double?) {
        emitSessionMutation("save")
        let completedAt = clock.now
        let persistedNote = Self.normalizeNote(note)
        enqueueStatusCompleted(at: completedAt)
        writeCompletionToLocalCache(note: persistedNote)
        if let kg = bodyweightKg {
            enqueueBodyweight(kg: kg, at: completedAt)
        }
        // For v0 we hand the reducer an empty freshItems/structure and
        // rely on the shell's Route flip to move the user back to Today.
        let empty = SessionState.Structure(itemsPerBlock: [], setsPerItem: [])
        apply([.save(freshItems: [], freshStructure: empty)])
        // swiftlint:disable:next no_direct_task_unstructured
        Task { [sessionStore] in
            try? await sessionStore?.clear()
        }
    }

    /// Emit a single `execution.session_mutation` event tagged with the
    /// current workout. The mutation name rides in `data_json` so the
    /// server's `name` column stays bounded.
    func emitSessionMutation(_ which: String) {
        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: "state",
            name: "execution.session_mutation",
            dataJSON: #"{"mutation":"\#(which)"}"#,
            workoutID: context.workout.id
        ))
    }

    /// Emit an `execution.autoreg_*` event tagged with the current workout.
    func emitAutoreg(_ name: String) {
        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: "state",
            name: name,
            workoutID: context.workout.id
        ))
    }

    /// Emit an `execution.exercise_swap` event capturing the from/to
    /// exerciseIDs + whether the alternative authored any parameter
    /// overrides. Analyzed downstream for swap rate / override uptake.
    func emitSwapTelemetry(
        itemID: UUID,
        fromExerciseID: UUID?,
        toExerciseID: UUID,
        hadOverrides: Bool
    ) {
        let from = fromExerciseID?.uuidString ?? ""
        let payload = """
        {\
        "item_id":"\(itemID.uuidString)",\
        "from_exercise_id":"\(from)",\
        "to_exercise_id":"\(toExerciseID.uuidString)",\
        "had_overrides":\(hadOverrides ? "true" : "false")\
        }
        """
        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: "state",
            name: "execution.exercise_swap",
            dataJSON: payload,
            workoutID: context.workout.id
        ))
    }

    /// Build a `SetLog` from the item + the reducer-resolved load and push
    /// it through `onSetLogged` if the hook is wired. The load is read
    /// from the *post-log* state so it reflects the prescribed load for
    /// that `set_index` (autoreg's load adjustments run against the
    /// post-log state — they target remaining non-done sets — so reading
    /// `loadKg` here is still the prescribed load for the logged set).
    ///
    /// Fire-and-forget: we never await from the UI mutation path. The
    /// enqueue is persistent (SwiftData), so a brief delay is invisible.
    func enqueueLoggedSet(
        item: WorkoutItem,
        setIndex: Int,
        reps: Int,
        rir: Int?
    ) {
        guard let onSetLogged = push.onSetLogged else { return }
        let itemLog = state.items.first(where: { $0.itemID == item.id })
        let loggedLoad = itemLog?.sets.first(where: { $0.setIndex == setIndex })?.loadKg
        let performedExerciseID = itemLog?.performedExerciseID
        let setLog = SetLog(
            id: Self.setLogID(itemID: item.id, setIndex: setIndex),
            workoutItemID: item.id,
            performedExerciseID: performedExerciseID,
            setIndex: setIndex,
            reps: reps,
            weight: loggedLoad,
            weightUnit: loggedLoad == nil ? nil : .kg,
            rir: rir,
            isWarmup: false,
            completedAt: clock.now
        )
        // swiftlint:disable:next no_direct_task_unstructured
        Task { @MainActor in
            await onSetLogged(setLog)
        }
    }

    /// Enqueue a corrective past-set edit through the push hook.
    ///
    /// Reads the post-edit state for the target `(itemID, setIndex)` —
    /// the reducer has already been applied by the time this runs, so
    /// `loadKg` / `reps` / `rir` reflect the user's new values. Uses the
    /// same deterministic UUID as the original `enqueueLoggedSet` push
    /// so the server upserts in place (same id → update, not insert).
    ///
    /// Silent no-op when the hook is nil (pure-offline test path) or
    /// when the target set is missing from state (a stale itemID /
    /// setIndex shouldn't reach here since `editPastSet` goes through
    /// the reducer's `updateSet` guard, but the guard here is cheap).
    func enqueueEditedSet(
        item: WorkoutItem,
        setIndex: Int
    ) {
        guard let onSetLogged = push.onSetLogged else { return }
        guard let itemLog = state.items.first(where: { $0.itemID == item.id }),
              let set = itemLog.sets.first(where: { $0.setIndex == setIndex }) else {
            return
        }
        let setLog = SetLog(
            id: Self.setLogID(itemID: item.id, setIndex: setIndex),
            workoutItemID: item.id,
            performedExerciseID: itemLog.performedExerciseID,
            setIndex: setIndex,
            reps: set.reps,
            weight: set.loadKg,
            weightUnit: .kg,
            rir: set.rir,
            isWarmup: false,
            completedAt: clock.now
        )
        // swiftlint:disable:next no_direct_task_unstructured
        Task { @MainActor in
            await onSetLogged(setLog)
        }
    }

    /// Run the post-apply side effects for a `.editPastSet` mutation:
    /// enqueue the corrected `SetLog` through the push hook (same
    /// deterministic UUID as the original log → server upserts in place)
    /// and emit the `execution.past_set_edited` telemetry event. Called
    /// from `editPastSet` on the view model; factored out so the public
    /// entry point stays a 1-line dispatch.
    func handlePastSetEditSideEffects(itemID: UUID, setIndex: Int) {
        guard let item = findItem(id: itemID, in: context) else { return }
        enqueueEditedSet(item: item, setIndex: setIndex)
        emitPastSetEdited(
            itemID: itemID,
            setIndex: setIndex,
            setLogID: Self.setLogID(itemID: itemID, setIndex: setIndex)
        )
    }

    /// Emit the `execution.past_set_edited` telemetry event. Fixes
    /// bug-017 — past-set edits previously bypassed `emitSessionMutation`
    /// so the corrective-edit trail was missing from the event log.
    /// The `setLogID` in the payload matches the deterministic UUID used
    /// to push the corrected SetLog, so an analyst can join the event to
    /// the SetLog it mutated.
    func emitPastSetEdited(itemID: UUID, setIndex: Int, setLogID: UUID) {
        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: "state",
            name: "execution.past_set_edited",
            dataJSON:
                #"{"itemID":"\#(itemID.uuidString)","setIndex":\#(setIndex),"setLogID":"\#(setLogID.uuidString)"}"#,
            workoutID: context.workout.id,
            setLogID: setLogID
        ))
    }

    /// Enqueue the terminal status_update + kick a flush. The periodic
    /// foreground flusher (every ~60s, see `PushFlusher` in Shell) would
    /// eventually drain both, but on completion the user is still
    /// looking at the ledger — we want the write to reach the server in
    /// seconds, not a minute. Per `docs/sync.md` § "Cadence", push is
    /// fire-and-forget at the UI level; an enqueue that can't reach the
    /// server stays on disk and retries on the next tick.
    func enqueueStatusCompleted(at completedAt: Date) {
        let workoutID = state.workoutID
        let hooks = push
        // swiftlint:disable:next no_direct_task_unstructured
        Task { @MainActor in
            await hooks.onStatusChanged?(workoutID, .completed, completedAt)
            await hooks.onPushKick?()
        }
    }

    /// Build the completed `Workout` + `[SetLog]` from the current session
    /// and hand them to `localCompletionWriter` (if wired). Called from
    /// `saveAndDone` BEFORE the reducer's `.save` wipes the in-memory log.
    ///
    /// The Workout is constructed by taking the pulled template and
    /// stamping `status = .completed` + `completedAt = now`. `notes` is
    /// populated from the Complete screen's note field when the user
    /// typed something; an empty / whitespace-only note collapses to
    /// `nil` (see `ExecutionViewModel.normalizeNote`). The set_logs are
    /// one-per-done-SetPlan across every item in the session; this
    /// mirrors the semantics of `enqueueLoggedSet` (which enqueues one
    /// set_log per `logSet` call) but batches the whole session.
    ///
    /// Each local SetLog.id is derived from `setLogID(itemID:setIndex:)`
    /// — the SAME deterministic UUID that `enqueueLoggedSet` /
    /// `enqueueEditedSet` send to the server. Before bug-040, the local
    /// cache stamped a fresh `UUID()` here, so the History-cache row and
    /// the server row had different ids for the same set. A past-set
    /// edit from History then pushed the local (random) id to the
    /// server, which inserted a NEW row instead of updating in place.
    /// Using the deterministic id keeps local cache and server in lock-
    /// step — one logical set = one UUID everywhere.
    ///
    /// Fire-and-forget: the local write runs in a detached Task so it
    /// never blocks the UI mutation path. The push queue is the
    /// authoritative server path; this write exists so History sees the
    /// workout immediately.
    func writeCompletionToLocalCache(note: String? = nil) {
        guard let writer = localCompletionWriter else { return }
        let completedAt = clock.now
        let base = context.workout
        let completedWorkout = Workout(
            id: base.id,
            userID: base.userID,
            name: base.name,
            scheduledDate: base.scheduledDate,
            status: .completed,
            source: base.source,
            notes: note ?? base.notes,
            createdAt: base.createdAt,
            updatedAt: completedAt,
            completedAt: completedAt,
            tagsJSON: base.tagsJSON
        )
        var setLogs: [SetLog] = []
        for itemLog in state.items {
            for set in itemLog.sets where set.done {
                setLogs.append(SetLog(
                    id: Self.setLogID(itemID: itemLog.itemID, setIndex: set.setIndex),
                    workoutItemID: itemLog.itemID,
                    performedExerciseID: itemLog.performedExerciseID,
                    setIndex: set.setIndex,
                    reps: set.reps,
                    weight: set.loadKg,
                    weightUnit: .kg,
                    rir: set.rir,
                    isWarmup: false,
                    completedAt: completedAt
                ))
            }
        }
        // swiftlint:disable:next no_direct_task_unstructured
        Task { @MainActor in
            await writer(completedWorkout, setLogs)
        }
    }

    /// Build a `UserParameter` for the just-captured bodyweight and fire
    /// it through the `onUserParameterChanged` hook. Shell wires that to
    /// `SyncAPI.pushUserParameter` which enqueues
    /// `POST /api/user-parameters`. Skipped silently if no hook is wired
    /// (pure-offline test path).
    ///
    /// Value encoding: the server stores `value` as a freeform string per
    /// the append-only `user_parameters` contract. We use Swift's
    /// default `String(Double)` formatting which is locale-independent
    /// and deterministic ("82.5" → "82.5", "82.0" → "82.0"). Claude's
    /// analytical queries parse the value back to `float()`, which
    /// accepts either shape.
    func enqueueBodyweight(kg: Double, at timestamp: Date) {
        guard let onUserParameterChanged = push.onUserParameterChanged else { return }
        let param = UserParameter(
            id: UUID(),
            userID: context.workout.userID,
            key: "bodyweight_kg",
            value: String(kg),
            updatedAt: timestamp,
            source: .appLog
        )
        // swiftlint:disable:next no_direct_task_unstructured
        Task { @MainActor in
            await onUserParameterChanged(param)
        }
    }
}
