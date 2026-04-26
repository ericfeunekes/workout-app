// ExecutionViewModel+Push.swift
//
// Push-enqueue helpers split out of `ExecutionViewModel.swift` so the
// class body stays under SwiftLint's `type_body_length` cap. These are
// fire-and-forget — they never gate the UI mutation path on network
// latency. See `docs/sync.md` § "Push protocol" and the file header on
// `ExecutionViewModel.swift` for the semantics.
//
// Telemetry emit helpers + payload structs live in
// `ExecutionViewModel+Telemetry.swift` so both files stay under
// SwiftLint's `file_length` cap.
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
        deterministicUUID(from: "\(itemID.uuidString.lowercased())|\(setIndex)")
    }

    /// Derive a stable `UserParameter.id` for a given
    /// `(userID, key, observedAt)`. Same derivation technique as
    /// `setLogID(itemID:setIndex:)` — the ID is client-owned so a push
    /// that replays after a crash between commit and queue-remove hits
    /// the server's upsert-on-id path instead of inserting a duplicate
    /// row (and `user_parameters` is append-only, so a duplicate would
    /// pollute history forever).
    ///
    /// `observedAt` is encoded as the underlying `timeIntervalSince1970`
    /// (to microsecond precision) so the same wall-clock instant produces
    /// the same id regardless of timezone formatting. The caller is
    /// responsible for passing a stable timestamp — typically the
    /// `clock.now` captured once at `saveAndDone` entry.
    static func userParameterID(userID: UUID, key: String, observedAt: Date) -> UUID {
        // 6-digit precision matches the server's SQLite DateTime rounding
        // and is far below the wall-clock resolution a human can trigger
        // two `saveAndDone` taps within. Stable string formatting (POSIX,
        // no locale fingerprint).
        let seconds = observedAt.timeIntervalSince1970
        let canonical = String(format: "%@|%@|%.6f", userID.uuidString.lowercased(), key, seconds)
        return deterministicUUID(from: canonical)
    }

    /// Shared MD5-based UUID derivation used by `setLogID` and
    /// `userParameterID`. Kept private — callers should pick a domain-
    /// specific helper so collisions between namespaces are impossible
    /// by construction (each caller picks a disjoint canonical string
    /// shape).
    private static func deterministicUUID(from canonical: String) -> UUID {
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
    /// 5. Enqueue the persisted-session clear on the serial pipeline.
    ///    Routing through the pipeline (rather than touching
    ///    `sessionStore.clear()` directly) is required — `.save` triggers
    ///    a persist() via `apply`; that save and this clear MUST land in
    ///    order or a restart could restore the saved-but-not-cleared
    ///    bytes. See `ExecutionViewModel+PersistencePipeline.swift`.
    func performSaveAndDone(note: String?, bodyweightKg: Double?) {
        emitSessionMutation("save")
        let completedAt = clock.now
        let persistedNote = Self.normalizeNote(note)
        // Terminal status push carries the note so the server is
        // authoritative for the value — the next `sync/pull` would
        // otherwise overwrite the local cache's freshly-typed note
        // with the server's stale value.
        enqueueStatusCompleted(at: completedAt, notes: persistedNote)
        writeCompletionToLocalCache(note: persistedNote)
        if let kg = bodyweightKg {
            enqueueBodyweight(kg: kg, at: completedAt)
        }
        // For v0 we hand the reducer an empty freshItems/structure and
        // rely on the shell's Route flip to move the user back to Today.
        let empty = SessionState.Structure(itemsPerBlock: [], setsPerItem: [])
        apply([.save(freshItems: [], freshStructure: empty)])
        clearPersistedSession()
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
        let loggedSet = itemLog?.sets.first(where: { $0.setIndex == setIndex })
        // `SetPlan.loadKg` is `Double?` (nil == loadless / BW). The
        // optional-chain on loggedSet would double-wrap to `Double??`;
        // use `flatMap(\.self)` to flatten so `nil` uniformly means
        // "no load" whether the row is missing or the row is loadless.
        // SetLog.weight is `Double?` by design; a loadless row writes
        // nil so History renders "BW" instead of fabricating "0 lb".
        let loggedLoad: Double? = loggedSet?.loadKg.flatMap { $0 }
        let loggedUnit = loggedSet?.unit
        let performedExerciseID = itemLog?.performedExerciseID
        // The reducer stamped `completedAt` at log time; reuse it so
        // this push and any future past-set edit push carry the same
        // timestamp (the server's upsert overwrites on each push).
        let completedAt = loggedSet?.completedAt ?? clock.now
        let skipped = loggedSet?.skipped ?? false
        let setLog = SetLog(
            id: Self.setLogID(itemID: item.id, setIndex: setIndex),
            workoutItemID: item.id,
            performedExerciseID: performedExerciseID,
            setIndex: setIndex,
            reps: skipped ? nil : reps,
            weight: skipped ? nil : loggedLoad,
            weightUnit: skipped || loggedLoad == nil ? nil : loggedUnit,
            durationSec: skipped ? nil : loggedSet?.durationSec,
            distanceM: skipped ? nil : loggedSet?.distanceM,
            rir: skipped ? nil : rir,
            isWarmup: false,
            skipped: skipped,
            side: loggedSet?.side ?? .bilateral,
            startedAt: loggedSet?.startedAt,
            completedAt: completedAt,
            hrAvgBpm: skipped ? nil : loggedSet?.hrAvgBpm,
            cadenceAvgSpm: skipped ? nil : loggedSet?.cadenceAvgSpm
        )
        // swiftlint:disable:next no_direct_task_unstructured
        Task { @MainActor in
            await onSetLogged(setLog)
        }
    }

    /// Cardio sibling of `enqueueLoggedSet`. Builds a cardio `SetLog`
    /// (no `reps` / `rir`, populated `durationSec` / `distanceM` /
    /// `hrAvgBpm` / `cadenceAvgSpm` / `startedAt`, and authored load
    /// when the target is loaded) and pushes it through `onSetLogged`
    /// if the hook is wired. Same deterministic UUID scheme as the
    /// strength path so retries upsert in place.
    func enqueueLoggedCardioSet(
        item: WorkoutItem,
        setIndex: Int,
        input: CardioLogInput
    ) {
        guard let onSetLogged = push.onSetLogged else { return }
        let itemLog = state.items.first(where: { $0.itemID == item.id })
        let loggedSet = itemLog?.sets.first(where: { $0.setIndex == setIndex })
        let performedExerciseID = itemLog?.performedExerciseID
        let completedAt = loggedSet?.completedAt ?? clock.now
        let weight = loggedSet?.loadKg
        let skipped = loggedSet?.skipped ?? false
        let setLog = SetLog(
            id: Self.setLogID(itemID: item.id, setIndex: setIndex),
            workoutItemID: item.id,
            performedExerciseID: performedExerciseID,
            setIndex: setIndex,
            reps: nil,
            weight: skipped ? nil : weight,
            weightUnit: skipped || weight == nil ? nil : loggedSet?.unit,
            durationSec: skipped ? nil : input.durationSec,
            distanceM: skipped ? nil : input.distanceM,
            rir: nil,
            isWarmup: false,
            skipped: skipped,
            side: loggedSet?.side ?? .bilateral,
            startedAt: loggedSet?.startedAt ?? input.startedAt,
            completedAt: completedAt,
            hrAvgBpm: skipped ? nil : input.hrAvgBpm,
            cadenceAvgSpm: skipped ? nil : input.cadenceAvgSpm
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
    /// `completedAt` is sourced from the ORIGINAL SetPlan's stamp (set
    /// by the reducer at `.logSet` time and preserved through
    /// `.editPastSet`). The server's `_upsert_set_log` overwrites the
    /// timestamp on every push, so if we sent `clock.now` here the edit
    /// would retroactively move the workout's timeline onto the edit
    /// moment. A corrective edit fixes reps/rir/load — not the clock.
    /// Matches History's `editPastSet` in `HistoryViewModel+Edit`, which
    /// preserves the cached timestamp for the same reason.
    ///
    /// Silent no-op when the hook is nil (pure-offline test path) or
    /// when the target set is missing from state (a stale itemID /
    /// setIndex shouldn't reach here since `editPastSet` goes through
    /// the reducer's `updateSet` guard, but the guard here is cheap).
    /// A SetPlan without a `completedAt` (edit reaches us on a set that
    /// was never logged — shouldn't happen, the reducer's
    /// `applyEditPastSet` guards on `done`) falls back to `clock.now`
    /// so the push still carries a valid timestamp; the guard is
    /// defense-in-depth, not a live path.
    func enqueueEditedSet(
        item: WorkoutItem,
        setIndex: Int
    ) {
        guard let onSetLogged = push.onSetLogged else { return }
        guard let itemLog = state.items.first(where: { $0.itemID == item.id }),
              let set = itemLog.sets.first(where: { $0.setIndex == setIndex }) else {
            return
        }
        let completedAt = set.completedAt ?? clock.now
        // `weightUnit` only makes sense paired with a non-nil weight.
        // A loadless row (`loadKg == nil`) writes both as nil so History
        // renders "BW" and analytics don't see a phantom unit on a BW set.
        let skipped = set.skipped
        let setLog = SetLog(
            id: Self.setLogID(itemID: item.id, setIndex: setIndex),
            workoutItemID: item.id,
            performedExerciseID: itemLog.performedExerciseID,
            setIndex: setIndex,
            reps: skipped ? nil : set.reps,
            weight: skipped ? nil : set.loadKg,
            weightUnit: skipped || set.loadKg == nil ? nil : set.unit,
            durationSec: skipped ? nil : set.durationSec,
            distanceM: skipped ? nil : set.distanceM,
            rir: skipped ? nil : set.rir,
            isWarmup: false,
            skipped: skipped,
            side: set.side,
            startedAt: set.startedAt,
            completedAt: completedAt,
            hrAvgBpm: skipped ? nil : set.hrAvgBpm,
            cadenceAvgSpm: skipped ? nil : set.cadenceAvgSpm
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

    /// Enqueue the terminal status_update + kick a flush. The periodic
    /// foreground flusher (every ~60s, see `PushFlusher` in Shell) would
    /// eventually drain both, but on completion the user is still
    /// looking at the ledger — we want the write to reach the server in
    /// seconds, not a minute. Per `docs/sync.md` § "Cadence", push is
    /// fire-and-forget at the UI level; an enqueue that can't reach the
    /// server stays on disk and retries on the next tick.
    func enqueueStatusCompleted(at completedAt: Date, notes: String? = nil) {
        let workoutID = state.workoutID
        let hooks = push
        // swiftlint:disable:next no_direct_task_unstructured
        Task { @MainActor in
            await hooks.onStatusChanged?(workoutID, .completed, completedAt, notes)
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
    /// Per-set timestamps:
    ///   - `completedAt` is sourced from `SetPlan.completedAt`, which the
    ///     reducer stamped at `.logSet` time. Falls back to the workout's
    ///     completion moment only if the set has no stamp (defensive — a
    ///     `done` set with `completedAt == nil` shouldn't occur in the
    ///     live path; legacy persisted sessions from before this field
    ///     existed might).
    ///   - `startedAt` is sourced from `SetPlan.startedAt`, stamped at
    ///     `.logSet` time by the reducer from `state.workStartedAt` (which
    ///     the VM stamps on `.start` and `.advanceFromRest`). This is
    ///     "when rest ended and work began" — NOT "previous set's
    ///     completedAt", which would fold rest time INTO set duration
    ///     (a 10s bench press + 90s rest would look like a 100s set).
    ///     See `SessionState.workStartedAt`.
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
        let setLogs = buildCompletionSetLogs(fallbackCompletedAt: completedAt)
        // swiftlint:disable:next no_direct_task_unstructured
        Task { @MainActor in
            await writer(completedWorkout, setLogs)
        }
    }

    /// Flatten every done `SetPlan` in `state.items` into a `SetLog`
    /// stream for the local-cache completion writer. Extracted so
    /// `writeCompletionToLocalCache` stays under SwiftLint's
    /// `function_body_length` cap.
    ///
    /// Walks items in cursor order (the flat `state.items` order matches
    /// block→item authoring order; within an item sets are 1..N).
    ///
    /// `startedAt` is read straight off `SetPlan.startedAt` — no chaining
    /// across sets. The reducer's `.logSet` / `.logCardioSet` handlers
    /// stamped it at log time from `state.workStartedAt` (which the VM
    /// populates on `.start` and every `.advanceFromRest`). Chaining via
    /// the previous set's `completedAt` would fold rest time INTO set
    /// duration — semantically wrong for per-set work-time analysis. See
    /// `SessionState.workStartedAt`.
    ///
    /// `fallbackCompletedAt` is used when a done SetPlan is missing its
    /// stamp — defensive against legacy persisted state seeded before
    /// the reducer-side stamp landed; the live path always has a stamp.
    private func buildCompletionSetLogs(fallbackCompletedAt: Date) -> [SetLog] {
        var setLogs: [SetLog] = []
        for itemLog in state.items {
            for set in itemLog.sets.sorted(by: { $0.setIndex < $1.setIndex })
            where set.done {
                let setCompletedAt = set.completedAt ?? fallbackCompletedAt
                // Cardio rows carry duration/distance/HR/cadence and may
                // still carry load (farmer carries, weighted hangs). Cluster
                // strength rows also carry duration, so a duration field by
                // itself is not enough; an explicit unit-aware target wins.
                let isCardio = set.workTarget?.kind == .duration
                    || set.workTarget?.kind == .distance
                    || set.distanceM != nil
                    || set.hrAvgBpm != nil
                    || set.cadenceAvgSpm != nil
                    || (set.durationSec != nil && set.reps == 0 && set.rir == nil)
                let reps: Int? = isCardio ? nil : set.reps
                let repsForLog: Int? = set.skipped ? nil : reps
                let weight: Double? = set.skipped ? nil : set.loadKg
                // `weightUnit` only makes sense paired with a non-nil
                // weight. A loadless strength row (BW, loadless AMRAP
                // token, `.empty` placeholder) writes weight=nil and
                // unit=nil so History renders "BW" and analytics don't
                // see a phantom unit on a BW set.
                let weightUnit: WeightUnit? = weight == nil ? nil : set.unit
                setLogs.append(SetLog(
                    id: Self.setLogID(itemID: itemLog.itemID, setIndex: set.setIndex),
                    workoutItemID: itemLog.itemID,
                    performedExerciseID: itemLog.performedExerciseID,
                    setIndex: set.setIndex,
                    reps: repsForLog,
                    weight: weight,
                    weightUnit: weightUnit,
                    durationSec: set.skipped ? nil : set.durationSec,
                    distanceM: set.skipped ? nil : set.distanceM,
                    rir: set.skipped ? nil : set.rir,
                    isWarmup: false,
                    skipped: set.skipped,
                    side: set.side,
                    startedAt: set.startedAt,
                    completedAt: setCompletedAt,
                    hrAvgBpm: set.skipped ? nil : set.hrAvgBpm,
                    cadenceAvgSpm: set.skipped ? nil : set.cadenceAvgSpm
                ))
            }
        }
        return setLogs
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
    ///
    /// `id` is derived deterministically from `(userID, key, timestamp)`
    /// via `userParameterID` — the app crashing after the push commit
    /// but before the queue-remove replays the SAME id on the next flush,
    /// and the server upserts on id (see
    /// `server/workoutdb_server/api/user_parameters.py`). Without this
    /// the replay would insert a second row, and `user_parameters` is
    /// append-only so the duplicate would live forever.
    func enqueueBodyweight(kg: Double, at timestamp: Date) {
        guard let onUserParameterChanged = push.onUserParameterChanged else { return }
        let userID = context.workout.userID
        let key = "bodyweight_kg"
        let param = UserParameter(
            id: Self.userParameterID(userID: userID, key: key, observedAt: timestamp),
            userID: userID,
            key: key,
            value: String(kg),
            updatedAt: timestamp,
            source: .appLog
        )
        // swiftlint:disable:next no_direct_task_unstructured
        Task { @MainActor in
            await onUserParameterChanged(param)
        }
    }

    // MARK: - logSet helpers

    /// Capture the pre-log prescribed load so autoreg telemetry can
    /// carry `step_kg = |newLoad - prescribed|`. Reading from the
    /// post-log state would see the observed value the log mutation
    /// stamps and surface step_kg = 0 on every proposal. `loadKg`
    /// is `Double?` on SetPlan (nil = loadless / BW); the optional
    /// chain flattens to a single `Double?` via `flatMap(\.self)`.
    func prescribedLoadForLog(itemID: UUID, setIndex: Int) -> Double? {
        state.items
            .first(where: { $0.itemID == itemID })?
            .sets
            .first(where: { $0.setIndex == setIndex })?
            .loadKg
            .flatMap { $0 }
    }

    /// Post-apply side effects of `logSet`: update proposal banner state,
    /// emit telemetry, enqueue the SetLog push, and re-derive timers.
    /// Extracted so the public `logSet` entry point stays under
    /// SwiftLint's `function_body_length` cap. Lives on the `+Push`
    /// extension (rather than the main class body) so the class body
    /// stays under `type_body_length` too.
    func handleLogSetSideEffects(
        item: WorkoutItem,
        event: SetLogEvent,
        outcome: DriverLogOutcome,
        prescribedLoadKg: Double?
    ) {
        currentProposal = outcome.proposal
        currentProposalItemID = outcome.proposal == nil ? nil : item.id
        emitSessionMutation("logSet")
        if let proposal = outcome.proposal {
            emitAutoregProposed(
                itemID: item.id,
                setIndex: event.setIndex,
                proposal: proposal,
                prescribedLoadKg: prescribedLoadKg
            )
        }
        enqueueLoggedSet(
            item: item,
            setIndex: event.setIndex,
            reps: event.loggedReps,
            rir: event.loggedRir
        )
        // After a log, the cursor may have auto-advanced (restDuration=0
        // → buildLogMutations appended `.advanceFromRest`). Re-derive
        // block / Tabata timers so crossing a block boundary via a
        // zero-rest mode (AMRAP / ForTime / Continuous) refreshes them.
        enterRestIfZeroItemBlock()
        enterTabataWorkWindowIfNeeded()
        enterBlockTimerIfNeeded()
    }
}
