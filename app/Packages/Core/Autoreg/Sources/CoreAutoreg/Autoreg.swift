// Autoreg.swift
//
// Pure functions that compute autoreg proposals and apply them to a list
// of remaining set plans. No state, no I/O. All session state (the "held"
// flag, the history of past-set edits, the set-log cursor) lives in
// Core/Session (future chunk). This package does not know whether the
// caller is on iPhone or Watch, nor whether the data came from SwiftData
// or a mock — it only sees numbers.
//
// Trigger rules — authoritative source: docs/prescription.md §
// "Autoregulation · Trigger rules". Reproduced here for code review:
//
//   OVERSHOOT (load too light):
//     loggedRir != nil && loggedRir >= targetRir + autoreg.overshootAt
//     → direction: .up, newLoadKg: prescribed + autoreg.overshootStepKg
//
//   UNDERSHOOT (reps):
//     (prescribedReps - loggedReps) >= autoreg.undershootAt
//     → direction: .down, newLoadKg: prescribed - autoreg.undershootStepKg
//
//   HIT-FAILURE:
//     loggedRir == 0 && targetRir > 0
//     → direction: .down, newLoadKg: prescribed - autoreg.undershootStepKg
//
// Precedence (when multiple rules could fire on a single set log):
//   1. undershoot-reps wins over hit-failure. The rep miss is the primary
//      signal; loggedRir=0 is consistent with it and would propose the
//      same direction/step. We report as .undershootReps so the banner
//      shows the numbers the user cares about (prescribed vs actual reps).
//   2. Overshoot and undershoot cannot fire together in practice — high
//      RIR is inconsistent with missing reps. If both conditions test
//      true (pathological authoring), undershoot wins: it carries the
//      harder "rep miss" evidence.
//
// RIR-null behavior (doc § "RIR nullable in set_log"):
//   - Overshoot cannot fire (no RIR value).
//   - Undershoot-reps can still fire on the rep miss.
//   - Hit-failure obviously cannot fire (needs loggedRir == 0).
//
// Load rounding:
//   Kilogram math is exact for the step sizes documented in the authoring
//   guide (2.5, 5.0, 1.0, 1.25). We do not round — the caller supplies
//   an exact load and an exact step and we emit their exact sum/difference.
//   If fractional plates ever motivate a different granularity we can
//   revisit; for now, keeping the math untouched preserves the step the
//   author chose. Tests assert exact equality (no epsilon tolerance).

import Foundation
import CorePrescription

public enum Autoreg {

    // -----------------------------------------------------------------
    // propose
    // -----------------------------------------------------------------

    /// Input bundle for `propose`. Groups the prescribed vs logged numbers
    /// plus the autoreg config into a single value so `propose` stays
    /// under SwiftLint's `function_parameter_count` cap and so call sites
    /// read as "propose(autoreg, for: input)" rather than a long parallel
    /// parameter list.
    public struct Input: Sendable {
        public let prescribedLoadKg: Double
        public let prescribedReps: Int
        public let loggedReps: Int
        public let loggedRir: Int?
        public let targetRir: Int
        public let autoreg: CorePrescription.Autoreg
        public let autoregHeld: Bool

        public init(
            prescribedLoadKg: Double,
            prescribedReps: Int,
            loggedReps: Int,
            loggedRir: Int?,
            targetRir: Int,
            autoreg: CorePrescription.Autoreg,
            autoregHeld: Bool = false
        ) {
            self.prescribedLoadKg = prescribedLoadKg
            self.prescribedReps = prescribedReps
            self.loggedReps = loggedReps
            self.loggedRir = loggedRir
            self.targetRir = targetRir
            self.autoreg = autoreg
            self.autoregHeld = autoregHeld
        }
    }

    /// Decide whether to fire an autoreg proposal after a single set has
    /// been logged.
    ///
    /// Returns `nil` when no proposal should be made. Cases that return
    /// nil:
    ///   - `input.autoregHeld == true` (user held autoreg for the session)
    ///   - No trigger condition is met
    ///   - `input.loggedRir == nil` AND reps were not missed enough to
    ///     trigger an undershoot
    ///
    /// The `input.targetRir` field is redundant with `input.autoreg.targetRir`
    /// (the Autoreg struct carries its own target). The brief accepts
    /// both explicitly for caller clarity; we treat the parameter as the
    /// source of truth so session-level overrides (e.g. a swap that
    /// changed the target) can be passed without rebuilding the Autoreg
    /// struct. In practice, Core/Session will pass `autoreg.targetRir`
    /// for both.
    public static func propose(_ input: Input) -> AutoregProposal? {
        // Hold flag shortcut.
        if input.autoregHeld { return nil }

        // Precedence:
        //   1. undershoot-reps
        //   2. hit-failure
        //   3. overshoot
        //
        // undershoot-reps is checked first because it subsumes the
        // hit-failure signal when both fire (loggedRir=0 + reps missed).

        let autoreg = input.autoreg
        let repsMissed = input.prescribedReps - input.loggedReps
        if repsMissed >= autoreg.undershootAt {
            return AutoregProposal(
                direction: .down,
                newLoadKg: Self.clampToZero(input.prescribedLoadKg - autoreg.undershootStepKg),
                reason: .undershootReps(
                    prescribed: input.prescribedReps,
                    actual: input.loggedReps,
                    threshold: autoreg.undershootAt
                )
            )
        }

        if let rir = input.loggedRir, rir == 0, input.targetRir > 0 {
            return AutoregProposal(
                direction: .down,
                newLoadKg: Self.clampToZero(input.prescribedLoadKg - autoreg.undershootStepKg),
                reason: .hitFailure(targetRir: input.targetRir)
            )
        }

        if let rir = input.loggedRir, rir >= input.targetRir + autoreg.overshootAt {
            return AutoregProposal(
                direction: .up,
                newLoadKg: input.prescribedLoadKg + autoreg.overshootStepKg,
                reason: .overshoot(
                    rirLogged: rir,
                    targetRir: input.targetRir,
                    threshold: autoreg.overshootAt
                )
            )
        }

        return nil
    }

    // -----------------------------------------------------------------
    // apply
    // -----------------------------------------------------------------

    /// Apply a proposal to a list of set plans. Returns a new array with
    /// per-set updates. The input list is not mutated.
    ///
    /// Rules (from docs/prescription.md § "Autoreg + manual edit"):
    ///   - A set with `done == true` is never touched — it's in the past.
    ///   - A set with `adjust == .manual` is never touched — the user
    ///     explicitly chose its load.
    ///   - A set with `loadKg == nil` (loadless / bodyweight) is never
    ///     touched — there is no numeric load to autoreg. The spec's
    ///     autoreg rules operate on kg adjustments; applying them to a
    ///     BW row would fabricate a numeric load out of thin air and
    ///     render "2.5 kg" for a bodyweight row.
    ///   - Any other set has its `loadKg` overwritten with the proposal's
    ///     `newLoadKg`, and its `adjust` set to `.up` / `.down` based on
    ///     the proposal direction.
    ///
    /// Note: this function treats every non-done, non-manual, numeric set
    /// as "remaining" — the caller is expected to pass only the sets that
    /// should be considered (typically: sets strictly after the one that
    /// just logged). Core/Session will own the windowing; Core/Autoreg
    /// stays pure.
    public static func apply(
        proposal: AutoregProposal,
        to sets: [SetPlan]
    ) -> [SetPlan] {
        let newAdjust: SetPlan.Adjust =
            (proposal.direction == .up) ? .up : .down
        return sets.map { set in
            if set.done { return set }
            if set.adjust == .manual { return set }
            if set.loadKg == nil { return set }
            return set.with(loadKg: proposal.newLoadKg, adjust: newAdjust)
        }
    }

    // -----------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------

    /// Floor the emitted load at zero. A bodyweight-weighted item (say,
    /// weighted dips @ 2.5 kg added) with an undershoot step of 5 kg
    /// would otherwise propose a -2.5 kg load — physically nonsense.
    /// Zero (no added load) is the correct floor: the user continues the
    /// movement at bodyweight for the remaining sets.
    private static func clampToZero(_ load: Double) -> Double {
        max(0.0, load)
    }
}
