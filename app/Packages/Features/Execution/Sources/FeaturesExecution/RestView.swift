// RestView.swift
//
// The rest screen. Mirrors `docs/design/components/rest-swap-complete-v2.jsx`
// and `docs/design/src/hifi.jsx` Rest:
//   - DSRing countdown with the configured rest duration
//   - strength "just did" row of DSPills: load, reps, RIR (each tap-editable)
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
import CoreDomain
import CoreSession
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

    private enum RestProgressDotState {
        case performed
        case skipped
        case pending
    }

    private struct RestProgressDot: Identifiable {
        let id: String
        let state: RestProgressDotState
        let accessibilityLabel: String
    }

    struct RestProgressOrderEntry: Equatable {
        let itemID: UUID
        let setIndex: Int
    }

    private struct RestBlockProgress {
        let blockIndex: Int
        let blockCount: Int
        let completed: Int
        let total: Int
        let dots: [RestProgressDot]
    }

    // Time-cap tick source (bug-042). Block caps on time-capped modes
    // (AMRAP / ForTime / EMOM / Tabata) can elapse WHILE the user is
    // resting — e.g., an EMOM's total_minutes expires during the rest
    // between intervals, or a For-Time cap hits while the user is
    // still resting. The Active view's tick goes silent on route change
    // to `.rest`, so the rest screen carries its own tick. Same cadence
    // (1s) and same gate (`blockEndsAt != nil || workEndsAt != nil`) as Active.
    private let tickTimer = Timer.publish(every: 1, on: .main, in: .common)
        .autoconnect()

    enum RestSheet: Identifiable {
        case load
        case reps
        case rir
        case batchLoad(itemID: UUID, setIndex: Int)
        case batchReps(itemID: UUID, setIndex: Int)
        case batchRir(itemID: UUID, setIndex: Int)
        case nextUp
        var id: String {
            switch self {
            case .load: return "load"
            case .reps: return "reps"
            case .rir: return "rir"
            case .batchLoad(let itemID, let setIndex):
                return "batchLoad-\(itemID.uuidString)-\(setIndex)"
            case .batchReps(let itemID, let setIndex):
                return "batchReps-\(itemID.uuidString)-\(setIndex)"
            case .batchRir(let itemID, let setIndex):
                return "batchRir-\(itemID.uuidString)-\(setIndex)"
            case .nextUp: return "nextUp"
            }
        }
    }

    var body: some View {
        ZStack {
            DSColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                navBar
                ScrollView {
                    VStack(spacing: DSSpacing.xl) {
                        header
                        autoregBannerView
                        if !viewModel.isFinalRoundRobinBatchRoundRest {
                            ringTile
                        }
                        if let progress = restBlockProgress {
                            progressGrid(progress)
                        }
                        // Standalone rest blocks have no just-logged set.
                        // Cardio intervals log duration/distance, not
                        // reps/RIR, so the strength correction pills would
                        // render misleading "0 reps" data here.
                        if viewModel.isRoundRobinBatchRoundRest {
                            roundRobinBatchRows
                        } else if shouldShowStrengthJustDidRow {
                            justDidRow
                        }
                        if let nextUp = viewModel.nextUpPresentation {
                            nextUpCard(nextUp)
                        }
                    }
                    .padding(.horizontal, DSSpacing.xl)
                    .padding(.top, DSSpacing.lg)
                    .padding(.bottom, DSSpacing.xxl)
                }
                nextButton
                    .padding(.horizontal, DSSpacing.xl)
                    .padding(.top, DSSpacing.lg)
                    .padding(.bottom, DSSpacing.xl)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        // Bug-042: keep block-cap ticking during rest. Guard on
        // `blockEndsAt != nil || workEndsAt != nil` covers capped work
        // that can expire during rest; `currentRestShouldAutoAdvance`
        // covers clock-owned rest/transition slots such as intervals and
        // Tabata. Strength recovery stays manual and can go over-rest.
        .onReceive(tickTimer) { _ in
            if viewModel.state.blockEndsAt != nil
                || viewModel.state.workEndsAt != nil
                || viewModel.currentRestShouldAutoAdvance {
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
            } else if viewModel.isRoundRobinBatchRoundRest {
                Text("ROUND \(viewModel.state.cursor.setIndex) COMPLETE")
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

    private var shouldShowStrengthJustDidRow: Bool {
        !isRestBlock && !viewModel.isCurrentBlockCardio && !viewModel.isRoundRobinBatchRoundRest
    }

    private var restBlockProgress: RestBlockProgress? {
        let blockIndex = viewModel.state.cursor.blockIndex
        guard blockIndex >= 0,
              blockIndex < viewModel.context.blocks.count,
              blockIndex < viewModel.context.itemsByBlock.count else {
            return nil
        }
        let block = viewModel.context.blocks[blockIndex]
        guard RestView.shouldRenderProgressGrid(
            for: block.timingMode,
            isRoundRobinBatchRoundRest: viewModel.isRoundRobinBatchRoundRest
        ) else {
            return nil
        }

        let items = viewModel.context.itemsByBlock[blockIndex]
        guard !items.isEmpty else { return nil }

        let dots = progressDots(blockIndex: blockIndex, items: items)

        guard !dots.isEmpty else { return nil }
        let completed = dots.filter { $0.state != .pending }.count
        return RestBlockProgress(
            blockIndex: blockIndex,
            blockCount: viewModel.context.blocks.count,
            completed: completed,
            total: dots.count,
            dots: dots
        )
    }

    private func progressDots(blockIndex: Int, items: [WorkoutItem]) -> [RestProgressDot] {
        let advancement = blockIndex < viewModel.state.structure.advancementByBlock.count
            ? viewModel.state.structure.advancementByBlock[blockIndex]
            : .setMajor
        let order = RestView.progressOrder(
            advancement: advancement,
            items: items,
            itemLogs: viewModel.state.items
        )
        var logsByItemID: [UUID: SessionState.ItemLog] = [:]
        for itemLog in viewModel.state.items {
            logsByItemID[itemLog.itemID] = itemLog
        }

        return order.compactMap { entry in
            guard let item = items.first(where: { $0.id == entry.itemID }),
                  let itemLog = logsByItemID[entry.itemID],
                  let set = itemLog.sets.first(where: { $0.setIndex == entry.setIndex }) else {
                return nil
            }
            return progressDot(item: item, itemLog: itemLog, set: set)
        }
    }

    private func progressDot(
        item: WorkoutItem,
        itemLog: SessionState.ItemLog,
        set: SetPlan
    ) -> RestProgressDot {
        let exerciseName = viewModel.context.exerciseName(
            for: item,
            performedExerciseID: itemLog.performedExerciseID
        )
        let state = RestView.progressDotState(for: set)
        return RestProgressDot(
            id: "\(item.id.uuidString)-\(set.setIndex)",
            state: state,
            accessibilityLabel: RestView.progressDotAccessibilityLabel(
                exerciseName: exerciseName,
                setIndex: set.setIndex,
                state: state
            )
        )
    }

    private var ringTile: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { tl in
            let now = tl.date
            let progress = restProgress(now: now)
            let remaining = RestView.restRemainingSeconds(
                endsAt: viewModel.state.restEndsAt,
                now: now
            )
            let overdue = RestView.restOverdueSeconds(
                endsAt: viewModel.state.restEndsAt,
                now: now
            )
            let isOverdue = overdue > 0
            VStack(spacing: DSSpacing.md) {
                ZStack {
                    DSRing(progress: progress, lineWidth: 8)
                        .frame(width: 200, height: 200)
                    VStack(spacing: DSSpacing.xs) {
                        Text(formatDuration(seconds: isOverdue ? overdue : remaining))
                            .font(.system(size: 44, weight: .light, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(isOverdue ? DSColors.danger : DSColors.accentInk)
                        Text(isOverdue ? "OVER REST" : "REST")
                            .font(DSTypography.caption)
                            .tracking(1.5)
                            .foregroundStyle(isOverdue ? DSColors.danger : DSColors.foregroundDim)
                    }
                }
                .padding(DSSpacing.md)
                .background(isOverdue ? DSColors.danger.opacity(0.16) : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(isOverdue ? DSColors.danger.opacity(0.6) : .clear, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                if !viewModel.currentRestShouldAutoAdvance {
                    restExtensionControls
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func progressGrid(_ progress: RestBlockProgress) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("BLOCK \(progress.blockIndex + 1) / \(progress.blockCount)")
                    .font(DSTypography.subLabel)
                    .tracking(1.2)
                    .foregroundStyle(DSColors.foregroundDim)
                Spacer()
                Text(RestView.progressSummary(completed: progress.completed, total: progress.total))
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.foregroundDim)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 18), spacing: DSSpacing.sm)],
                alignment: .leading,
                spacing: DSSpacing.sm
            ) {
                ForEach(progress.dots) { dot in
                    progressDot(dot.state)
                        .accessibilityLabel(dot.accessibilityLabel)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progressDot(_ state: RestProgressDotState) -> some View {
        Circle()
            .fill(progressDotFill(state))
            .frame(width: 10, height: 10)
            .overlay {
                if state == .skipped {
                    Circle()
                        .strokeBorder(DSColors.foregroundMuted, lineWidth: 1)
                }
            }
    }

    private func progressDotFill(_ state: RestProgressDotState) -> Color {
        switch state {
        case .performed:
            return DSColors.accentInk
        case .skipped:
            return DSColors.surfaceElevated
        case .pending:
            return DSColors.surfaceHigh
        }
    }

    private var restExtensionControls: some View {
        HStack(spacing: DSSpacing.sm) {
            Button {
                viewModel.extendRest(by: 30)
            } label: {
                Text("+30 sec")
                    .font(DSTypography.mono)
                    .foregroundStyle(DSColors.foreground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DSSpacing.md)
                    .background(DSColors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("add 30 seconds rest")

            Button {
                viewModel.extendRest(by: 60)
            } label: {
                Text("+1 min")
                    .font(DSTypography.mono)
                    .foregroundStyle(DSColors.foreground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DSSpacing.md)
                    .background(DSColors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("add 1 minute rest")
        }
    }

    private var justDidRow: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            // Group label moved to `DSTypography.subLabel` (12pt medium
            // mono) so it reads in gym lighting (bug-021). The per-pill
            // KG / REPS / RIR captions use the same token via `DSPill`.
            HStack(alignment: .firstTextBaseline) {
                let set = viewModel.lastLoggedSet
                Text(RestView.justLoggedHeader(for: set))
                    .font(DSTypography.subLabel)
                    .tracking(1.2)
                    .foregroundStyle(DSColors.foregroundDim)
                Spacer()
                if RestView.shouldOfferJustLoggedCorrection(for: set) {
                    Text("tap to correct")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.foregroundDim)
                }
            }

            HStack(spacing: DSSpacing.md) {
                let set = viewModel.lastLoggedSet
                if set?.skipped == true {
                    DSPill(value: "SKIPPED")
                        .accessibilityHint("Set was deliberately skipped")
                } else {
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
                        .accessibilityHint("Tap to correct logged load")
                    }
                    DSPill(
                        value: set.map { String($0.reps) } ?? "—",
                        caption: "REPS",
                        isEditable: set != nil,
                        onTap: set == nil ? nil : { activeSheet = .reps }
                    )
                    .accessibilityHint("Tap to correct logged reps")
                    DSPill(
                        value: set.flatMap { $0.rir.map(String.init) } ?? "skip",
                        caption: "RIR",
                        isEditable: set != nil,
                        onTap: set == nil ? nil : { activeSheet = .rir }
                    )
                    .accessibilityHint("Tap to correct logged RIR")
                }
            }
        }
    }

    private var roundRobinBatchRows: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("ROUND LOG")
                    .font(DSTypography.subLabel)
                    .tracking(1.2)
                    .foregroundStyle(DSColors.foregroundDim)
                Spacer()
                Text("tap to correct")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.foregroundDim)
            }

            VStack(spacing: DSSpacing.sm) {
                ForEach(viewModel.roundRobinBatchRows()) { row in
                    roundRobinBatchRow(row)
                }
            }
        }
    }

    private func roundRobinBatchRow(_ row: RoundRobinBatchSetRow) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(row.exerciseName)
                .font(DSTypography.subtitle)
                .foregroundStyle(DSColors.foreground)
            HStack(spacing: DSSpacing.sm) {
                if row.loadKg != nil {
                    DSPill(
                        value: row.loadKg.map { formatKilograms($0) } ?? "BW",
                        caption: row.unit.rawValue.uppercased(),
                        isEditable: true,
                        onTap: { activeSheet = .batchLoad(itemID: row.itemID, setIndex: row.setIndex) }
                    )
                }
                DSPill(
                    value: String(row.reps),
                    caption: "REPS",
                    isEditable: true,
                    onTap: { activeSheet = .batchReps(itemID: row.itemID, setIndex: row.setIndex) }
                )
                DSPill(
                    value: row.rir.map(String.init) ?? "—",
                    caption: "RIR",
                    isEditable: true,
                    onTap: { activeSheet = .batchRir(itemID: row.itemID, setIndex: row.setIndex) }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.md)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var nextButton: some View {
        DSButton(
            title: "next",
            style: .primary,
            action: { viewModel.advance() }
        )
    }

    private func nextUpCard(_ nextUp: ExecutionNextUpPresentation) -> some View {
        Button {
            activeSheet = .nextUp
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
        .accessibilityIdentifier("execution.rest.nextUp")
        .accessibilityHint("Tap to preview what is coming next")
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
        return !set.skipped && set.loadKg != nil
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
        if set.skipped || set.loadKg == nil {
            return nil
        }
        return set.unit.rawValue.uppercased()
    }

    /// Heading for the post-log row. Skipped sets count as cursor progress,
    /// but they are not performed work and must not read as logged metrics.
    static func justLoggedHeader(for set: SetPlan?) -> String {
        set?.skipped == true ? "SKIPPED SET" : "JUST LOGGED"
    }

    /// The correction affordance only applies to performed logs. A skipped row
    /// intentionally has no load, rep, RIR, distance, or duration metrics.
    static func shouldOfferJustLoggedCorrection(for set: SetPlan?) -> Bool {
        guard let set else { return false }
        return !set.skipped
    }

    static func progressSummary(completed: Int, total: Int) -> String {
        "\(max(0, completed)) / \(max(0, total)) DONE"
    }

    static func progressOrder(
        advancement: SessionState.BlockAdvancement,
        items: [WorkoutItem],
        itemLogs: [SessionState.ItemLog]
    ) -> [RestProgressOrderEntry] {
        var logsByItemID: [UUID: SessionState.ItemLog] = [:]
        for itemLog in itemLogs {
            logsByItemID[itemLog.itemID] = itemLog
        }

        switch advancement {
        case .zeroItem:
            return []
        case .setMajor:
            return items.flatMap { item -> [RestProgressOrderEntry] in
                guard let itemLog = logsByItemID[item.id] else { return [] }
                return itemLog.sets
                    .sorted(by: { $0.setIndex < $1.setIndex })
                    .map { RestProgressOrderEntry(itemID: item.id, setIndex: $0.setIndex) }
            }
        case .roundRobin:
            let itemIDs = Set(items.map(\.id))
            let maxSetIndex = itemLogs
                .filter { itemIDs.contains($0.itemID) }
                .flatMap(\.sets)
                .map(\.setIndex)
                .max() ?? 0
            guard maxSetIndex > 0 else { return [] }

            var order: [RestProgressOrderEntry] = []
            for setIndex in 1...maxSetIndex {
                for item in items {
                    let hasSet = logsByItemID[item.id]?.sets.contains { set in
                        set.setIndex == setIndex
                    } ?? false
                    guard hasSet else { continue }
                    order.append(RestProgressOrderEntry(itemID: item.id, setIndex: setIndex))
                }
            }
            return order
        }
    }

    static func shouldRenderProgressGrid(
        for timingMode: TimingMode,
        isRoundRobinBatchRoundRest: Bool = false
    ) -> Bool {
        if isRoundRobinBatchRoundRest {
            return false
        }
        switch timingMode {
        case .amrap, .emom, .accumulate:
            return false
        case .straightSets, .superset, .circuit, .forTime, .intervals,
             .tabata, .continuous, .custom, .rest:
            return true
        }
    }

    private static func progressDotState(for set: SetPlan) -> RestProgressDotState {
        guard set.done else { return .pending }
        return set.skipped ? .skipped : .performed
    }

    private static func progressDotAccessibilityLabel(
        exerciseName: String,
        setIndex: Int,
        state: RestProgressDotState
    ) -> String {
        let status: String
        switch state {
        case .performed:
            status = "done"
        case .skipped:
            status = "skipped"
        case .pending:
            status = "pending"
        }
        return "\(exerciseName) set \(setIndex) \(status)"
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

    static func restRemainingSeconds(endsAt: Date?, now: Date) -> TimeInterval {
        max(0, endsAt?.timeIntervalSince(now) ?? 0)
    }

    static func restOverdueSeconds(endsAt: Date?, now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(endsAt ?? now))
    }
}
