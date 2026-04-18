// HistoryView.swift
//
// Root view for the History tab. Owns the NavigationStack, switches
// between the list and by-exercise surfaces based on the VM's `tab`,
// and routes to session / exercise detail destinations.
//
// Placed at the top of the file graph so callers (the app shell's
// RootTabView) just hand over a `HistoryViewModel` and get a full
// history surface back.

import SwiftUI
import CoreDomain
import DesignSystem
import Persistence
import WorkoutCoreFoundation

public struct HistoryView: View {
    @State private var viewModel: HistoryViewModel

    public init(viewModel: HistoryViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                DSColors.background.ignoresSafeArea()
                content
            }
            .navigationTitle("History")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .navigationDestination(for: WorkoutID.self) { (id: WorkoutID) in
                if let detail = viewModel.detail(for: id) {
                    HistorySessionDetailView(
                        viewModel: detail,
                        historyViewModel: viewModel
                    )
                } else {
                    Text("session not found")
                        .foregroundStyle(DSColors.foregroundMuted)
                }
            }
            .navigationDestination(for: ByExerciseDestination.self) { destination in
                if let detail = viewModel.exerciseDetail(for: destination.exerciseID) {
                    HistoryExerciseDetailView(viewModel: detail)
                } else {
                    Text("exercise not found")
                        .foregroundStyle(DSColors.foregroundMuted)
                }
            }
        }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.tab {
        case .list:
            HistoryListView(viewModel: viewModel)
        case .byExercise:
            HistoryByExerciseView(viewModel: viewModel)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("History — list") {
    HistoryView(viewModel: HistoryViewModel(
        cache: HistoryPreviewSeed.makePreviewCache()
    ))
    .preferredColorScheme(.dark)
}
#endif
