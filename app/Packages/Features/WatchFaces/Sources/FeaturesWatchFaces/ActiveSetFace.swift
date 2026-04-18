// ActiveSetFace.swift
//
// Shown when the phone is in `SessionState.route == .active` and has
// pushed an ActiveBlock payload. v1 goal (ADR-2026-04-17-ux-scope § 4):
// "make starting and ending a set very easy" — so the whole face is a
// single tap zone. One tap fires `.setStarted(...)` back to the phone
// through WatchBridge.
//
// Layout (simplified from the grammar in
// `docs/design/src/watch-grammar.jsx` — the full superset/EMOM/AMRAP/etc.
// widgets are v1.1+):
//
//   Header :  "SET n / N"        · mono caption, uppercase
//   Hero   :  exercise name       · small caps, body size
//             prescription        · mono large
//   Footer :  HR placeholder      · "—" until HealthKit on-watch
//
// A single `Button` wraps the whole face so tap visuals (watchOS haptic
// + highlight) come for free. We use `.buttonStyle(.plain)` to strip
// the default chrome; the face owns its own layout.

import SwiftUI
import DesignSystem

struct ActiveSetFace: View {
    let payload: WatchFacesViewModel.ActivePayload
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                header

                Spacer(minLength: DSSpacing.sm)

                hero

                Spacer(minLength: DSSpacing.sm)

                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(DSSpacing.md)
            .contentShape(Rectangle()) // whole-face tap zone
            .background(DSColors.background)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sections

    private var header: some View {
        Text("SET \(payload.setNumber) / \(payload.setCount)")
            .font(DSTypography.caption)
            .tracking(0.5)
            .foregroundStyle(DSColors.foregroundDim)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            // Exercise name renders small-caps-ish via uppercased text +
            // tracking, matching the design grammar's "small caps"
            // treatment without bundling a custom font.
            Text(payload.exerciseName.uppercased())
                .font(DSTypography.body)
                .tracking(0.3)
                .foregroundStyle(DSColors.foreground)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            Text(payload.prescription)
                .font(DSTypography.monoLarge)
                .monospacedDigit()
                .foregroundStyle(DSColors.accentInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var footer: some View {
        HStack(spacing: DSSpacing.sm) {
            Text("HR")
                .font(DSTypography.caption)
                .tracking(0.5)
                .foregroundStyle(DSColors.foregroundDim)
            Text("—")
                .font(DSTypography.mono)
                .foregroundStyle(DSColors.foregroundDim)

            Spacer()

            if let rir = payload.targetRir {
                Text("RIR \(rir)")
                    .font(DSTypography.caption)
                    .tracking(0.5)
                    .foregroundStyle(DSColors.foregroundMuted)
            }
        }
    }
}

#if DEBUG
#Preview {
    ActiveSetFace(
        payload: WatchFacesViewModel.ActivePayload(
            exerciseName: "Bench Press",
            prescription: "5 × 102.5 kg",
            setNumber: 3,
            setCount: 5,
            targetRir: 2
        ),
        onTap: {}
    )
    .preferredColorScheme(.dark)
}
#endif
