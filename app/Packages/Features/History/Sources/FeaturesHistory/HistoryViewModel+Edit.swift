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
// Weight-unit correctness: the load override arrives as an
// `EditPastSetLoadCommit` carrying both the numeric value AND the unit
// the user typed in. We write the SetLog's `weight` / `weightUnit`
// together — the unit is preserved as what the user just confirmed,
// not silently stamped as `.kg`. That prevents the footgun where a
// `.lb` row gets corrected and becomes a `.kg` row numerically equal
// to the old pounds (a 100 lb row "corrected" would read as 100 kg,
// twice the actual load).
//
// RIR three-state: the commit carries `.preserve` / `.clear` / `.set(n)`
// so the edit can distinguish "user didn't touch RIR" (leave existing)
// from "user explicitly cleared RIR" (write nil). Plain `Int?` would
// collapse those two — the earlier shape did, which is why an explicit
// clear from the sheet never reached the SetLog.
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
    /// the `reps` / `rir` / `load` overrides (nil/`.preserve` = preserve),
    /// writes the updated row to the local cache, emits telemetry, fires
    /// the push hook, and reloads so the detail view re-renders with the
    /// corrected row. Unknown IDs are silent no-ops — the cache read
    /// would just miss and we'd return without side effects.
    ///
    /// `load.unit` is written onto the SetLog verbatim — the sheet
    /// rendered the numbers in the unit the row was recorded in, so
    /// preserving the unit on save is the contract.
    ///
    /// Called from `HistorySessionDetailView` when the user commits an
    /// `EditSetSheet`.
    public func editPastSet(
        workoutID: WorkoutID,
        setLogID: SetLogID,
        reps: Int?,
        rir: EditPastSetRirCommit,
        load loadCommit: EditPastSetLoadCommit?
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
        switch rir {
        case .preserve:
            break
        case .clear:
            edited.rir = nil
        case .set(let value):
            edited.rir = value
        }
        if let loadCommit {
            edited.weight = loadCommit.value
            // Always stamp the unit the user just confirmed. Never
            // default to `.kg` when a concrete unit is in hand —
            // doing so silently corrupts lb-stored rows.
            edited.weightUnit = loadCommit.unit
        }

        do {
            // Corrective edits stay pinned to their original workout —
            // `workoutID` passes through unchanged so the denormalized
            // column on the existing SetLog row is preserved (R1.4
            // SetLog denormalization, see `SwiftDataModels.swift`).
            try await cache.saveSetLogs([edited], workoutID: workoutID)
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

    public func canResetToday(workoutID: WorkoutID) -> Bool {
        guard let session = rawSessions.first(where: { $0.workout.id == workoutID }),
              let date = session.sortDate else {
            return false
        }
        return calendar.isDate(date, inSameDayAs: now())
    }

    @discardableResult
    public func resetWorkout(workoutID: WorkoutID) async -> Bool {
        guard canResetToday(workoutID: workoutID) else { return false }

        do {
            try await cache.resetWorkout(workoutID: workoutID)
        } catch {
            return false
        }

        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: "state",
            name: "history.workout_reset",
            workoutID: workoutID
        ))

        if let onWorkoutReset {
            // swiftlint:disable:next no_direct_task_unstructured
            Task { [onWorkoutReset, workoutID] in
                await onWorkoutReset(workoutID)
            }
        }

        await load()
        return true
    }

    /// Emit a single `history.past_set_edited` telemetry event tagged
    /// with the workout and the SetLog it mutated. Payload carries
    /// `{itemID, setIndex, setLogID}` — the same shape as
    /// `execution.past_set_edited` — so an analyst can join either
    /// surface's edit events through the item the set belongs to.
    /// The event itself is still tagged with `workoutID` at the row
    /// level (via `Event.workoutID`) so the event_log row is reachable
    /// per workout without the payload having to duplicate that column.
    /// Parallels
    /// `ExecutionViewModel.emitPastSetEdited(itemID:setIndex:setLogID:)`.
    ///
    /// All ids are written via `.wireID` so the payload obeys the
    /// "every id on the wire is lowercase UUID" invariant (Codex R1.3).
    /// Encoded via a typed `Encodable` struct rather than hand-formatted
    /// — one less place to forget the lowercasing.
    func emitPastSetEdited(workoutID: WorkoutID, setLog: SetLog) {
        let payload = HistoryPastSetEditedEventPayload(
            itemID: setLog.workoutItemID.wireID,
            setLogID: setLog.id.wireID,
            setIndex: setLog.setIndex
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // swiftlint:disable:next force_try
        let data = try! encoder.encode(payload)
        // swiftlint:disable:next force_unwrapping
        let dataJSON = String(data: data, encoding: .utf8)!
        telemetry.emit(Event(
            sessionID: TelemetrySession.id,
            kind: "state",
            name: "history.past_set_edited",
            dataJSON: dataJSON,
            workoutID: workoutID,
            setLogID: setLog.id
        ))
    }
}

// MARK: - Telemetry payload

/// Payload for `history.past_set_edited`. CamelCase field names match
/// `execution.past_set_edited` so the two surfaces compose into one
/// event stream — an analyst joins by `itemID` + `setLogID` without
/// caring which UI emitted the edit. The R1.3 fix landed the lowercase-
/// UUID invariant; qa-036 swapped the misspelled `workoutID` to the
/// documented `itemID` so the shape actually matches the contract.
private struct HistoryPastSetEditedEventPayload: Encodable {
    let itemID: String
    let setLogID: String
    let setIndex: Int
}
