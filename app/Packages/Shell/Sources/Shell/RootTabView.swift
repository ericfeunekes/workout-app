// RootTabView.swift
//
// The three-tab root view surfaced once bootstrap produces a live
// TodayViewModel + ExecutionVMHolder. Kept here (not in WorkoutDBApp)
// because Shell is the one place allowed to see multiple Features at
// once — the SwiftLint rule `no_feature_cross_import` forbids anyone
// else from wiring Today + History + Settings into the same view.
//
// The app shell calls `RootTabView(todayVM:executionHolder:historyVM:
// settingsVM:)` and renders the returned view inside its `WindowGroup`.
// `executionHolder` is observed through `@Bindable` so the shell can
// swap `holder.vm` after save-and-done and the view re-evaluates the
// routing switch against the NEW vm's `.state.route` (qa-002 / qa-003
// root cause: previously the view held a stale VM reference and the
// shell's `holder.vm = newVM` was unobserved).
//
// Tab entries (matches docs/design/components/meta.jsx TabBar):
//   • today    — TodayView or ExecutionView based on session route
//   • history  — HistoryView
//   • settings — SettingsView wrapped in a NavigationStack for title

import SwiftUI
import CoreSession
import DesignSystem
import FeaturesExecution
import FeaturesHistory
import FeaturesSettings
import FeaturesToday

/// Identifier for the current tab. Exposed so callers can pin a default
/// (e.g. post-bootstrap jump straight to History).
public enum RootTab: Sendable, Hashable {
    case today
    case history
    case settings
}

public struct RootTabView: View {
    @State private var tab: RootTab
    private let todayVM: TodayViewModel
    /// Observable holder whose `.vm` swaps per-workout after save-and-done.
    /// `@Bindable` lets the view track `holder.vm` changes so the swap
    /// flips the rendered routing branch onto the fresh VM.
    @Bindable private var executionHolder: ExecutionVMHolder
    private let historyVM: HistoryViewModel
    private let settingsVM: SettingsViewModel?

    /// Build the tab container. `settingsVM` is optional so callers that
    /// haven't wired Settings yet can pass `nil` and skip the tab.
    public init(
        initial: RootTab = .today,
        todayVM: TodayViewModel,
        executionHolder: ExecutionVMHolder,
        historyVM: HistoryViewModel,
        settingsVM: SettingsViewModel? = nil
    ) {
        _tab = State(initialValue: initial)
        self.todayVM = todayVM
        self.executionHolder = executionHolder
        self.historyVM = historyVM
        self.settingsVM = settingsVM
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            activeContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if shouldShowTabBar {
                HStack(spacing: DSSpacing.sm) {
                    tabButton(.today, title: "today", systemImage: "figure.strengthtraining.traditional")
                    tabButton(.history, title: "history", systemImage: "clock")
                    if settingsVM != nil {
                        tabButton(.settings, title: "settings", systemImage: "gearshape")
                    }
                }
                .padding(DSSpacing.sm)
                .background(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(DSColors.border.opacity(0.7), lineWidth: 1)
                )
                .clipShape(Capsule(style: .continuous))
                .padding(.horizontal, DSSpacing.xl)
                .padding(.bottom, DSSpacing.lg)
            }
        }
        .tint(DSColors.accent)
    }

    @ViewBuilder
    private var activeContent: some View {
        switch tab {
        case .today:
            todayTab
        case .history:
            HistoryView(viewModel: historyVM)
        case .settings:
            if let settingsVM {
                NavigationStack {
                    SettingsView(viewModel: settingsVM)
                        .navigationTitle("Settings")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.large)
                        #endif
                }
            } else {
                todayTab
            }
        }
    }

    private var shouldShowTabBar: Bool {
        guard let executionVM = executionHolder.vm else { return true }
        switch executionVM.state.route {
        case .today:
            return true
        case .active, .transition, .rest, .complete:
            return false
        }
    }

    private func tabButton(
        _ destination: RootTab,
        title: String,
        systemImage: String
    ) -> some View {
        let isSelected = tab == destination
        return Button {
            tab = destination
        } label: {
            VStack(spacing: DSSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(DSTypography.caption)
                    .tracking(0.4)
            }
            .foregroundStyle(isSelected ? DSColors.accentInk : DSColors.foregroundMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DSSpacing.md)
            .background(isSelected ? DSColors.accentMuted : Color.clear)
            .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("root.tab.\(title)")
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Route the "today" tab's content based on session route — same
    /// rule as the non-tab shell in WorkoutDBApp.routedView.
    ///
    /// Reads `executionHolder.vm` so a post-save VM swap (new workout
    /// constructed by the completion writer) flips the rendered branch
    /// without a relaunch. When `vm` is `nil` — the "no next planned
    /// workout" terminal state — Today's `isEmpty == true` state hides
    /// the start button, so the nil branch is never dispatched to.
    @ViewBuilder
    private var todayTab: some View {
        if let executionVM = executionHolder.vm {
            switch executionVM.state.route {
            case .today:
                TodayView(viewModel: todayVM)
            case .active, .transition, .rest, .complete:
                ExecutionView(viewModel: executionVM)
            }
        } else {
            // No active execution VM → user has no planned workouts
            // queued. TodayView renders its own empty state.
            TodayView(viewModel: todayVM)
        }
    }
}
