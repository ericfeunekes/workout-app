// PrescriptionParser+Autoreg.swift
//
// Autoreg sub-object parser. Split out of `PrescriptionParser.swift` so the
// parent file stays under SwiftLint caps. When `autoreg` is present, the
// item's `target_rir` becomes required (it's the reference point the
// overshoot/undershoot thresholds are measured from).

import Foundation

extension PrescriptionParser {

    /// Parses the `autoreg` subobject + sibling `target_rir` into an
    /// Autoreg struct. Returns nil when `autoreg` is absent. The doc's
    /// default values (overshoot/undershoot_at=2, step_kg=2.5, apply_to=
    /// "remaining") are applied for omitted inner keys.
    func parseAutoreg(
        _ obj: [String: Any],
        shape: String
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
        switch readAutoregThresholds(autoreg) {
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
        _ autoreg: [String: Any]
    ) -> Result<AutoregThresholds, ParseError> {
        let overshootAt: Int
        switch readOptionalInt(autoreg, "overshoot_at") {
        case .failure(let e): return .failure(e)
        case .success(let v): overshootAt = v ?? 2
        }
        let overshootStep: Double
        switch readOptionalDouble(autoreg, "overshoot_step_kg") {
        case .failure(let e): return .failure(e)
        case .success(let v): overshootStep = v ?? 2.5
        }
        let undershootAt: Int
        switch readOptionalInt(autoreg, "undershoot_at") {
        case .failure(let e): return .failure(e)
        case .success(let v): undershootAt = v ?? 2
        }
        let undershootStep: Double
        switch readOptionalDouble(autoreg, "undershoot_step_kg") {
        case .failure(let e): return .failure(e)
        case .success(let v): undershootStep = v ?? 2.5
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
