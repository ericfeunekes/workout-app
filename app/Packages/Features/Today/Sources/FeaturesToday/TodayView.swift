// TodayView.swift
//
// The Today screen — read-side plan queue for missed, current, and
// upcoming workouts. The shell can start any visible planned workout by
// rebuilding the execution VM for that card before routing into execution.
//
// Dark-only; all color, type, and spacing from DesignSystem tokens.

import SwiftUI
import CoreDomain
import CoreSession
import DesignSystem
import WorkoutCoreFoundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct TodayView: View {
    @State private var viewModel: TodayViewModel
    @State private var selectedDetail: TodayViewModel.WorkoutDetail?
    @State private var copiedAdjustmentID: UUID?
    @State private var visibleWorkoutIDs: Set<UUID> = []
    @State private var measuredWorkoutIDs: Set<UUID> = []
    @State private var visibleSectionIDs: Set<String> = []
    @State private var measuredSectionIDs: Set<String> = []

    public init(viewModel: TodayViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ZStack {
            DSColors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DSSpacing.xl) {
                        if viewModel.isEmpty {
                            emptyGlance
                        } else {
                            header
                            lastSessionChip
                            planQueue
                        }
                    }
                    .padding(.horizontal, DSSpacing.xl)
                    .padding(.top, DSSpacing.xxl)
                    .padding(.bottom, DSSpacing.xxl)
                }
                .refreshable {
                    await viewModel.refresh()
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear
                        .frame(height: 96)
                        .allowsHitTesting(false)
                }
                .onPreferenceChange(TodayWorkoutCardFramePreferenceKey.self) { frames in
                    measuredWorkoutIDs = Set(frames.keys)
                    visibleWorkoutIDs = TodayWorkoutAccessibilityVisibility.visibleWorkoutIDs(
                        frames: frames,
                        viewport: currentViewport
                    )
                }
                .onPreferenceChange(TodaySectionFramePreferenceKey.self) { frames in
                    measuredSectionIDs = Set(frames.keys)
                    visibleSectionIDs = TodaySectionAccessibilityVisibility.visibleSectionIDs(
                        frames: frames,
                        viewport: currentViewport
                    )
                }
            }
        }
        .sheet(item: $selectedDetail) { detail in
            workoutDetailSheet(detail)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Text("Today")
                        .font(DSTypography.display)
                        .foregroundStyle(DSColors.foreground)

                    Text("planned queue")
                        .font(DSTypography.caption)
                        .tracking(1.5)
                        .foregroundStyle(DSColors.foregroundDim)
                }

                Spacer()

                if viewModel.canRefresh {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Text(refreshLabel)
                            .font(DSTypography.caption)
                            .tracking(0.8)
                            .foregroundStyle(DSColors.accentInk)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.refreshState == .refreshing)
                }
            }

            if viewModel.refreshState == .failed {
                Text("refresh failed; showing local cache")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.warn)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var refreshLabel: String {
        switch viewModel.refreshState {
        case .idle, .failed: return "REFRESH"
        case .refreshing: return "SYNCING"
        }
    }

    @ViewBuilder
    private var lastSessionChip: some View {
        if let summary = viewModel.lastSessionSummary {
            DSChip(label: "last session", value: summary, tone: .default)
        }
    }

    private var planQueue: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xl) {
            ForEach(viewModel.planSections) { section in
                let isAccessible = isSectionAccessible(section.id)
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Text(section.title)
                        .font(DSTypography.caption)
                        .tracking(1.5)
                        .foregroundStyle(sectionColor(section.kind))
                        .background(sectionFrameReader(section.id))
                        .accessibilityHidden(!isAccessible)

                    VStack(spacing: DSSpacing.lg) {
                        ForEach(section.workouts) { workout in
                            workoutCard(workout)
                        }
                    }
                }
            }
        }
    }

    private func workoutCard(_ workout: TodayViewModel.WorkoutSummary) -> some View {
        let isAccessible = isWorkoutCardAccessible(workout.id)
        return DSCard {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                Button {
                    selectedDetail = viewModel.detail(for: workout.id)
                } label: {
                    VStack(alignment: .leading, spacing: DSSpacing.md) {
                        workoutCardHeader(workout)
                        workoutCardPreview(workout)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("preview \(workout.name)")
                .accessibilityHint("Opens workout preview")
                .accessibilityIdentifier("today.workout.detail.\(workout.id.uuidString)")
                .accessibilityHidden(!isAccessible)
                .allowsHitTesting(isAccessible)

                Text("tap to preview")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.foregroundDim)
                    .accessibilityHidden(true)
            }
        }
        .background(workoutCardFrameReader(workout.id))
        .accessibilityHidden(!isAccessible)
        .allowsHitTesting(isAccessible)
    }

    private func workoutCardHeader(_ workout: TodayViewModel.WorkoutSummary) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.md) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(workout.name)
                    .font(DSTypography.title)
                    .foregroundStyle(DSColors.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let tagLine = workout.tagLine {
                    Text(tagLine)
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.foregroundDim)
                }
            }

            if let badge = workout.badge {
                Text(badge.uppercased())
                    .font(DSTypography.caption)
                    .tracking(0.8)
                    .foregroundStyle(badgeColor(workout))
                    .padding(.vertical, DSSpacing.xs)
                    .padding(.horizontal, DSSpacing.sm)
                    .background(badgeBackground(workout))
                    .clipShape(Capsule())
            }
        }
    }

    @ViewBuilder
    private func workoutCardPreview(_ workout: TodayViewModel.WorkoutSummary) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            ForEach(workout.cardBlocks) { block in
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    HStack(alignment: .center, spacing: DSSpacing.sm) {
                        DSExerciseIconView(
                            icon: blockIcon(for: block.timingLabel),
                            size: 30,
                            showsTile: true
                        )

                        VStack(alignment: .leading, spacing: DSSpacing.xs) {
                            Text(block.timingLabel.uppercased())
                                .font(DSTypography.caption)
                                .tracking(0.9)
                                .foregroundStyle(DSColors.accentInk)

                            Text(block.title)
                                .font(DSTypography.subtitle)
                                .foregroundStyle(DSColors.foregroundMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if let timingDetail = block.timingDetail {
                        Text(timingDetail)
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColors.foregroundDim)
                    }

                    ForEach(block.exercises) { row in
                        exerciseRow(row, muted: true)
                    }

                    if block.hasMoreExercises {
                        Text("more exercises in details")
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColors.foregroundFaint)
                    }
                }
            }

            if workout.hasMoreBlocks {
                Text("more blocks in details")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.foregroundFaint)
            }
        }
    }

    private func exerciseRow(
        _ row: TodayViewModel.ExerciseSummary,
        muted: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.md) {
            Text(row.name)
                .font(DSTypography.body)
                .foregroundStyle(muted ? DSColors.foregroundMuted : DSColors.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.prescriptionLine)
                .font(DSTypography.mono)
                .monospacedDigit()
                .foregroundStyle(DSColors.foregroundDim)
        }
    }

    private func workoutDetailSheet(_ detail: TodayViewModel.WorkoutDetail) -> some View {
        ZStack {
            DSColors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.xl) {
                    HStack {
                        Spacer()
                        Button("done") {
                            selectedDetail = nil
                        }
                        .font(DSTypography.body)
                        .foregroundStyle(DSColors.accentInk)
                    }

                    detailHeader(detail)

                    ForEach(detail.blocks) { block in
                        blockDetailCard(block)
                    }

                    adjustmentCard(detail)
                }
                .padding(.horizontal, DSSpacing.xl)
                .padding(.top, DSSpacing.xl)
                .padding(.bottom, DSSpacing.xxl)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.canStart(workoutID: detail.id) {
                DSButton(title: "start", style: .primary) {
                    selectedDetail = nil
                    Task {
                        await viewModel.start(workoutID: detail.id)
                    }
                }
                .accessibilityIdentifier("today.preview.start.\(detail.id.uuidString)")
                .padding(.horizontal, DSSpacing.xl)
                .padding(.bottom, DSSpacing.xl)
                .padding(.top, DSSpacing.md)
                .background(DSColors.background)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func detailHeader(_ detail: TodayViewModel.WorkoutDetail) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(detail.sectionTitle)
                .font(DSTypography.caption)
                .tracking(1.5)
                .foregroundStyle(DSColors.foregroundDim)

            Text(detail.name)
                .font(DSTypography.display)
                .foregroundStyle(DSColors.foreground)

            if let tagLine = detail.tagLine {
                Text(tagLine)
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.foregroundMuted)
            }

            if let notes = detail.notes, !notes.isEmpty {
                Text(notes)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.foregroundMuted)
                    .padding(.top, DSSpacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func adjustmentCard(_ detail: TodayViewModel.WorkoutDetail) -> some View {
        let draft = viewModel.adjustmentDraft(for: detail)
        return DSCard {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                Text("Need to change this?")
                    .font(DSTypography.subtitle)
                    .foregroundStyle(DSColors.foreground)

                Text("Copy a structured request for Claude. The app does not reorder, swap, or delete planned work locally.")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.foregroundMuted)

                DSButton(
                    title: copiedAdjustmentID == detail.id
                        ? "copied"
                        : "copy adjustment request",
                    style: .ghost
                ) {
                    copyToClipboard(draft.body)
                    copiedAdjustmentID = detail.id
                }

                if copiedAdjustmentID == detail.id {
                    Text("Copied. Paste it into Claude to request changes.")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.accentInk)
                        .accessibilityIdentifier("today.adjustment.copied")
                }
            }
        }
    }

    private func blockDetailCard(_ block: TodayViewModel.BlockDetail) -> some View {
        DSCard {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                HStack(alignment: .top, spacing: DSSpacing.md) {
                    DSExerciseIconView(
                        icon: blockIcon(for: block.timingLabel),
                        size: 44,
                        showsTile: true
                    )

                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text(block.timingLabel.uppercased())
                            .font(DSTypography.caption)
                            .tracking(1.2)
                            .foregroundStyle(DSColors.accentInk)

                        Text(block.title)
                            .font(DSTypography.title)
                            .foregroundStyle(DSColors.foreground)

                        if let timingDetail = block.timingDetail {
                            Text(timingDetail)
                                .font(DSTypography.caption)
                                .foregroundStyle(DSColors.foregroundMuted)
                        }

                        if let notes = block.notes, !notes.isEmpty {
                            Text(notes)
                                .font(DSTypography.caption)
                                .foregroundStyle(DSColors.foregroundDim)
                        }
                    }
                }

                if !block.exercises.isEmpty {
                    DSDivider()
                    VStack(alignment: .leading, spacing: DSSpacing.sm) {
                        ForEach(block.exercises) { row in
                            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                                exerciseRow(row, muted: false)
                                if let lastTime = row.lastTime {
                                    Text("last time \(lastTime)")
                                        .font(DSTypography.caption)
                                        .foregroundStyle(DSColors.foregroundDim)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func sectionColor(_ kind: TodayViewModel.PlanSectionKind) -> Color {
        switch kind {
        case .missed: return DSColors.warn
        case .today: return DSColors.accentInk
        case .upcoming: return DSColors.foregroundDim
        case .unscheduled: return DSColors.foregroundDim
        }
    }

    private func badgeColor(_ workout: TodayViewModel.WorkoutSummary) -> Color {
        if workout.isSelected { return DSColors.success }
        switch workout.sectionKind {
        case .missed: return DSColors.warn
        case .today, .upcoming, .unscheduled: return DSColors.success
        }
    }

    private func badgeBackground(_ workout: TodayViewModel.WorkoutSummary) -> Color {
        if workout.isSelected { return DSColors.success.opacity(0.12) }
        switch workout.sectionKind {
        case .missed: return DSColors.warn.opacity(0.12)
        case .today, .upcoming, .unscheduled: return DSColors.success.opacity(0.12)
        }
    }

    private func blockIcon(for timingLabel: String) -> DSExerciseIcon {
        switch timingLabel {
        case "straight sets":
            return .strength
        case "amrap", "for time", "circuit", "superset":
            return .conditioning
        case "emom", "tabata", "intervals", "custom", "accumulate", "continuous":
            return .timer
        default:
            return .timer
        }
    }

    private var currentViewport: CGRect {
        #if os(iOS)
        UIScreen.main.bounds
        #elseif os(macOS)
        NSScreen.main?.frame ?? .zero
        #endif
    }

    private func isWorkoutCardAccessible(_ id: UUID) -> Bool {
        measuredWorkoutIDs.isEmpty || visibleWorkoutIDs.contains(id)
    }

    private func isSectionAccessible(_ id: String) -> Bool {
        measuredSectionIDs.isEmpty || visibleSectionIDs.contains(id)
    }

    private func workoutCardFrameReader(_ id: UUID) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: TodayWorkoutCardFramePreferenceKey.self,
                value: [id: proxy.frame(in: .global)]
            )
        }
    }

    private func sectionFrameReader(_ id: String) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: TodaySectionFramePreferenceKey.self,
                value: [id: proxy.frame(in: .global)]
            )
        }
    }

    // qa-008: when `viewModel.isEmpty == true` the VM has no workout to
    // render — previously the view still displayed the pinned "start
    // workout" button, producing a black screen with an orphaned CTA.
    // Per `docs/features/today.md` S11, the empty path should render a
    // quiet message and no CTA until Claude pushes a new session.
    private var emptyGlance: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("no planned workouts")
                .font(DSTypography.body)
                .foregroundStyle(DSColors.foregroundMuted)
            Text("check back after Claude sends a new session.")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.foregroundDim)

            if viewModel.refreshState == .failed {
                Text("refresh failed; showing local cache")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.warn)
                    .padding(.top, DSSpacing.sm)
            }

            if viewModel.canRefresh {
                DSButton(title: refreshLabel.lowercased(), style: .ghost) {
                    Task { await viewModel.refresh() }
                }
                .padding(.top, DSSpacing.md)
                .disabled(viewModel.refreshState == .refreshing)
            }
        }
        .padding(.vertical, DSSpacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TodayWorkoutCardFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct TodaySectionFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

enum TodayWorkoutAccessibilityVisibility {
    static func visibleWorkoutIDs(frames: [UUID: CGRect], viewport: CGRect) -> Set<UUID> {
        Set(frames.compactMap { id, frame in
            isVisible(frame: frame, viewport: viewport) ? id : nil
        })
    }

    static func isVisible(frame: CGRect, viewport: CGRect) -> Bool {
        frame.width > 0 && frame.height > 0 && frame.intersects(viewport)
    }
}

enum TodaySectionAccessibilityVisibility {
    static func visibleSectionIDs(frames: [String: CGRect], viewport: CGRect) -> Set<String> {
        Set(frames.compactMap { id, frame in
            TodayWorkoutAccessibilityVisibility.isVisible(frame: frame, viewport: viewport) ? id : nil
        })
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Today — Push A") {
    TodayView(viewModel: TodayViewModel(
        context: TodayPreviewSeed.pushA(withLastSession: true)
    ))
    .preferredColorScheme(.dark)
}

#Preview("Today — no prior session") {
    TodayView(viewModel: TodayViewModel(
        context: TodayPreviewSeed.pushA(withLastSession: false)
    ))
    .preferredColorScheme(.dark)
}

#Preview("Today — empty (nothing planned)") {
    let vm = TodayViewModel(
        context: TodayPreviewSeed.pushA(withLastSession: false)
    )
    vm.apply(nil)
    return TodayView(viewModel: vm)
        .preferredColorScheme(.dark)
}
#endif
