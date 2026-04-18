// ActiveView.swift
//
// The active-set screen. Mirrors `docs/design/src/hifi.jsx` function
// `Active` (lines 306-441):
//   - nav bar: Back → Today · title "NN of M" · End
//   - exercise name + meta (set N of M · rest mm:ss)
//   - progress pips for the sets in this item
//   - hero prescription block: big load (mono) / unit / "N reps"
//   - "LAST TIME" chip at the bottom (when history present)
//   - primary "log set N" pinned at the bottom
//
// Dark-only. All color / type / spacing tokens come from DesignSystem.

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import Combine
import CoreAutoreg
import CoreDomain
import DesignSystem
import WorkoutCoreFoundation

struct ActiveView: View {
    @Bindable var viewModel: ExecutionViewModel

    @State private var showLogSheet = false
    // `internal` so the swap-sheet helpers in `ActiveView+Swap.swift`
    // can toggle the binding. The rest stay file-private.
    @State var showSwapSheet = false

    // Time-cap tick source (bug-042). `TimelineView` is a render-time
    // construct; we need the tick to fire `viewModel.tickBlockTimer()` as
    // a side effect, so we drive it via a `Timer.publish` + `.onReceive`
    // instead. One-second cadence matches the cap resolution (AMRAP /
    // ForTime caps are in whole seconds; Tabata's 20s work window is too).
    // `autoconnect()` handles start/stop with view lifecycle.
    private let tickTimer = Timer.publish(every: 1, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        ZStack {
            DSColors.background.ignoresSafeArea()

            if let content = viewModel.activeContent {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: DSSpacing.xl) {
                            header(content: content)
                            if content.totalSets > 0 {
                                progressPips(content: content)
                            }
                            heroBlock(content: content)
                            if let lastTime = content.lastTime {
                                lastTimeChip(lastTime)
                            }
                        }
                        .padding(.horizontal, DSSpacing.xl)
                        .padding(.top, DSSpacing.xxl)
                        // The whole card is the long-press zone so a sweaty
                        // finger landing anywhere near the exercise name or
                        // hero value triggers the swap menu. See
                        // `app/README.md` § "Swap" — long-press opens the
                        // swap / adjust affordances.
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.4) {
                            openSwapSheet()
                        }
                    }

                    logButton(content: content)
                        .padding(.horizontal, DSSpacing.xl)
                        .padding(.top, DSSpacing.lg)
                        .padding(.bottom, DSSpacing.xl)
                }
            } else {
                // Defensive empty state — reach here only with a broken
                // cursor, which shouldn't happen in normal flow.
                Text("no active set")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.foregroundMuted)
            }
        }
        // Bug-042: time-capped modes (AMRAP / ForTime / EMOM / Tabata)
        // need a runtime tick so the VM's `blockEndsAt` / `workEndsAt`
        // gates flip the route to `.complete` (or auto-log + rest, for
        // Tabata). Gate on `blockEndsAt != nil` so straight_sets /
        // superset / circuit / rest blocks don't pay the tick cost —
        // `tickBlockTimer()` is a no-op in that case anyway, but skipping
        // the call avoids waking the view model on every interval for
        // blocks that can't possibly auto-complete.
        .onReceive(tickTimer) { _ in
            if viewModel.state.blockEndsAt != nil {
                viewModel.tickBlockTimer()
            }
        }
        .sheet(isPresented: $showLogSheet) {
            // Combined reps + RIR entry — single sheet, one commit
            // (bug-023 fix). Prescribed reps pre-fill the numpad; RIR
            // is untouched = nil on commit, matching the prior "skip"
            // semantics. The NumPad + Rir individual sheets still ship
            // for past-set edits on the Rest screen where only one
            // field changes at a time.
            if let content = viewModel.activeContent {
                LogSetSheet(
                    initialReps: content.reps,
                    onCommit: { reps, rir in
                        showLogSheet = false
                        viewModel.logSet(reps: reps, rir: rir)
                    }
                )
            }
        }
        .sheet(isPresented: $showSwapSheet) {
            swapSheet
        }
    }

    // MARK: - Sections

    private func header(content: ActiveContent) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(content.exerciseName)
                .font(DSTypography.title)
                .foregroundStyle(DSColors.foreground)
            // Meta line moved from `caption` (11pt) to `subtitle` (14pt
            // semibold) — set counter + rest duration are the most
            // action-critical info on this screen for a user
            // glancing mid-lift (bug-022). The hero load stays the
            // visual anchor at 64pt, so this still reads as sub-
            // header, not title; the bump just makes it legible at
            // arm's length.
            Text(metaLine(content: content))
                .font(DSTypography.subtitle)
                .foregroundStyle(DSColors.foregroundMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Active-screen meta line. Contract for unbounded time-capped modes
    /// (AMRAP — driver passes `totalSets == 0`): render "ROUND N · REST
    /// mm:ss" with no denominator. Bounded modes (StraightSets / Circuit
    /// / Tabata / ForTime / EMOM / etc.) keep the "SET N OF M" shape.
    /// Fixes bug-037 — prior code dereferenced `totalSets = 999` into
    /// a visible denominator and rendered 999 progress dots off-screen.
    private func metaLine(content: ActiveContent) -> String {
        ActiveView.formattedMetaLine(
            content: content,
            restSeconds: viewModel.restDurationSeconds
        )
    }

    /// Pure-swift helper exposed for unit tests. Mirrors the bug-037
    /// contract: `totalSets > 0` → "SET n OF m · REST …"; `totalSets
    /// <= 0` → "ROUND n · REST …" (unbounded rounds).
    static func formattedMetaLine(
        content: ActiveContent,
        restSeconds: Double
    ) -> String {
        let rest = formatDuration(seconds: restSeconds)
        if content.totalSets > 0 {
            return "SET \(content.setIndex) OF \(content.totalSets) · REST \(rest)"
        }
        return "ROUND \(content.setIndex) · REST \(rest)"
    }

    /// Pure-swift helper for the bug-037 progress-dot contract: dots
    /// render iff `totalSets > 0`. The view's `if` gate calls this
    /// implicitly; exposing it keeps the contract unit-testable
    /// without SwiftUI snapshotting.
    static func shouldRenderProgressPips(content: ActiveContent) -> Bool {
        content.totalSets > 0
    }

    private func progressPips(content: ActiveContent) -> some View {
        HStack(spacing: DSSpacing.sm) {
            ForEach(1...max(content.totalSets, 1), id: \.self) { idx in
                Circle()
                    .fill(pipFill(for: idx, content: content))
                    .frame(width: 8, height: 8)
            }
            Spacer()
        }
    }

    private func pipFill(for setIndex: Int, content: ActiveContent) -> Color {
        if setIndex < content.setIndex { return DSColors.foregroundMuted }
        if setIndex == content.setIndex { return DSColors.accent }
        return DSColors.foregroundFaint
    }

    private func heroBlock(content: ActiveContent) -> some View {
        VStack(spacing: DSSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.md) {
                heroLoad(content.loadDisplay)
                if let glyph = adjustGlyph(content.adjustGlyph) {
                    Text(glyph)
                        .font(DSTypography.monoLarge)
                        .foregroundStyle(DSColors.accent)
                        .baselineOffset(18)
                }
            }
            Text("\(content.repsDisplay) reps")
                .font(DSTypography.monoLarge)
                .foregroundStyle(DSColors.foregroundMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.xxl)
    }

    /// Render the hero load face. `loadDisplay` from the driver is a
    /// pre-formatted string — "102.5 kg", "BW", or a pace token
    /// ("4:30 / km") for cardio modes. We split off the " kg" suffix
    /// so the unit renders in the same mono family + weight as the
    /// number (bug-027 — the prior single-Text `"102.5 kg"` let "kg"
    /// drift into the default sans face on some devices). Non-kg
    /// displays (BW, pace, dash) render plain.
    @ViewBuilder
    private func heroLoad(_ display: String) -> some View {
        if display.hasSuffix(" kg") {
            let number = String(display.dropLast(3))
            DSWeightLabel(
                number: number,
                unit: "kg",
                size: 64,
                weight: .light,
                color: DSColors.accentInk
            )
        } else {
            Text(display)
                .font(.system(size: 64, weight: .light, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(DSColors.accentInk)
        }
    }

    private func adjustGlyph(_ adjust: SetPlan.Adjust?) -> String? {
        switch adjust {
        case .up: return "↑"
        case .down: return "↓"
        case .manual: return "✎"
        case nil: return nil
        }
    }

    private func lastTimeChip(_ value: String) -> some View {
        HStack(spacing: DSSpacing.md) {
            Text("LAST TIME")
                .font(DSTypography.caption)
                .tracking(0.5)
                .foregroundStyle(DSColors.foregroundDim)
            Text(value)
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.foregroundMuted)
            Spacer()
        }
    }

    private func logButton(content: ActiveContent) -> some View {
        DSButton(
            title: "log set \(content.setIndex)",
            style: .primary,
            action: { showLogSheet = true }
        )
    }

}
