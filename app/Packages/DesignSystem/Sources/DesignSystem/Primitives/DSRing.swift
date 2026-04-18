// DSRing.swift
//
// Countdown ring for rest timer. Mirrors the JSX `Ring` primitive in
// `docs/design/components/primitives.jsx` — same geometry (starts at 12 o'clock,
// sweeps clockwise). Progress animates via `DSAnimation.standard`.
//
// Uses tokens: `DSColors.foregroundFaint` (track), `DSColors.accent`
// (progress), `DSAnimation.standard` (value animation).

import SwiftUI

/// A circular progress ring. `progress` ranges 0...1 — 0 is empty, 1 is full.
/// Renders as a thin stroked circle with a clockwise sweep from 12 o'clock.
///
/// - Parameters:
///   - progress: Completion fraction. Values outside 0...1 are clamped.
///   - lineWidth: Stroke width in points. Default 6; bump for hero rings.
public struct DSRing: View {
    private let progress: Double
    private let lineWidth: CGFloat

    public init(progress: Double, lineWidth: CGFloat = 6) {
        self.progress = progress
        self.lineWidth = lineWidth
    }

    public var body: some View {
        let clamped = min(max(progress, 0), 1)
        ZStack {
            Circle()
                .stroke(DSColors.foregroundFaint, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    DSColors.accent,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(DSAnimation.standard, value: clamped)
        }
    }
}

#Preview {
    HStack(spacing: DSSpacing.xl) {
        DSRing(progress: 0.0).frame(width: 80, height: 80)
        DSRing(progress: 0.35).frame(width: 80, height: 80)
        DSRing(progress: 0.8, lineWidth: 10).frame(width: 120, height: 120)
    }
    .padding()
    .background(DSColors.background)
}
