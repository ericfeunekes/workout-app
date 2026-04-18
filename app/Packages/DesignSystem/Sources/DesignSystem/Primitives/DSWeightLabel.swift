// DSWeightLabel.swift
//
// Render a weight value + its unit with matched type styling. The prior
// pattern — a `Text("\(formatKilograms(x)) kg")` string — let the mono
// digits sit next to a default-design "kg" that inherited the run font
// weight, which in practice drifted in and out of visual match across
// screens (bug-027). This primitive locks the pairing: digits and unit
// share the same monospaced family and weight; the unit renders at
// ~0.55× the number face and at the same baseline.
//
// Uses tokens: the caller supplies the numeric size + weight. The unit
// is derived from those params so "big headline 64pt .light" and "mono
// inline 14pt .regular" both stay coherent.

import SwiftUI

/// A horizontal weight readout — digits + unit — with matching font
/// family and weight. Callers pass the numeric display string (already
/// formatted via `formatKilograms`) and the visual weight/size of the
/// primary face; this view renders the unit at a smaller matching size
/// so the pairing stays coherent across the hero, banner, and ledger.
///
/// - Parameters:
///   - number: The formatted number ("102.5"). `BW` should be rendered
///     directly by the caller — this view always shows a unit.
///   - unit: The unit string ("kg"). Defaults to "kg".
///   - size: Point size for the number face.
///   - weight: Font weight shared by number and unit.
///   - color: Fill for the number. Unit inherits a muted variant.
///   - mutedUnitColor: Fill for the unit. Defaults to `foregroundMuted`
///     so the pair reads as "value + unit" rather than "two equal
///     weights".
public struct DSWeightLabel: View {
    private let number: String
    private let unit: String
    private let size: CGFloat
    private let weight: Font.Weight
    private let color: Color
    private let mutedUnitColor: Color

    public init(
        number: String,
        unit: String = "kg",
        size: CGFloat,
        weight: Font.Weight,
        color: Color,
        mutedUnitColor: Color = DSColors.foregroundMuted
    ) {
        self.number = number
        self.unit = unit
        self.size = size
        self.weight = weight
        self.color = color
        self.mutedUnitColor = mutedUnitColor
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: max(DSSpacing.sm, size * 0.08)) {
            Text(number)
                .font(.system(size: size, weight: weight, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(color)
            // Unit sits at ~55% of the number face in the SAME family +
            // weight so "kg" doesn't drift into a different visual key.
            // Prior pattern rendered "102.5 kg" as a single Text run with
            // the run font — which in practice meant the unit picked up
            // whichever font was nearest in the hierarchy, usually the
            // default sans rather than the mono next to the digits.
            Text(unit)
                .font(.system(size: size * 0.55, weight: weight, design: .monospaced))
                .foregroundStyle(mutedUnitColor)
        }
    }
}

#Preview("hero · 64 .light") {
    DSWeightLabel(
        number: "102.5",
        size: 64,
        weight: .light,
        color: DSColors.accentInk
    )
    .padding()
    .background(DSColors.background)
}

#Preview("inline · 22 .medium") {
    DSWeightLabel(
        number: "85",
        size: 22,
        weight: .medium,
        color: DSColors.foreground
    )
    .padding()
    .background(DSColors.background)
}
