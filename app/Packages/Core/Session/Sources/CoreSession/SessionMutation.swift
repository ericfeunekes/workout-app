// SessionMutation.swift
//
// The full vocabulary of session-state transitions. Every user-visible
// session action and every timer-driven transition funnels through one of
// these cases. Adding a new case without adding a `reduce` handler is a
// compile-time error (switch exhaustiveness).
//
// Case groupings, from `app/README.md`:
//
//   Route transitions:   .start, .enterRest, .advanceFromRest,
//                        .complete, .save
//   Set log mutations:   .logSet, .editPendingSet, .editPastSet,
//                        .applyAutoregProposal
//   Item mutations:      .swap, .holdAutoreg
//   Note mutations:      .appendNote
//
// `applyAutoregProposal` is a separate mutation — not auto-fired by
// `.logSet` — because autoreg is advisory. The Features layer logs the
// set, calls `Autoreg.propose` from Core/Autoreg, surfaces a banner, and
// only dispatches `.applyAutoregProposal` on user acceptance (default)
// or drops it on Undo (with `.holdAutoreg`). Keeping the mutations
// separate makes the reducer honest about what the user opted into.

import Foundation
import CoreAutoreg
import CorePrescription
import WorkoutCoreFoundation

public enum SessionMutation: Equatable, Sendable {

    // --- Route transitions ---------------------------------------------

    /// Today → Active. Cursor is already at (0, 0, 1) by the start-state
    /// contract; this transition just flips the route.
    case start

    /// Set `restEndsAt = now + durationSec`, flip route to `.rest`.
    /// Passing `now` explicitly keeps the reducer pure — no `Date()`
    /// calls inside `reduce`.
    case enterRest(durationSec: Double, now: Date)

    /// Rest → Active (or Rest → Complete on the last set). Advances the
    /// cursor and clears `restEndsAt`.
    case advanceFromRest

    /// Force route to `.complete`. Does not clear state (the ledger
    /// surfaces the log). `.save` is the real "I'm done, clear everything"
    /// action.
    case complete

    /// Save-and-done. Requires the caller to hand in a fresh list of
    /// `ItemLog` (sets reset to prescribed values, `done=false`, `adjust=nil`,
    /// `autoregHeld=false`) and a fresh `Structure` — Core/Session does
    /// not know the prescription shape, so reseeding happens outside.
    /// Returned state has:
    ///   - `route = .today`
    ///   - `cursor = (0, 0, 1)`
    ///   - `items = freshItems`
    ///   - `restEndsAt = nil`
    ///   - `note = ""`
    ///   - `structure = freshStructure`
    ///   - `workoutID` preserved from the input state (for now; the
    ///     wrapping Features layer is expected to swap the state entirely
    ///     to the next day's workout).
    case save(freshItems: [SessionState.ItemLog], freshStructure: SessionState.Structure)

    // --- Set log mutations ---------------------------------------------

    /// Log a set. Finds the item, finds the 1-based `setIndex`, sets
    /// `done=true`, `reps=loggedReps`, `rir=loggedRir`, and stamps
    /// `completedAt = now`. Does NOT fire autoreg — that's a Features-
    /// layer concern (see file header).
    ///
    /// `now` is passed in explicitly rather than read from `Date()` so the
    /// reducer stays pure — callers (the view model) source it from their
    /// injected `Clock`. The stamp is session-authoritative: history edits
    /// preserve it, and the local-cache writer reads it per set so rest
    /// intervals reflect real timing rather than the final `saveAndDone`
    /// instant.
    case logSet(
        itemID: WorkoutItemID,
        setIndex: Int,
        loggedReps: Int,
        loggedRir: Int?,
        now: Date
    )

    /// Cardio log variant. Stamps `durationSec` / `distanceM` /
    /// `hrAvgBpm` / `cadenceAvgSpm` / `startedAt` on the SetPlan plus
    /// `done=true` and `completedAt = now`. `reps` is set to 0 (cardio
    /// intervals carry no rep count) and `rir` is forced nil. Every
    /// cardio metric is optional — a time-based interval with no HR
    /// source logs with only `durationSec` populated. Drivers for
    /// `intervals` / `continuous` dispatch this instead of `.logSet`.
    case logCardioSet(
        itemID: WorkoutItemID,
        setIndex: Int,
        durationSec: Double?,
        distanceM: Double?,
        hrAvgBpm: Int?,
        cadenceAvgSpm: Int?,
        startedAt: Date?,
        now: Date
    )

    /// Edit a pending (not-yet-logged) set. Updates loadKg/reps (either
    /// may be nil for "leave unchanged"), marks `adjust = .manual`.
    /// Session-local; the workout template is not mutated (that's a
    /// Features-layer concern — Core/Session doesn't know about templates).
    case editPendingSet(
        itemID: WorkoutItemID,
        setIndex: Int,
        loadKg: Double?,
        reps: Int?
    )

    /// Edit a past (logged) set. Corrective — does NOT retrigger autoreg.
    /// Updates loadKg/reps/rir (any may be nil for "leave unchanged"),
    /// sets `adjust` to `.manual` if it was `nil`, `.up`, or `.down`;
    /// leaves it at `.manual` if already manual.
    case editPastSet(
        itemID: WorkoutItemID,
        setIndex: Int,
        loadKg: Double?,
        reps: Int?,
        rir: Int?
    )

    /// Apply a proposal computed by Core/Autoreg. Delegates to
    /// `Autoreg.apply(proposal:to:)`, which respects `.manual` and `done`
    /// (see CoreAutoreg/Autoreg.swift header for the preserved rules).
    case applyAutoregProposal(
        itemID: WorkoutItemID,
        proposal: AutoregProposal
    )

    // --- Item mutations ------------------------------------------------

    /// Swap the performed exercise for this item. Sets
    /// `performedExerciseID = toExerciseID` and (when provided) writes
    /// `overrides` onto the `ItemLog`. Does not modify logged sets
    /// (preserves history). Does not reset `autoregHeld` — the hold is
    /// session-scoped and survives a swap by design (docs/prescription.md
    /// § "Hold scope": "The hold does not persist across workouts").
    ///
    /// `overrides` carries the alternative's `parameter_overrides_json`
    /// in parsed form. The Features layer also writes the reps/load
    /// overrides onto the item's remaining non-done `SetPlan` rows
    /// (outside this mutation — via `editPendingSet` calls dispatched
    /// alongside). The `target_rir` override cannot live on `SetPlan` so
    /// it flows through `overrides` and is read by the autoreg driver.
    case swap(
        itemID: WorkoutItemID,
        toExerciseID: ExerciseID,
        overrides: AlternativeOverrides? = nil
    )

    /// Flip `autoregHeld = true` on the target item. Idempotent.
    /// Core/Session only stores the flag; the Features layer is expected
    /// to read it before calling `Autoreg.propose`.
    case holdAutoreg(itemID: WorkoutItemID)

    // --- Note mutations ------------------------------------------------

    /// Append text to the workout-level note with a newline separator.
    /// Empty input is a no-op (idempotent on empty). If `note` is
    /// currently empty, the appended text replaces it (no leading
    /// newline).
    case appendNote(String)
}
