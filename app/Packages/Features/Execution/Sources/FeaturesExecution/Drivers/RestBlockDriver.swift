// RestBlockDriver.swift
//
// TimingDriver for `timing_mode = rest` — a standalone rest block between
// work blocks (e.g. an AMRAP → rest → EMOM sequence in a CrossFit-style
// workout). The block has NO `workout_items`; its `timing_config_json`
// supplies a single `duration_sec` value that drives the rest countdown.
//
// Cursor model (Decision A1 — documented in the driver brief):
//
//   A zero-item block cannot carry a normal `(blockIndex, itemIndex,
//   setIndex)` cursor since there is no item-0 and no set-1. Rather than
//   introduce a separate `Cursor.restBlock(blockIndex:)` case (Option A2)
//   and touch every mutation handler, we keep the cursor uniform and
//   treat `(blockIndex, 0, 1)` on a zero-item block as a sentinel. The
//   reducer's `advanceCursor` lands the cursor on the rest block; the
//   view model detects `structure.itemsPerBlock[blockIndex] == 0` and
//   flips the route to `.rest` with `restEndsAt = now + duration_sec`
//   without going through `.active`. On `advanceFromRest` from a
//   zero-item block, the reducer jumps straight to the next block
//   (see `SessionReducer+Handlers.swift` § `nextCursor`).
//
// This driver therefore has no Active screen content (rest is the only
// route for these blocks) and cannot accept set logs (there are no sets
// to log). All three protocol methods exist to satisfy `TimingDriver`
// but two are defensive no-ops; `restDuration` is the real behavior.
//
// Why keep the driver thin:
//   - The view model owns the route transition (pure reducer preference —
//     the reducer never calls `Date()` or reads `driver.restDuration`).
//   - The reducer's `.enterRest` mutation already does the work of
//     setting `route = .rest` + `restEndsAt`. The VM dispatches that
//     with the duration this driver parses from the block's JSON blob.
//   - No autoreg, no mutations, no last-time chip — nothing to compute.

import Foundation
import CoreDomain
import CorePrescription
import CoreSession
import WorkoutCoreFoundation

public struct RestBlockDriver: TimingDriver {

    private let parser: PrescriptionParser

    public init(parser: PrescriptionParser = PrescriptionParser()) {
        self.parser = parser
    }

    // MARK: - Active content

    /// Rest blocks never show an Active screen — `route` goes straight
    /// from the previous block's advance into `.rest`. Returning nil here
    /// is the contract: `ActiveView` shows a defensive empty state, which
    /// should never render because the VM keeps the route on `.rest` for
    /// the duration of this block.
    public func activeContent(
        state: SessionState,
        context: WorkoutContext
    ) -> ActiveContent? {
        nil
    }

    // MARK: - Rest duration

    /// Parse `timing_config_json.duration_sec` for the current block.
    /// Integer seconds — the authoring vocabulary specifies Double, we
    /// pass through whatever the parser returns. Malformed or missing
    /// config yields 0 seconds (matches `StraightSetsDriver`'s
    /// parse-failure fallback) so the rest auto-advances immediately
    /// rather than trapping the user.
    public func restDuration(
        state: SessionState,
        context: WorkoutContext
    ) -> TimeInterval {
        let c = state.cursor
        guard let block = context.block(at: c.blockIndex) else { return 0 }
        switch parser.parseTimingConfig(
            timingMode: block.timingMode.rawValue,
            configJSON: block.timingConfigJSON
        ) {
        case .success(let config):
            if case .rest(let durationSec) = config {
                return durationSec
            }
            return 0
        case .failure:
            return 0
        }
    }

    // MARK: - Log outcome

    /// Rest blocks have no sets, so `onSetLogged` should never be called.
    /// Defensive: return an empty outcome if it somehow fires.
    public func onSetLogged(
        state: SessionState,
        context: WorkoutContext,
        event: SetLogEvent
    ) -> DriverLogOutcome {
        DriverLogOutcome()
    }
}
