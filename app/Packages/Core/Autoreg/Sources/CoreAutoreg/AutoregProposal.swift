// AutoregProposal.swift
//
// The result of a single `Autoreg.propose(...)` call. Pure data — no
// behaviour. The proposal describes:
//
//   - which direction to nudge remaining sets (up / down),
//   - the new load the proposal would apply,
//   - the reason the rule fired (so the app can surface it in the banner).
//
// See docs/prescription.md § "Autoregulation · Trigger rules" for the
// authoritative rules that produce each Reason case.

import Foundation

public struct AutoregProposal: Equatable, Sendable, Hashable {

    /// Direction of the load adjustment on remaining sets.
    public enum Direction: String, Sendable, Equatable, Hashable {
        case up
        case down
    }

    /// Why autoreg fired. Carries the observed inputs so the banner (and
    /// debugging) can say "You hit RIR 4 vs target 2 (+2 threshold) →
    /// bumping load" without the caller re-deriving the numbers.
    public enum Reason: Equatable, Sendable, Hashable {
        /// `loggedRir >= targetRir + threshold` — load was too light.
        case overshoot(rirLogged: Int, targetRir: Int, threshold: Int)

        /// `(prescribed - actual) >= threshold` — reps were missed.
        case undershootReps(prescribed: Int, actual: Int, threshold: Int)

        /// `loggedRir == 0 && targetRir > 0` — hit failure when the target
        /// wasn't zero.
        case hitFailure(targetRir: Int)
    }

    public let direction: Direction
    public let newLoadKg: Double
    public let reason: Reason

    public init(direction: Direction, newLoadKg: Double, reason: Reason) {
        self.direction = direction
        self.newLoadKg = newLoadKg
        self.reason = reason
    }
}
