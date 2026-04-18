// RestView.swift
//
// The rest screen. Mirrors `docs/design/components/rest-swap-complete-v2.jsx`
// and `docs/design/src/hifi.jsx` Rest:
//   - DSRing countdown with the configured rest duration
//   - "just did" row of three DSPills: load, reps, RIR (each tap-editable)
//   - Autoreg banner (when viewModel.currentProposal != nil) with Undo
//   - Primary "next" button advances the session
//
// The countdown ticks via a SwiftUI `TimelineView(.periodic)` — no timer
// state, no invalidation logic, just "what's the time now?" read from a
// `Date()` per tick and compared against `state.restEndsAt`.
//
// Per-section rendering is split across `RestView+Banner.swift` (autoreg
// banner) and `RestView+Sheets.swift` (past-set edit sheets) so the main
// struct stays under SwiftLint's `type_body_length` cap.

import SwiftUI
import Combine
import DesignSystem
import WorkoutCoreFoundation

struct RestView: View {
    @Bindable var viewModel: ExecutionViewModel

    @State var activeSheet: RestSheet?

    // Time-cap tick source (bug-042). Block caps on time-capped modes
    // (AMRAP / ForTime / EMOM / Tabata) can elapse WHILE the user is
    // resting — e.g., an EMOM's total_minutes expires during the rest
    // between intervals, or a For-Time cap hits while the user is
    // still resting. The Active view's tick goes silent on route change
    // to `.rest`, so the rest screen carries its own tick. Same cadence
    // (1s) and same gate (`blockEndsAt != nil`) as Active.
    private let tickTimer = Timer.publish(every: 1, on: .main, in: .common)
        .autoconnect()

    enum RestSheet: Identifiable {
        case load
        case reps
        case rir
        var id: String {
            switch self {
            case .load: return "load"
            case .reps: return "reps"
            case .rir: return "rir"
            }
        }
    }

    var body: some View {
        ZStack {
            DSColors.background.ignoresSafeArea()

            VStack(spacing: DSSpacing.xl) {
                header
                autoregBannerView
                ringTile
                // A standalone rest block (zero-item) has no "just logged"
                // set — hide the pill row. The timer + next button are the
                // whole UI for that variant.
                if !isRestBlock {
                    justDidRow
                }
                Spacer()
                nextButton
            }
            .padding(.horizontal, DSSpacing.xl)
            .padding(.top, DSSpacing.xl)
            .padding(.bottom, DSSpacing.xl)
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        // Bug-042: keep block-cap ticking during rest. Guard on
        // `blockEndsAt != nil` so non-time-capped rest periods
        // (straight_sets between-sets rest) don't wake the VM each second.
        .onReceive(tickTimer) { _ in
            if viewModel.state.blockEndsAt != nil {
                viewModel.tickBlockTimer()
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("rest")
                .font(DSTypography.title)
                .foregroundStyle(DSColors.foreground)
            if isRestBlock {
                // Standalone rest block — label it so the user knows this
                // is between blocks, not between sets. Bumped to
                // `subtitle` (14pt) for parity with Active's meta line
                // (bug-022).
                Text("BETWEEN BLOCKS")
                    .font(DSTypography.subtitle)
                    .tracking(0.5)
                    .foregroundStyle(DSColors.foregroundMuted)
            } else if let name = viewModel.activeContent?.exerciseName {
                Text(name.uppercased())
                    .font(DSTypography.subtitle)
                    .tracking(0.5)
                    .foregroundStyle(DSColors.foregroundMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// True when the current cursor sits on a zero-item block (a standalone
    /// `rest` block). Used to hide the "just logged" pill row and relabel
    /// the header.
    private var isRestBlock: Bool {
        let b = viewModel.state.cursor.blockIndex
        guard b < viewModel.state.structure.itemsPerBlock.count else {
            return false
        }
        return viewModel.state.structure.itemsPerBlock[b] == 0
    }

    private var ringTile: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { tl in
            let now = tl.date
            let progress = restProgress(now: now)
            let remaining = max(0, (viewModel.state.restEndsAt?.timeIntervalSince(now)) ?? 0)
            ZStack {
                DSRing(progress: progress, lineWidth: 8)
                    .frame(width: 200, height: 200)
                VStack(spacing: DSSpacing.xs) {
                    Text(formatDuration(seconds: remaining))
                        .font(.system(size: 44, weight: .light, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(DSColors.accentInk)
                    Text("REST")
                        .font(DSTypography.caption)
                        .tracking(1.5)
                        .foregroundStyle(DSColors.foregroundDim)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var justDidRow: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            // Group label moved to `DSTypography.subLabel` (12pt medium
            // mono) so it reads in gym lighting (bug-021). The per-pill
            // KG / REPS / RIR captions use the same token via `DSPill`.
            Text("JUST LOGGED")
                .font(DSTypography.subLabel)
                .tracking(1.2)
                .foregroundStyle(DSColors.foregroundDim)

            HStack(spacing: DSSpacing.md) {
                let set = viewModel.lastLoggedSet
                DSPill(
                    value: set.map { formatKilograms($0.loadKg) } ?? "—",
                    caption: "KG",
                    isEditable: set != nil,
                    onTap: set == nil ? nil : { activeSheet = .load }
                )
                DSPill(
                    value: set.map { String($0.reps) } ?? "—",
                    caption: "REPS",
                    isEditable: set != nil,
                    onTap: set == nil ? nil : { activeSheet = .reps }
                )
                DSPill(
                    value: set.flatMap { $0.rir.map(String.init) } ?? "—",
                    caption: "RIR",
                    isEditable: set != nil,
                    onTap: set == nil ? nil : { activeSheet = .rir }
                )
            }
        }
    }

    private var nextButton: some View {
        DSButton(
            title: "next",
            style: .primary,
            action: { viewModel.advance() }
        )
    }

    // MARK: - Timer math

    private func restProgress(now: Date) -> Double {
        let total = viewModel.restDurationSeconds
        guard total > 0, let endsAt = viewModel.state.restEndsAt else { return 0 }
        let remaining = max(0, endsAt.timeIntervalSince(now))
        let elapsed = total - remaining
        return min(max(elapsed / total, 0), 1)
    }
}
