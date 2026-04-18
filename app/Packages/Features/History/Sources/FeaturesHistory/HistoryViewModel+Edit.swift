// HistoryViewModel+Edit.swift
//
// Past-set corrective edit from the History session-detail surface.
// Fixes bug-015: tapping a set row in `HistorySessionDetailView` now
// opens an `EditSetSheet` whose commit flows through `editPastSet`
// below, instead of flashing a highlight and doing nothing.
//
// Intentional parity with Execution's `editPastSet`:
//   - The pushed `SetLog.id` is DETERMINISTIC — the cache-resident
//     SetLog's existing `id` is reused verbatim (it was assigned by
//     `ExecutionViewModel.setLogID(itemID:setIndex:)` when the set
//     was first logged, so the server upsert-in-place contract holds
//     automatically; no re-derivation needed here).
//   - Edits emit `history.past_set_edited` telemetry, tagged with
//     `workoutID` + `setLogID`. Mirrors `execution.past_set_edited`
//     so the two surfaces' edit trails compose.
//   - Corrective edits NEVER retrigger autoreg — History writes the
//     updated SetLog directly and the reducer path is bypassed entirely.
//
// Why the History edit is local-cache + push, not reducer-dispatched:
//   History looks at COMPLETED workouts. The in-memory SessionState for
//   a completed workout has already been wiped by `saveAndDone`; there
//   is no live reducer to dispatch `.editPastSet` through. The cache
//   is the authoritative store for completed workouts; we write there
//   and fire the push, same as a fresh log.

import Foundation
import CoreDomain
import CoreTelemetry
import WorkoutCoreFoundation

extension HistoryViewModel {

    /// Corrective edit of one past set from a completed workout.
    ///
    /// Looks up the cached `SetLog` by `(workoutID, setLogID)`, applies
    /// the `reps` / `rir` / `loadKg` overrides (nil = preserve), writes
    /// the updated row to the local cache, emits telemetry, fires the
    /// push hook, and reloads so the detail view re-renders with the
    /// corrected row. Unknown IDs are silent no-ops — the cache read
    /// would just miss and we'd return without side effects.
    ///
    /// Called from `HistorySessionDetailView` when the user commits an
    /// `EditSetSheet`.
    public func editPastSet(
        workoutID: WorkoutID,
        setLogID: SetLogID,
        reps: Int?,
        rir: Int?,
        loadKg: Double?
    ) async {
        guard let session = rawSessions.first(where: { $0.workout.id == workoutID }),
              let existing = session.setLogs.first(where: { $0.id == setLogID }) else {
            return
        }
        // SetLog fields are `var`; copy-mutate is tighter than a fresh
        // init + every field name repeated. `id` / `workoutItemID` /
        // `performedExerciseID` / `setIndex` / `completedAt` / etc.
        // are all preserved untouched — an edit is corrective, not
        // identity-changing.
        var edited = existing
        if let reps { edited.reps = reps }
        if let rir { edited.rir = rir }
        if let loadKg {
            edited.weight = loadKg
            if edited.weightUnit == nil { edited.weightUnit = .kg }
        }

        do {
            try await cache.saveSetLogs([edited])
        } catch {
            // Local write failed — surface nothing to the UI (the edit
            // screen has already dismissed) but bail before pushing.
            // Telemetry skipped too; the caller can retry the edit.
            return
        }

        emitPastSetEdited(workoutID: workoutID, setLog: edited)

        if let onSetLogEdited {
            // swiftlint:disable:next no_direct_task_unstructured
            Task { [onSetLogEdited, edited] in
                await onSetLogEdited(edited)
            }
        }

        await load()
    }

    /// Emit a single `history.past_set_edited` telemetry event tagged
    /// with the workout and the SetLog it mutated. Payload carries the
    /// composite key so an analyst can join the event back to the
    /// updated row. Parallels
    /// `ExecutionViewModel.emitPastSetEdited(itemID:setIndex:setLogID:)`.
    func emitPastSetEdited(workoutID: WorkoutID, setLog: SetLog) {
        let payload = """
        {\
        "workoutID":"\(workoutID.uuidString)",\
        "setLogID":"\(setLog.id.uuidString)",\
        "setIndex":\(setLog.setIndex)\
        }
        """
        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: "state",
            name: "history.past_set_edited",
            dataJSON: payload,
            workoutID: workoutID,
            setLogID: setLog.id
        ))
    }
}
