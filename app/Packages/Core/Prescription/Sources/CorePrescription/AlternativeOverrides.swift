// AlternativeOverrides.swift
//
// Parser for `exercise_alternative.parameter_overrides_json`. When the user
// swaps an exercise mid-session, the alternative can override any
// prescription key — `docs/prescription.md` § "Alternative prescription
// (overrides)" promises "Any prescription key can be overridden" — so the
// parser is widened to recognise the full key set. Overrides that are
// malformed for any key are rejected wholesale: we do not silently drop
// individual keys (a partial accept would leave the user in a half-swapped
// state with no feedback).
//
// Shape (from docs/features/exercise-swap.md and docs/specs/v2-architecture.md
// § "exercise_alternative"):
//
//   {
//     "sets": 3,              // Int? — adjusts the remaining SetPlan count
//                             //        on the item (the reducer truncates or
//                             //        extends the non-done tail).
//     "reps": 8,              // Int — overrides prescribed reps on remaining
//                             //        sets.
//     "load_kg": 72.5,        // Double — overrides prescribed load on
//                             //        remaining sets.
//     "target_rir": 3,        // Int — shadows the item's prescription
//                             //        target_rir for autoreg.
//     "per_side": true,       // Bool — the alternative is a per-side movement
//                             //        (single-arm dumbbell row). Stored on
//                             //        ItemLog.overrides; rendered by the
//                             //        Active surface when present.
//     "autoreg": {            // Partial autoreg override — each inner key
//                             //        is optional. Stored on
//                             //        ItemLog.overrides; the driver has not
//                             //        wired the override path yet (v0), so
//                             //        these values are parsed-but-inert
//                             //        until the driver slice lands.
//       "overshoot_at": 1,
//       "overshoot_step_kg": 1.25,
//       "undershoot_at": 1,
//       "undershoot_step_kg": 1.25,
//       "apply_to": "remaining"
//     }
//   }
//
// All keys are optional; a missing key means "don't override". A parse
// failure on any present key returns `.failure(ParseError)` — the caller
// decides what to surface; the current `ExecutionViewModel.swap` callsite
// treats a parse failure as "swap without overrides" so the user still
// gets the exercise change they asked for.
//
// Mid-session wiring (what the reducer does with each field today):
//   - `sets`           → adjusts the non-done tail of SetPlan rows and
//                        rewrites `structure.setsPerItem[b][i]`.
//   - `reps`           → mirrors onto non-done, non-manual SetPlan rows.
//   - `load_kg`        → mirrors onto non-done, non-manual SetPlan rows.
//   - `target_rir`     → stored on `ItemLog.overrides`; StraightSetsDriver
//                        reads `overrides?.targetRir` in preference to the
//                        prescription's authored target.
//   - `per_side`       → stored on `ItemLog.overrides`; no driver reads it
//                        yet (display-only concern for the swap UX).
//   - `autoreg`        → stored on `ItemLog.overrides`; no driver reads it
//                        yet. Flagged as a follow-up; the v0 drivers inherit
//                        the original item's autoreg config.
//
// NOT supported (by design, still):
//   - prescription-shape change — an override that would morph a
//     straightSets item into a bodyweight item or vice versa. Flagged
//     as S18 in docs/features/exercise-swap.md; not validated.

import Foundation
import CoreDomain

/// Partial override of an item's `autoreg` subobject. Each field is
/// optional — when set, it shadows the corresponding field on the
/// prescription's authored autoreg config; when nil, the original value
/// wins.
public struct AutoregOverrides: Sendable, Equatable, Hashable {
    public let overshootAt: Int?
    public let overshootStepKg: Double?
    public let undershootAt: Int?
    public let undershootStepKg: Double?
    public let applyTo: Autoreg.ApplyTo?

    public init(
        overshootAt: Int? = nil,
        overshootStepKg: Double? = nil,
        undershootAt: Int? = nil,
        undershootStepKg: Double? = nil,
        applyTo: Autoreg.ApplyTo? = nil
    ) {
        self.overshootAt = overshootAt
        self.overshootStepKg = overshootStepKg
        self.undershootAt = undershootAt
        self.undershootStepKg = undershootStepKg
        self.applyTo = applyTo
    }

    public var isEmpty: Bool {
        overshootAt == nil &&
        overshootStepKg == nil &&
        undershootAt == nil &&
        undershootStepKg == nil &&
        applyTo == nil
    }
}

/// Parsed `parameter_overrides_json` payload. All fields optional; absent
/// means "no override".
public struct AlternativeOverrides: Sendable, Equatable, Hashable {
    public let sets: Int?
    public let reps: Int?
    public let loadKg: Double?
    /// Unit the override's `load_kg` scalar is in. Optional — when absent
    /// on the override, callers should inherit the parent `SetPlan.unit`.
    /// Documented in `docs/prescription.md` § "Units · alternative
    /// overrides".
    public let unit: WeightUnit?
    public let targetRir: Int?
    public let perSide: Bool?
    public let autoreg: AutoregOverrides?

    public init(
        sets: Int? = nil,
        reps: Int? = nil,
        loadKg: Double? = nil,
        unit: WeightUnit? = nil,
        targetRir: Int? = nil,
        perSide: Bool? = nil,
        autoreg: AutoregOverrides? = nil
    ) {
        self.sets = sets
        self.reps = reps
        self.loadKg = loadKg
        self.unit = unit
        self.targetRir = targetRir
        self.perSide = perSide
        self.autoreg = autoreg
    }

    /// True when nothing was authored — the swap is a pure exercise
    /// substitution with no plan changes.
    public var isEmpty: Bool {
        sets == nil &&
        reps == nil &&
        loadKg == nil &&
        unit == nil &&
        targetRir == nil &&
        perSide == nil &&
        (autoreg?.isEmpty ?? true)
    }

    /// Parse a raw `parameter_overrides_json` string. `nil` or empty input
    /// returns `.success` with an empty overrides struct. A malformed
    /// payload — any key present with the wrong type, or an autoreg
    /// subobject with a malformed inner key — returns `.failure`; the
    /// caller decides whether to drop overrides entirely or surface the
    /// error.
    public static func parse(
        _ json: String?
    ) -> Result<AlternativeOverrides, ParseError> {
        guard let json, !json.isEmpty else { return .success(AlternativeOverrides()) }
        switch parseRootObject(json, shape: "parameter_overrides") {
        case .failure(let e): return .failure(e)
        case .success(let obj): return parse(dictionary: obj)
        }
    }

    /// Exposed for tests that already have the dictionary in hand.
    public static func parse(
        dictionary obj: [String: Any]
    ) -> Result<AlternativeOverrides, ParseError> {
        switch readOverrideScalars(obj) {
        case .failure(let e): return .failure(e)
        case .success(let scalars):
            switch readAutoregOverrides(obj) {
            case .failure(let e): return .failure(e)
            case .success(let autoreg):
                return .success(AlternativeOverrides(
                    sets: scalars.sets,
                    reps: scalars.reps,
                    loadKg: scalars.loadKg,
                    unit: scalars.unit,
                    targetRir: scalars.targetRir,
                    perSide: scalars.perSide,
                    autoreg: autoreg
                ))
            }
        }
    }
}

// MARK: - Helpers

private struct OverrideScalars {
    let sets: Int?
    let reps: Int?
    let loadKg: Double?
    let unit: WeightUnit?
    let targetRir: Int?
    let perSide: Bool?
}

private func readOverrideScalars(
    _ obj: [String: Any]
) -> Result<OverrideScalars, ParseError> {
    let sets: Int?
    switch readOptionalInt(obj, "sets") {
    case .failure(let e): return .failure(e)
    case .success(let v): sets = v
    }
    let reps: Int?
    switch readOptionalInt(obj, "reps") {
    case .failure(let e): return .failure(e)
    case .success(let v): reps = v
    }
    let loadKg: Double?
    switch readOptionalDouble(obj, "load_kg") {
    case .failure(let e): return .failure(e)
    case .success(let v): loadKg = v
    }
    // Overrides treat `weight_unit` as fully optional (unlike top-level
    // prescriptions, which default to `.lb`). `nil` here means "inherit
    // the parent SetPlan's unit" — callers resolve at apply time.
    let unit: WeightUnit?
    switch readOptionalString(obj, "weight_unit") {
    case .failure(let e): return .failure(e)
    case .success(.none): unit = nil
    case .success(.some(let raw)):
        guard let parsed = WeightUnit(rawValue: raw) else {
            return .failure(.wrongType(key: "weight_unit", expected: "\"kg\" or \"lb\""))
        }
        unit = parsed
    }
    let targetRir: Int?
    switch readOptionalInt(obj, "target_rir") {
    case .failure(let e): return .failure(e)
    case .success(let v): targetRir = v
    }
    let perSide: Bool?
    switch readOptionalBool(obj, "per_side") {
    case .failure(let e): return .failure(e)
    case .success(let v): perSide = v
    }
    return .success(OverrideScalars(
        sets: sets, reps: reps, loadKg: loadKg, unit: unit,
        targetRir: targetRir, perSide: perSide
    ))
}

private struct AutoregOverrideThresholds {
    let overshootAt: Int?
    let overshootStep: Double?
    let undershootAt: Int?
    let undershootStep: Double?
}

private func readAutoregOverrideThresholds(
    _ autoregObj: [String: Any]
) -> Result<AutoregOverrideThresholds, ParseError> {
    let overshootAt: Int?
    switch readOptionalInt(autoregObj, "overshoot_at") {
    case .failure(let e): return .failure(e)
    case .success(let v): overshootAt = v
    }
    let overshootStep: Double?
    switch readOptionalDouble(autoregObj, "overshoot_step_kg") {
    case .failure(let e): return .failure(e)
    case .success(let v): overshootStep = v
    }
    let undershootAt: Int?
    switch readOptionalInt(autoregObj, "undershoot_at") {
    case .failure(let e): return .failure(e)
    case .success(let v): undershootAt = v
    }
    let undershootStep: Double?
    switch readOptionalDouble(autoregObj, "undershoot_step_kg") {
    case .failure(let e): return .failure(e)
    case .success(let v): undershootStep = v
    }
    return .success(AutoregOverrideThresholds(
        overshootAt: overshootAt,
        overshootStep: overshootStep,
        undershootAt: undershootAt,
        undershootStep: undershootStep
    ))
}

private func readAutoregOverrideApplyTo(
    _ autoregObj: [String: Any]
) -> Result<Autoreg.ApplyTo?, ParseError> {
    switch readOptionalString(autoregObj, "apply_to") {
    case .failure(let e): return .failure(e)
    case .success(.none): return .success(nil)
    case .success(.some(let s)):
        guard let parsed = Autoreg.ApplyTo(rawValue: s) else {
            return .failure(.wrongType(key: "apply_to", expected: "\"remaining\""))
        }
        return .success(parsed)
    }
}

private func readAutoregOverrides(
    _ obj: [String: Any]
) -> Result<AutoregOverrides?, ParseError> {
    let autoregObj: [String: Any]
    switch readOptionalObject(obj, "autoreg") {
    case .failure(let e): return .failure(e)
    case .success(.none): return .success(nil)
    case .success(.some(let d)): autoregObj = d
    }
    let thresholds: AutoregOverrideThresholds
    switch readAutoregOverrideThresholds(autoregObj) {
    case .failure(let e): return .failure(e)
    case .success(let v): thresholds = v
    }
    let applyTo: Autoreg.ApplyTo?
    switch readAutoregOverrideApplyTo(autoregObj) {
    case .failure(let e): return .failure(e)
    case .success(let v): applyTo = v
    }
    return .success(AutoregOverrides(
        overshootAt: thresholds.overshootAt,
        overshootStepKg: thresholds.overshootStep,
        undershootAt: thresholds.undershootAt,
        undershootStepKg: thresholds.undershootStep,
        applyTo: applyTo
    ))
}
