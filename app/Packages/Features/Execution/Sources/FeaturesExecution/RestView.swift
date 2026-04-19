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
import CoreAutoreg
import DesignSystem
import WorkoutCoreFoundation

struct RestView: View {
    @Bindable var viewModel: ExecutionViewModel

    @State var activeSheet: RestSheet?

    // qa-028: End confirmation alert. Same affordance as ActiveView — tap
    // the inline nav-bar End control → alert → `viewModel.complete()` on
    // confirm. Alert copy matches across screens so the semantics are
    // identical regardless of which route the user is on.
    @State private var showEndConfirm = false

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

            VStack(spacing: 0) {
                navBar
                VStack(spacing: DSSpacing.xl) {
                    header
                    autoregBannerView
                    ringTile
                    // A standalone rest block (zero-item) has no
                    // "just logged" set — hide the pill row. The timer +
                    // next button are the whole UI for that variant.
                    if !isRestBlock {
                        justDidRow
                    }
                    Spacer()
                    nextButton
                }
                .padding(.horizontal, DSSpacing.xl)
                .padding(.top, DSSpacing.lg)
                .padding(.bottom, DSSpacing.xl)
            }
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
        // qa-028: End-workout confirmation. Same copy / semantics as
        // ActiveView's alert — ending mid-rest is equally destructive
        // (the just-logged set counts, but anything remaining in the
        // session is dropped), so surface the same "you can still save &
        // done" reassurance.
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

    /// qa-028: top-of-screen End control. Matches ActiveView's inline
    /// nav-bar pattern — single trailing ghost button, tap surfaces the
    /// confirmation alert. Docs spec describes the End button on both
    /// Active and Rest (`execute-loop.md` S13 + `save-and-done.md` S2).
    private var navBar: some View {
        HStack {
            Spacer()
            Button {
                showEndConfirm = true
            } label: {
                Text("end")
                    .font(DSTypography.subLabel)
                    .tracking(0.5)
                    .foregroundStyle(DSColors.foregroundMuted)
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.sm)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("execution.rest.end")
            .accessibilityLabel("End workout")
        }
        .padding(.horizontal, DSSpacing.xl)
        .padding(.top, DSSpacing.md)
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
                // qa-026: hide the load pill entirely when the just-logged
                // set was bodyweight (`loadKg == nil`). The previous
                // behaviour rendered an editable "BW" pill whose tap
                // opened a numpad at 0 and, on save, wrote a non-nil
                // loadKg — silently corrupting the BW contract. A user
                // has no reason to edit a load that doesn't exist, so
                // the pill is dropped from the row. DSPill uses
                // `.frame(maxWidth: .infinity)`, so the reps + RIR
                // pills grow to fill the row — no spacer needed.
                // R2.10 unit-thread: load caption follows the SetPlan's
                // unit so an lb-prescribed workout reads "LB" here, not
                // the hardcoded "KG" that leaked through before this fix.
                if RestView.shouldRenderLoadPill(for: set) {
                    DSPill(
                        value: set.flatMap { plan in
                            plan.loadKg.map { formatKilograms($0) } ?? "BW"
                        } ?? "—",
                        caption: RestView.loadPillCaption(for: set),
                        isEditable: set != nil,
                        onTap: set == nil ? nil : { activeSheet = .load }
                    )
                }
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

    // MARK: - Pure helpers (exposed for tests)

    /// Gate for rendering the load pill on the "just logged" row.
    ///
    /// qa-026: when the just-logged set is bodyweight (`loadKg == nil`),
    /// the load pill is hidden outright. The load sheet's numpad is
    /// destructive for that row — saving any value converts the BW
    /// entry to a non-nil loadKg and corrupts the bodyweight contract.
    /// The user can still correct reps / RIR on a BW log (those pills
    /// remain editable); they just can't edit a load that doesn't
    /// exist. Returns `true` when no set is logged yet (the dash-state
    /// pill renders `—` with a cosmetic caption — not a BW log).
    /// Exposed as a pure static so unit tests can pin the contract
    /// without constructing a SwiftUI view.
    static func shouldRenderLoadPill(for set: SetPlan?) -> Bool {
        guard let set else { return true }
        return set.loadKg != nil
    }

    /// Caption for the load pill on the "just logged" row. Returns the
    /// SetPlan's unit in uppercase ("KG", "LB"); falls back to "KG" when
    /// no set is logged yet (the pill shows "—" in that state, so the
    /// caption is cosmetic). Returns `nil` when the logged set is
    /// loadless (`SetPlan.loadKg == nil`, i.e. bodyweight) so the pill
    /// value "BW" is not stacked over a misleading "KG" / "LB" caption
    /// (qa-007). The bodyweight contract from bug-053 is explicit:
    /// `loadKg == nil` renders as "BW" with no unit, distinct from a
    /// genuine 0 which renders as "0 KG" / "0 LB". Exposed as a static
    /// so unit tests can pin the R2.10 unit-thread + loadless contracts
    /// without building a SwiftUI view.
    static func loadPillCaption(for set: SetPlan?) -> String? {
        guard let set else {
            return "KG"
        }
        if set.loadKg == nil {
            return nil
        }
        return set.unit.rawValue.uppercased()
    }

    /// Unit string for the autoreg banner's DSWeightLabel. The proposal
    /// has no unit field — we inherit from the SetPlan it targets (the
    /// just-logged set on the same item). Exposed for tests so the
    /// inheritance contract stays locked; the banner callsite passes
    /// `viewModel.lastLoggedSet?.unit` directly.
    static func proposalBannerUnit(for set: SetPlan?) -> String {
        set?.unit.rawValue ?? "kg"
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
