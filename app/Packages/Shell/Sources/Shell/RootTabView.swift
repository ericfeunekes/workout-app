// RootTabView.swift
//
// The three-tab root view surfaced once bootstrap produces a live
// TodayViewModel + ExecutionViewModel. Kept here (not in WorkoutDBApp)
// because Shell is the one place allowed to see multiple Features at
// once — the SwiftLint rule `no_feature_cross_import` forbids anyone
// else from wiring Today + History + Settings into the same view.
//
// The app shell calls `RootTabView(todayVM:executionVM:historyVM:
// settingsVM:)` and renders the returned view inside its `WindowGroup`.
// This lets the parallel concurrency-fix slice stay focused on
// WorkoutDBApp.swift's routing logic; when both slices land, the
// `routedView(todayVM:executionVM:)` call becomes `RootTabView(...)`.
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
    private let executionVM: ExecutionViewModel
    private let historyVM: HistoryViewModel
    private let settingsVM: SettingsViewModel?

    /// Build the tab container. `settingsVM` is optional so callers that
    /// haven't wired Settings yet can pass `nil` and skip the tab.
    public init(
        initial: RootTab = .today,
        todayVM: TodayViewModel,
        executionVM: ExecutionViewModel,
        historyVM: HistoryViewModel,
        settingsVM: SettingsViewModel? = nil
    ) {
        _tab = State(initialValue: initial)
        self.todayVM = todayVM
        self.executionVM = executionVM
        self.historyVM = historyVM
        self.settingsVM = settingsVM
    }

    public var body: some View {
        // Note: `.accessibilityIdentifier` on tab content does NOT propagate
        // to the tab-bar button in SwiftUI's `TabView`. See
        // `docs/open-questions.md` § "Tab bar accessibility IDs missing" —
        // real fix requires a custom tab bar or UIKit wrapper. For now
        // MCP-driven UI tests fall back to coordinate taps on the tab bar.
        TabView(selection: $tab) {
            todayTab
                .tag(RootTab.today)
                .tabItem { Label("today", systemImage: "figure.strengthtraining.traditional") }

            HistoryView(viewModel: historyVM)
                .tag(RootTab.history)
                .tabItem { Label("history", systemImage: "clock") }

            if let settingsVM {
                NavigationStack {
                    SettingsView(viewModel: settingsVM)
                        .navigationTitle("Settings")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.large)
                        #endif
                }
                .tag(RootTab.settings)
                .tabItem { Label("settings", systemImage: "gearshape") }
            }
        }
        .tint(DSColors.accent)
    }

    /// Route the "today" tab's content based on session route — same
    /// rule as the non-tab shell in WorkoutDBApp.routedView.
    @ViewBuilder
    private var todayTab: some View {
        switch executionVM.state.route {
        case .today:
            TodayView(viewModel: todayVM)
        case .active, .rest, .complete:
            ExecutionView(viewModel: executionVM)
        }
    }
}
