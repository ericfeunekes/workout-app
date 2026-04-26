// IdleFace.swift
//
// Shown when no workout is active. Minimal by design — the watch only
// exists to support active workouts; in idle the face reminds the user
// the pairing is working and nothing else.
//
// Layout (per v1 scope in app/README.md § "Watch (v1 scope)"):
//   - center: "setmark · paired" in mono caption
//   - footer: HR placeholder ("—") until HealthKit on-watch lands in v1.1+
//
// The full design grammar (`docs/design/src/watch-hifi-v2.jsx`) is deferred.

import SwiftUI
import DesignSystem

struct IdleFace: View {
    var body: some View {
        VStack(spacing: DSSpacing.md) {
            Spacer()

            Text("setmark · paired")
                .font(DSTypography.caption)
                .tracking(0.5)
                .foregroundStyle(DSColors.foregroundMuted)

            Spacer()

            // HR footer placeholder. Stays "—" until HealthKit on-watch
            // ships; see v1.1+ deferral in app/README.md.
            HStack(spacing: DSSpacing.sm) {
                Text("HR")
                    .font(DSTypography.caption)
                    .tracking(0.5)
                    .foregroundStyle(DSColors.foregroundDim)
                Text("—")
                    .font(DSTypography.mono)
                    .foregroundStyle(DSColors.foregroundDim)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DSSpacing.md)
        .background(DSColors.background)
    }
}

#if DEBUG
#Preview {
    IdleFace()
        .preferredColorScheme(.dark)
}
#endif
