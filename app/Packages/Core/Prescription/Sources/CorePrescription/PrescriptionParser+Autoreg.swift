// PrescriptionParser+Autoreg.swift
//
// Autoreg sub-object parser. Split out of `PrescriptionParser.swift` so the
// parent file stays under SwiftLint caps. When `autoreg` is present, the
// item's `target_rir` becomes required (it's the reference point the
// overshoot/undershoot thresholds are measured from).

import Foundation
import CoreDomain

extension PrescriptionParser {

    /// Parses the `autoreg` subobject + sibling `target_rir` into an
    /// Autoreg struct. Returns nil when `autoreg` is absent.
    ///
    /// Default inner values are unit-aware (R2.10): when the prescription
    /// carries `weight_unit: "lb"` (or no explicit unit — lb is the
    /// default) and the author omits `overshoot_step_kg`, the step
    /// defaults to `5.0` (smallest loadable plate pair in a US gym). For
    /// `"kg"` the default is `1.25`. Explicit authoring always wins.
    /// `overshoot_at` / `undershoot_at` default to `2`, `apply_to` to
    /// `"remaining"`, per `docs/prescription.md` § "Autoregulation".
    func parseAutoreg(
        _ obj: [String: Any],
        shape: String,
        unit: WeightUnit
    ) -> Result<Autoreg?, ParseError> {
        let autoreg: [String: Any]
        switch readOptionalObject(obj, "autoreg") {
        case .failure(let e): return .failure(e)
        case .success(.none): return .success(nil)
        case .success(.some(let d)): autoreg = d
        }
        let targetRir: Int
        switch readAutoregTargetRir(obj, shape: shape) {
        case .failure(let e): return .failure(e)
        case .success(let v): targetRir = v
        }
        switch readAutoregThresholds(autoreg, unit: unit) {
        case .failure(let e): return .failure(e)
        case .success(let thresholds):
            let applyTo: Autoreg.ApplyTo
            switch readAutoregApplyTo(autoreg) {
            case .failure(let e): return .failure(e)
            case .success(let v): applyTo = v
            }
            return .success(Autoreg(
                targetRir: targetRir,
                overshootAt: thresholds.overshootAt,
                overshootStepKg: thresholds.overshootStep,
                undershootAt: thresholds.undershootAt,
                undershootStepKg: thresholds.undershootStep,
                applyTo: applyTo
            ))
        }
    }

    /// When autoreg is opted into, target_rir is required at the item
    /// level — it's the reference point that overshoot_at / undershoot_at
    /// are offsets from. Parsers for individual shapes always read
    /// target_rir as optional; here we enforce the coupling.
    private func readAutoregTargetRir(
        _ obj: [String: Any],
        shape: String
    ) -> Result<Int, ParseError> {
        switch readOptionalInt(obj, "target_rir") {
        case .failure(let e): return .failure(e)
        case .success(.none):
            return .failure(.missingKey("target_rir", inShape: "autoreg(\(shape))"))
        case .success(.some(let v)): return .success(v)
        }
    }

    private struct AutoregThresholds {
        let overshootAt: Int
        let overshootStep: Double
        let undershootAt: Int
        let undershootStep: Double
    }

    private func readAutoregThresholds(
        _ autoreg: [String: Any],
        unit: WeightUnit
    ) -> Result<AutoregThresholds, ParseError> {
        let overshootAt: Int
        switch readOptionalInt(autoreg, "overshoot_at") {
        case .failure(let e): return .failure(e)
        case .success(let v): overshootAt = v ?? 2
        }
        let defaultStep = defaultAutoregStep(for: unit)
        let overshootStep: Double
        switch readOptionalDouble(autoreg, "overshoot_step_kg") {
        case .failure(let e): return .failure(e)
        case .success(let v): overshootStep = v ?? defaultStep
        }
        let undershootAt: Int
        switch readOptionalInt(autoreg, "undershoot_at") {
        case .failure(let e): return .failure(e)
        case .success(let v): undershootAt = v ?? 2
        }
        let undershootStep: Double
        switch readOptionalDouble(autoreg, "undershoot_step_kg") {
        case .failure(let e): return .failure(e)
        case .success(let v): undershootStep = v ?? defaultStep
        }
        return .success(AutoregThresholds(
            overshootAt: overshootAt,
            overshootStep: overshootStep,
            undershootAt: undershootAt,
            undershootStep: undershootStep
        ))
    }

    private func readAutoregApplyTo(
        _ autoreg: [String: Any]
    ) -> Result<Autoreg.ApplyTo, ParseError> {
        switch readOptionalString(autoreg, "apply_to") {
        case .failure(let e): return .failure(e)
        case .success(.none): return .success(.remaining)
        case .success(.some(let s)):
            guard let parsed = Autoreg.ApplyTo(rawValue: s) else {
                return .failure(.wrongType(key: "apply_to", expected: "\"remaining\""))
            }
            return .success(parsed)
        }
    }
}
