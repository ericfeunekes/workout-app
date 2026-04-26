// ActiveView.swift
//
// The active-set screen. Mirrors `docs/design/src/hifi.jsx` function
// `Active` (lines 306-441):
//   - nav bar: Back → Today · title "NN of M" · End
//   - exercise name + meta (set N of M · rest mm:ss)
//   - progress pips for the sets in this item
//   - hero prescription block: big load (mono) / unit / "N reps"
//   - "LAST TIME" chip at the bottom (when history present)
//   - primary mode-aware log button pinned at the bottom
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

    // `internal` so the log-button helper in `ActiveView+LogButton.swift`
    // can toggle the binding on the strength path (tapping the primary
    // log button opens this sheet).
    @State var showLogSheet = false
    // `internal` so the swap-sheet helpers in `ActiveView+Swap.swift`
    // can toggle the binding.
    @State var showSwapSheet = false
    @State var showMetconResultSheet = false
    @State private var showNextUpSheet = false

    // qa-028: End confirmation alert. Tapping the nav-bar End button
    // surfaces the alert instead of firing `complete()` directly so a
    // stray tap mid-workout doesn't silently skip remaining sets.
    @State private var showEndConfirm = false
    @State private var timerNow = Date()

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
                    navBar
                    ScrollView {
                        VStack(alignment: .leading, spacing: DSSpacing.xl) {
                            header(content: content)
                            if let progress = activeBlockProgress {
                                blockProgressStrip(progress)
                            }
                            if let timer = viewModel.timerPresentation(now: timerNow) {
                                timerHero(timer)
                            }
                            if content.totalSets > 0 {
                                progressPips(content: content)
                            }
                            heroBlock(content: content)
                            if let lastTime = content.lastTime {
                                lastTimeChip(lastTime)
                            }
                            if let nextUp = viewModel.nextUpPresentation {
                                nextUpCard(nextUp)
                            }
                        }
                        .padding(.horizontal, DSSpacing.xl)
                        .padding(.top, DSSpacing.lg)
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
            timerNow = Date()
            if ActiveView.shouldPresentAMRAPResultSheet(
                timingMode: currentTimingMode,
                blockEndsAt: viewModel.state.blockEndsAt,
                now: timerNow,
                isMetconResultSheetPresented: showMetconResultSheet
            ) {
                showMetconResultSheet = true
                return
            }
            if ActiveView.shouldTickBlockTimer(
                blockEndsAt: viewModel.state.blockEndsAt,
                workEndsAt: viewModel.state.workEndsAt,
                isMetconResultSheetPresented: showMetconResultSheet
            ) {
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
            //
            // Sheet is strength-only — cardio blocks never present it
            // (they dispatch `logCurrentSet` directly from the button
            // tap). So the sheet's commit fires the strength-specific
            // `logSet(reps:rir:)` rather than the mode-branching
            // `logCurrentSet(...)`.
            if let content = viewModel.activeContent {
                LogSetSheet(
                    title: logSheetTitle(content: content),
                    initialLoad: viewModel.activeSetPlan?.loadKg,
                    loadUnit: viewModel.activeSetPlan?.unit.rawValue,
                    initialReps: content.reps,
                    onCommit: { loadKg, reps, rir in
                        showLogSheet = false
                        viewModel.logSet(loadKg: loadKg, reps: reps, rir: rir)
                    }
                )
            }
        }
        .sheet(isPresented: $showSwapSheet) {
            swapSheet
        }
        .sheet(isPresented: $showMetconResultSheet) {
            MetconResultSheet(
                timingMode: currentTimingMode,
                elapsed: currentWorkElapsedSeconds,
                amrapItems: viewModel.amrapPartialResultItems(),
                onAMRAPCommit: { extraReps in
                    showMetconResultSheet = false
                    viewModel.logAMRAPPartialResult(extraReps: extraReps)
                },
                onForTimeCommit: {
                    showMetconResultSheet = false
                    viewModel.logForTimeResult()
                }
            )
        }
        .sheet(isPresented: $showNextUpSheet) {
            if let nextUp = viewModel.nextUpPresentation {
                NextUpSheet(
                    nextUp: nextUp,
                    workQueue: viewModel.executionProjection(now: Date()).workQueue
                )
            }
        }
        // qa-028: confirm before force-completing. Ending mid-workout is
        // destructive (unlogged sets vanish), so a stray tap or sweaty
        // finger mis-press shouldn't skip the rest of the session without
        // a beat of intent. Confirm → `viewModel.complete()` flips the
        // route to `.complete`; user can still Save & Done from there.
        .alert("End workout?", isPresented: $showEndConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("End", role: .destructive) {
                viewModel.complete()
            }
        } message: {
            Text("Unlogged sets won't be recorded. You can still save & done.")
        }
    }

    // MARK: - Nav bar

    /// qa-028: top-of-screen End control. No `NavigationStack` wraps
    /// `ExecutionView`, so we render the nav bar inline — a single trailing
    /// ghost button matching the `docs/design/src/hifi.jsx` § Active hint
    /// ("nav bar: Back → Today · title · End"). Tap surfaces the alert in
    /// `showEndConfirm` rather than firing `complete()` directly.
    private var navBar: some View {
        HStack {
            Spacer()
            Button {
                if currentTimingMode == .amrap {
                    showMetconResultSheet = true
                } else {
                    showEndConfirm = true
                }
            } label: {
                Text("end")
                    .font(DSTypography.subLabel)
                    .tracking(0.5)
                    .foregroundStyle(DSColors.foregroundMuted)
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.sm)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("execution.active.end")
            .accessibilityLabel("End workout")
        }
        .padding(.horizontal, DSSpacing.xl)
        .padding(.top, DSSpacing.md)
    }

    // MARK: - Sections

    private func header(content: ActiveContent) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(content.exerciseName)
                .font(DSTypography.title)
                .foregroundStyle(DSColors.foreground)
            // Meta line stays structural; the running timer has its own
            // primary hero below so the two don't compete or duplicate.
            Text(metaLine(content: content))
                .font(DSTypography.subtitle)
                .foregroundStyle(DSColors.foregroundMuted)
            Text("hold exercise to swap")
                .font(DSTypography.caption)
                .tracking(0.4)
                .foregroundStyle(DSColors.foregroundDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.4) {
            openSwapSheet()
        }
        .accessibilityHint("Long press to open exercise alternatives")
    }

    /// Active-screen meta line. Contract for unbounded time-capped modes
    /// (AMRAP — driver passes `totalSets == 0`): render "ROUND N"
    /// with no denominator. Other modes use the user's workout vocabulary
    /// where the cursor represents intervals or rounds rather than a
    /// strength set.
    /// Fixes bug-037 — prior code dereferenced `totalSets = 999` into
    /// a visible denominator and rendered 999 progress dots off-screen.
    private func metaLine(content: ActiveContent) -> String {
        ActiveView.formattedMetaLine(
            content: content,
            timingMode: currentTimingMode
        )
    }

    /// Pure-swift helper exposed for unit tests. Mirrors the bug-037
    /// contract for unbounded modes while allowing bounded modes to use
    /// mode-native language.
    static func formattedMetaLine(
        content: ActiveContent,
        timingMode: TimingMode = .straightSets
    ) -> String {
        switch timingMode {
        case .straightSets:
            guard content.totalSets > 0 else { return "ROUND \(content.setIndex)" }
            return "SET \(content.setIndex) OF \(content.totalSets)"
        case .emom, .intervals:
            guard content.totalSets > 0 else { return "INTERVAL \(content.setIndex)" }
            return "INTERVAL \(content.setIndex) OF \(content.totalSets)"
        case .superset, .circuit, .forTime, .tabata:
            guard content.totalSets > 0 else { return "ROUND \(content.setIndex)" }
            return "ROUND \(content.setIndex) OF \(content.totalSets)"
        case .continuous:
            return "CONTINUOUS"
        case .accumulate:
            return "ACCUMULATE"
        case .amrap:
            return "ROUND \(content.setIndex)"
        case .custom:
            guard content.totalSets > 0 else { return "SEGMENT \(content.setIndex)" }
            return "SEGMENT \(content.setIndex) OF \(content.totalSets)"
        case .rest:
            return "REST"
        }
    }

    func logSheetTitle(content: ActiveContent) -> String {
        let bi = viewModel.state.cursor.blockIndex
        switch viewModel.context.block(at: bi)?.timingMode {
        case .accumulate:
            return "log chunk"
        case .emom:
            return "log interval \(content.setIndex)"
        case .forTime, .tabata:
            return "log round \(content.setIndex)"
        case .custom:
            return "log segment \(content.setIndex)"
        case .superset, .circuit, .amrap:
            return "log station"
        case .straightSets, .rest, .intervals, .continuous, nil:
            return "log set"
        }
    }

    static func shouldTickBlockTimer(
        blockEndsAt: Date?,
        workEndsAt: Date?,
        isMetconResultSheetPresented: Bool
    ) -> Bool {
        guard !isMetconResultSheetPresented else { return false }
        return blockEndsAt != nil || workEndsAt != nil
    }

    static func shouldPresentAMRAPResultSheet(
        timingMode: TimingMode,
        blockEndsAt: Date?,
        now: Date,
        isMetconResultSheetPresented: Bool
    ) -> Bool {
        guard timingMode == .amrap,
              !isMetconResultSheetPresented,
              let blockEndsAt else { return false }
        return now >= blockEndsAt
    }

    private var currentTimingMode: TimingMode {
        let bi = viewModel.state.cursor.blockIndex
        return viewModel.context.block(at: bi)?.timingMode ?? .straightSets
    }

    private var currentWorkElapsedSeconds: TimeInterval {
        guard let startedAt = viewModel.state.workStartedAt else { return 0 }
        return max(0, Date().timeIntervalSince(startedAt))
    }

    private var activeBlockProgress: BlockProgressPresentation? {
        let progress = viewModel.executionProjection(now: timerNow).blockProgress
        guard ActiveView.shouldRenderBlockProgress(progress) else { return nil }
        return progress
    }

    private func blockProgressStrip(_ progress: BlockProgressPresentation) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("BLOCK \(progress.blockIndex + 1) / \(progress.blockCount)")
                .font(DSTypography.subLabel)
                .tracking(1.2)
                .foregroundStyle(DSColors.foregroundDim)
            Spacer()
            Text(ActiveView.blockProgressSummary(progress))
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.foregroundDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Block \(progress.blockIndex + 1) of \(progress.blockCount), "
            + "\(progress.completedSets) of \(progress.totalSets) done"
        )
    }

    private func timerHero(_ timer: ExecutionTimerPresentation) -> some View {
        VStack(spacing: DSSpacing.xs) {
            Text(timer.label)
                .font(DSTypography.subLabel)
                .tracking(1.4)
                .foregroundStyle(DSColors.foregroundMuted)
            Text(timer.formattedValue)
                .font(.system(size: 56, weight: .light, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(DSColors.accentInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.xl)
        .background(DSColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityIdentifier("execution.active.primaryTimer")
    }

    /// Pure-swift helper for the bug-037 progress-dot contract: dots
    /// render iff `totalSets > 0`. The view's `if` gate calls this
    /// implicitly; exposing it keeps the contract unit-testable
    /// without SwiftUI snapshotting.
    static func shouldRenderProgressPips(content: ActiveContent) -> Bool {
        content.totalSets > 0
    }

    static func shouldRenderBlockProgress(_ progress: BlockProgressPresentation?) -> Bool {
        guard let progress else { return false }
        return progress.totalSets > 0
    }

    static func blockProgressSummary(_ progress: BlockProgressPresentation) -> String {
        "\(max(0, progress.completedSets)) / \(max(0, progress.totalSets)) DONE"
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
                heroPrimary(content: content)
                if let glyph = adjustGlyph(content.adjustGlyph) {
                    Text(glyph)
                        .font(DSTypography.monoLarge)
                        .foregroundStyle(DSColors.accent)
                        .baselineOffset(18)
                }
            }
            Text(heroSecondary(content: content))
                .font(DSTypography.monoLarge)
                .foregroundStyle(DSColors.foregroundMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.xxl)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.4) {
            openSwapSheet()
        }
        .accessibilityHint("Long press to open exercise alternatives")
    }

    private func nextUpCard(_ nextUp: ExecutionNextUpPresentation) -> some View {
        Button {
            showNextUpSheet = true
        } label: {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(nextUp.label.uppercased())
                        .font(DSTypography.subLabel)
                        .tracking(1.2)
                        .foregroundStyle(DSColors.foregroundDim)
                    Spacer()
                    Text("tap to preview")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.foregroundDim)
                }
                Text(nextUp.title)
                    .font(DSTypography.subtitle)
                    .foregroundStyle(DSColors.foreground)
                if let detail = nextUp.detail {
                    Text(detail)
                        .font(DSTypography.mono)
                        .foregroundStyle(DSColors.foregroundMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.md)
            .background(DSColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("execution.active.nextUp")
        .accessibilityHint("Tap to preview what is coming next")
    }

    /// Hero primary face. Strength shows `loadDisplay` (which may split
    /// into DSWeightLabel mono pairing). Cardio shows `repsDisplay`
    /// (the primary target — "45 min" / "400 m") as the big face —
    /// qa-043: pre-fix the view rendered "45 min reps" / "400 m reps"
    /// by feeding `repsDisplay` into the "N reps" template; this branch
    /// promotes the cardio primary to the hero face instead.
    @ViewBuilder
    private func heroPrimary(content: ActiveContent) -> some View {
        switch content.kind {
        case .strength:
            heroLoad(content.loadDisplay)
        case .cardio:
            Text(content.repsDisplay)
                .font(.system(size: 64, weight: .light, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(DSColors.accentInk)
        }
    }

    /// Hero secondary face. Strength shows "N reps"; cardio shows
    /// `loadDisplay` (pace / zone / dash) verbatim — no " reps"
    /// suffix since a continuous effort or interval doesn't have reps.
    private func heroSecondary(content: ActiveContent) -> String {
        switch content.kind {
        case .strength:
            return viewModel.currentCompositeRepsDisplay ?? "\(content.repsDisplay) reps"
        case .cardio:
            return content.loadDisplay
        }
    }

    /// Render the hero load face. `loadDisplay` from the driver is a
    /// pre-formatted string — "102.5 kg", "225 lb", "BW", or a pace
    /// token ("4:30 / km") for cardio modes. We split off any known
    /// unit suffix so the unit renders in the same mono family +
    /// weight as the number (bug-027 — the prior single-Text
    /// `"102.5 kg"` let "kg" drift into the default sans face on
    /// some devices). Non-weight displays (BW, pace, dash) render
    /// plain. R2.10 unit-thread: scan `LoadUnit.allCases` instead
    /// of hardcoding `" kg"` so lb-prescribed workouts also get the
    /// DSWeightLabel mono pairing.
    @ViewBuilder
    private func heroLoad(_ display: String) -> some View {
        if let (number, unit) = splitWeightDisplay(display) {
            DSWeightLabel(
                number: number,
                unit: unit,
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

    /// Pull a `(number, unit)` pair off the end of a pre-formatted
    /// load string when it ends in a known `LoadUnit` suffix. Returns
    /// nil for "BW", pace tokens, and anything else that doesn't
    /// terminate in a unit — those render as plain mono text.
    private func splitWeightDisplay(_ display: String) -> (String, String)? {
        for unit in LoadUnit.allCases {
            let suffix = " \(unit.rawValue)"
            if display.hasSuffix(suffix) {
                let number = String(display.dropLast(suffix.count))
                return (number, unit.rawValue)
            }
        }
        return nil
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

    // `logButton` + cardio-branch title helper live in
    // `ActiveView+LogButton.swift` to keep the struct body under
    // SwiftLint's `type_body_length` cap.
}
