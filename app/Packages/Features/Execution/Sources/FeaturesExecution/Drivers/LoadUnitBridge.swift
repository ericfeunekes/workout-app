// LoadUnitBridge.swift
//
// Bridge between the domain `WeightUnit` and the formatter `LoadUnit`.
// Core/Foundation (where `LoadUnit` lives) has no dependency on
// CoreDomain, so the raw-value bridge is done at the Features layer.
// This one-liner extension keeps every driver callsite noise-free.
//
// The raw values are contract-tested to be identical on both enums
// (`app/Packages/Core/Foundation/Tests/WorkoutCoreFoundationTests/main.swift`
// pins `LoadUnit.kg.rawValue == "kg"` etc.), so the bridge cannot fail
// at runtime — a mismatch would be caught at build time.

import CoreDomain
import WorkoutCoreFoundation

extension LoadUnit {
    /// Bridge a `WeightUnit` (the domain wire enum) to a `LoadUnit` (the
    /// formatter's unit suffix). Force-unwraps the `rawValue:` init since
    /// the enums share raw values by contract test; a mismatch here would
    /// be an unshippable build regression, not a runtime input.
    init(setPlanUnit: WeightUnit) {
        // swiftlint:disable:next force_unwrapping
        self = LoadUnit(rawValue: setPlanUnit.rawValue)!
    }
}
