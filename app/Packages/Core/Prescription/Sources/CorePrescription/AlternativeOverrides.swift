// AlternativeOverrides.swift
//
// Parser for `exercise_alternative.parameter_overrides_json`. When the user
// swaps an exercise mid-session, the alternative can override a few
// prescription keys — reps, load_kg, target_rir — for the remaining sets
// of that item. v1 supports exactly those three keys; everything else is a
// TODO (see below).
//
// Shape (from docs/features/exercise-swap.md and docs/specs/v2-architecture.md
// § "exercise_alternative"):
//
//   {
//     "reps": 8,          // integer — replaces prescribed reps on remaining sets
//     "load_kg": 72.5,    // double  — replaces prescribed load on remaining sets
//     "target_rir": 3     // integer — shadows the item's prescription target_rir
//                         //           for autoreg (StraightSetsDriver reads
//                         //           the override via SessionState.ItemLog.overrides).
//   }
//
// All keys are optional; a missing key means "don't override". A parse
// failure on a present-but-wrong-type key returns `.none` (empty
// overrides) — the swap still happens, just without the overrides. The
// caller logs a TODO in that path; swap UX beats a "parse failed, swap
// aborted" error for a user who just long-pressed an exercise.
//
// NOT supported in v1 (deferred with a TODO):
//   - autoreg.step_kg / autoreg.overshoot_at / autoreg.undershoot_at
//     override — the alternative inherits the original item's autoreg
//     config wholesale. If a future alternative needs to change autoreg
//     behavior, extend this parser + the driver's autoreg path.
//   - sets count override — seed set count is locked at session start
//     (persisted to SessionState.structure.setsPerItem). Changing it
//     mid-item would require reseeding, which we don't do on swap.
//   - prescription-shape change — an override that would morph a
//     straightSets item into a bodyweight item or vice versa. Flagged
//     as S18 in docs/features/exercise-swap.md; not validated.

import Foundation

/// Parsed `parameter_overrides_json` payload. All fields optional; absent
/// means "no override".
public struct AlternativeOverrides: Sendable, Equatable, Hashable {
    public let reps: Int?
    public let loadKg: Double?
    public let targetRir: Int?

    public init(
        reps: Int? = nil,
        loadKg: Double? = nil,
        targetRir: Int? = nil
    ) {
        self.reps = reps
        self.loadKg = loadKg
        self.targetRir = targetRir
    }

    /// True when nothing was authored — the swap is a pure exercise
    /// substitution with no plan changes.
    public var isEmpty: Bool {
        reps == nil && loadKg == nil && targetRir == nil
    }

    /// Parse a raw `parameter_overrides_json` string. `nil` or empty input
    /// returns an empty overrides struct. A malformed payload also returns
    /// empty — the swap proceeds without parameter changes rather than
    /// failing loudly.
    public static func parse(_ json: String?) -> AlternativeOverrides {
        guard let json, !json.isEmpty else { return AlternativeOverrides() }
        switch parseRootObject(json, shape: "parameter_overrides") {
        case .failure:
            return AlternativeOverrides()
        case .success(let obj):
            return parse(dictionary: obj)
        }
    }

    /// Exposed for tests that already have the dictionary in hand.
    public static func parse(dictionary obj: [String: Any]) -> AlternativeOverrides {
        let reps: Int?
        switch readOptionalInt(obj, "reps") {
        case .success(let v): reps = v
        case .failure: reps = nil
        }
        let loadKg: Double?
        switch readOptionalDouble(obj, "load_kg") {
        case .success(let v): loadKg = v
        case .failure: loadKg = nil
        }
        let targetRir: Int?
        switch readOptionalInt(obj, "target_rir") {
        case .success(let v): targetRir = v
        case .failure: targetRir = nil
        }
        return AlternativeOverrides(
            reps: reps,
            loadKg: loadKg,
            targetRir: targetRir
        )
    }
}
