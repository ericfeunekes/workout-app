// main.swift — entry point for `swift run DesignSystemTests`.
//
// DesignSystem is a visual package — we can't meaningfully run snapshot tests
// without a simulator. What we can do: construct each primitive with
// representative params and assert it compiles and exposes the expected
// surface (non-nil instance, non-empty accessibility label where applicable).
//
// These tests catch regressions in primitive signatures — if a parameter gets
// renamed or removed, the test fails to compile.

import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif
import DesignSystem

// ---- Token smoke tests --------------------------------------------------

runCase("DSSpacing scale is monotonically increasing") {
    try expect(DSSpacing.xs < DSSpacing.sm, "xs < sm")
    try expect(DSSpacing.sm < DSSpacing.md, "sm < md")
    try expect(DSSpacing.md < DSSpacing.lg, "md < lg")
    try expect(DSSpacing.lg < DSSpacing.xl, "lg < xl")
    try expect(DSSpacing.xl < DSSpacing.xxl, "xl < xxl")
    try expect(DSSpacing.xxl < DSSpacing.xxxl, "xxl < xxxl")
}

runCase("DSSpacing numeric values match documented scale") {
    try expectEqual(DSSpacing.xs, 2)
    try expectEqual(DSSpacing.sm, 4)
    try expectEqual(DSSpacing.md, 8)
    try expectEqual(DSSpacing.lg, 12)
    try expectEqual(DSSpacing.xl, 16)
    try expectEqual(DSSpacing.xxl, 24)
    try expectEqual(DSSpacing.xxxl, 40)
}

#if canImport(SwiftUI)

// ---- Primitive smoke tests ----------------------------------------------
//
// Each case constructs the primitive with representative params. The goal is
// compile-time signature protection — if the test builds, the primitive is
// callable from the outside in the documented shape. We don't render or
// snapshot; ViewInspector-free.

runCase("DSButton constructs in every style") {
    _ = DSButton(title: "log set", style: .primary, action: {})
    _ = DSButton(title: "skip", style: .ghost, action: {})
    _ = DSButton(title: "reset", style: .danger, action: {})
    _ = DSButton(title: "disabled", style: .primary, disabled: true, action: {})
}

runCase("DSButton pins minimum action height") {
    try expect(
        DSButton.minimumHeight >= 44,
        "button minimum height must satisfy platform hit-target expectation"
    )
}

runCase("DSChip constructs with every tone") {
    _ = DSChip(label: "last session", value: "fri")
    _ = DSChip(label: "offline")
    _ = DSChip(label: "pr", value: "102.5 kg", tone: .accent)
    _ = DSChip(label: "paused", tone: .muted)
}

runCase("DSPill constructs editable and non-editable") {
    _ = DSPill(value: "102.5", caption: "kg", isEditable: true, onTap: {})
    _ = DSPill(value: "5", caption: "reps")
    _ = DSPill(value: "2", caption: nil, isEditable: false)
}

runCase("DSRing constructs across progress range") {
    _ = DSRing(progress: 0.0)
    _ = DSRing(progress: 0.5, lineWidth: 8)
    _ = DSRing(progress: 1.0)
    // Out-of-range inputs don't crash — the clamp lives in the body; we just
    // exercise the init here.
    _ = DSRing(progress: -0.5)
    _ = DSRing(progress: 1.5)
}

runCase("DSKeypad constructs with and without decimal") {
    _ = DSKeypad(onDigit: { _ in }, onDelete: {}, onDecimal: {})
    _ = DSKeypad(onDigit: { _ in }, onDelete: {})
}

runCase("SetEditSheetModel emits only supported touched fields") {
    let model = SetEditSheetModel(availableFields: [.reps, .rir])
    model.setLoad(100, unit: "kg")
    model.setReps(8)
    model.clearRIR()
    model.setSkipped(true)
    model.setNotes("bad plate math")
    let intent = model.commit()

    try expectEqual(intent.reps, 8)
    try expectEqual(intent.rir, .clear)
    try expectEqual(intent.load, nil)
    try expectEqual(intent.loadUnit, nil)
    try expectEqual(intent.skipped, nil)
    try expectEqual(intent.notes, .preserve)
}

runCase("SetEditSheetModel supports target field vocabulary") {
    let model = SetEditSheetModel(availableFields: Set(SetEditField.allCases), scope: .remaining)
    model.setLoad(100, unit: "kg")
    model.setReps(5)
    model.setRIR(9)
    model.setBodyweight(82.5, unit: "kg")
    model.setSide(.left)
    model.setDistance(400, unit: "m")
    model.setDuration(seconds: 75)
    model.setSkipped(true)
    model.setNotes("corrected after workout")
    model.setCarry(load: 32, loadUnit: "kg", distance: 40, distanceUnit: "m")
    let intent = model.commit()

    try expectEqual(intent.scope, .remaining)
    try expectEqual(intent.load, 100)
    try expectEqual(intent.loadUnit, "kg")
    try expectEqual(intent.reps, 5)
    try expectEqual(intent.rir, .set(5))
    try expectEqual(intent.bodyweight, 82.5)
    try expectEqual(intent.bodyweightUnit, "kg")
    try expectEqual(intent.side, .left)
    try expectEqual(intent.distance, 400)
    try expectEqual(intent.distanceUnit, "m")
    try expectEqual(intent.durationSeconds, 75)
    try expectEqual(intent.skipped, true)
    try expectEqual(intent.notes, .set("corrected after workout"))
    try expectEqual(intent.carryLoad, 32)
    try expectEqual(intent.carryLoadUnit, "kg")
    try expectEqual(intent.carryDistance, 40)
    try expectEqual(intent.carryDistanceUnit, "m")
}

runCase("DSCard wraps arbitrary content") {
    _ = DSCard { Text("hello") }
    _ = DSCard(padding: 0) { Text("flush") }
    _ = DSDivider()
}

runCase("DSWeightLabel constructs at hero and inline sizes") {
    _ = DSWeightLabel(
        number: "102.5",
        size: 64,
        weight: .light,
        color: DSColors.accentInk
    )
    _ = DSWeightLabel(
        number: "85",
        unit: "kg",
        size: 22,
        weight: .medium,
        color: DSColors.foreground
    )
}

runCase("DSExerciseIconView constructs every icon at compact and tiled sizes") {
    try expectEqual(DSExerciseIcon.allCases.count, 15)
    for icon in DSExerciseIcon.allCases {
        _ = DSExerciseIconView(icon: icon, size: 24)
        _ = DSExerciseIconView(icon: icon, size: 48, showsTile: true)
    }
}

// ---- Color token smoke --------------------------------------------------

runCase("DSColors exposes every documented token") {
    // Force-evaluate each token so any missing symbol surfaces at compile time
    // and any runtime lazy failure surfaces here. Colors are value types — the
    // assignments are cheap.
    _ = DSColors.background
    _ = DSColors.surface
    _ = DSColors.surfaceElevated
    _ = DSColors.surfaceHigh
    _ = DSColors.foreground
    _ = DSColors.foregroundMuted
    _ = DSColors.foregroundDim
    _ = DSColors.foregroundFaint
    _ = DSColors.accent
    _ = DSColors.accentMuted
    _ = DSColors.accentInk
    _ = DSColors.divider
    _ = DSColors.border
    _ = DSColors.warn
    _ = DSColors.success
    _ = DSColors.danger
}

runCase("DSTypography exposes the full ramp") {
    _ = DSTypography.display
    _ = DSTypography.title
    _ = DSTypography.subtitle
    _ = DSTypography.body
    _ = DSTypography.caption
    _ = DSTypography.subLabel
    _ = DSTypography.mono
    _ = DSTypography.monoLarge
}

runCase("DSAnimation exposes every motion token") {
    _ = DSAnimation.quick
    _ = DSAnimation.standard
    _ = DSAnimation.slow
}

#endif

reportAndExit()
