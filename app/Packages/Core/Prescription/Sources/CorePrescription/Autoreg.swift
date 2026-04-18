// Autoreg.swift
//
// The autoregulation configuration attached to an item's prescription.
// Shape documented in docs/prescription.md § "Autoregulation · Configuration
// shape".
//
// Defaults (`overshoot_at=2`, `overshoot_step_kg=2.5`, `undershoot_at=2`,
// `undershoot_step_kg=2.5`) come from the doc. They are applied by the
// parser when the authored object omits a key — the parser fills in the
// default rather than surfacing a missing-key error, to match the doc's
// "Omit the autoreg subobject on items that shouldn't autoadjust" posture:
// the object is opt-in; once opted in, missing inner keys are tolerated.

import Foundation

public struct Autoreg: Equatable, Sendable, Hashable {
    public let targetRir: Int
    public let overshootAt: Int
    public let overshootStepKg: Double
    public let undershootAt: Int
    public let undershootStepKg: Double
    public let applyTo: ApplyTo

    public enum ApplyTo: String, Sendable, Hashable {
        case remaining
    }

    public init(
        targetRir: Int,
        overshootAt: Int = 2,
        overshootStepKg: Double = 2.5,
        undershootAt: Int = 2,
        undershootStepKg: Double = 2.5,
        applyTo: ApplyTo = .remaining
    ) {
        self.targetRir = targetRir
        self.overshootAt = overshootAt
        self.overshootStepKg = overshootStepKg
        self.undershootAt = undershootAt
        self.undershootStepKg = undershootStepKg
        self.applyTo = applyTo
    }
}
