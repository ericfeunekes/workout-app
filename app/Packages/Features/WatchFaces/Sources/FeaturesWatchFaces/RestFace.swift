// RestFace.swift
//
// Shown when the phone is in `SessionState.route == .rest`. Big ring
// countdown (DSRing) + center mm:ss timer. Tap anywhere ends the set —
// fires `.setEnded(...)` back to the phone through WatchBridge.
//
// Remaining time is derived from `endsAt - now` via SwiftUI's
// `TimelineView`, which redraws on a 1-second schedule. This matches
// the iOS convention (SessionState.restEndsAt is absolute) and means
// the watch face survives a background→foreground transition without
// drift.
//
// Design grammar reference: `docs/design/src/watch-grammar.jsx` —
// simplified to a single widget (the ring) for v1. The elapsed/remaining
// split, alt-set pill, and HR sparkline are v1.1+.

import SwiftUI
import DesignSystem

struct RestFace: View {
    let payload: WatchFacesViewModel.RestPayload
    let onTap: () -> Void

    /// Total rest duration is unknown from the bridge payload alone —
    /// we only have `endsAt`. The ring's progress needs a start-time
    /// anchor, which we derive from the view's first render. Storing
    /// it in `@State` means the anchor survives re-renders inside the
    /// timeline but resets when the payload changes (watchOS creates a
    /// new `RestFace` when the payload differs).
    @State private var anchor: Date = .now

    var body: some View {
        Button(action: onTap) {
            TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                ZStack {
                    ring(now: timeline.date)

                    VStack(spacing: DSSpacing.xs) {
                        if !payload.exerciseName.isEmpty {
                            Text(payload.exerciseName.uppercased())
                                .font(DSTypography.caption)
                                .tracking(0.5)
                                .foregroundStyle(DSColors.foregroundDim)
                                .lineLimit(1)
                        }

                        Text(elapsedMMSS(now: timeline.date))
                            .font(DSTypography.monoLarge)
                            .monospacedDigit()
                            .foregroundStyle(DSColors.accentInk)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(DSSpacing.md)
                .contentShape(Rectangle()) // whole-face tap zone
                .background(DSColors.background)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            anchor = Date()
        }
    }

    // MARK: - Derivations

    private func ring(now: Date) -> some View {
        let total = max(payload.endsAt.timeIntervalSince(anchor), 1)
        let remaining = max(payload.endsAt.timeIntervalSince(now), 0)
        let progress = 1.0 - (remaining / total)
        return DSRing(progress: progress, lineWidth: 6)
    }

    /// "mm:ss" elapsed since `anchor`, consistent with the iOS rest
    /// screen's elapsed-since-rest-start convention.
    private func elapsedMMSS(now: Date) -> String {
        let elapsed = max(Int(now.timeIntervalSince(anchor)), 0)
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#if DEBUG
#Preview {
    RestFace(
        payload: WatchFacesViewModel.RestPayload(
            endsAt: Date().addingTimeInterval(90),
            exerciseName: "Bench Press"
        ),
        onTap: {}
    )
    .preferredColorScheme(.dark)
}
#endif
