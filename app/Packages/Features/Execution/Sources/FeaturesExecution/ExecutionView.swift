// ExecutionView.swift
//
// Top-level router for the Execution feature. Switches between the
// Active, Rest, Transition, and Complete screens based on `SessionState.Route`.
// `.today` is owned by `FeaturesToday` and never shown here — the shell
// uses `ExecutionView` only once the session is in-flight.
//
// Matches the Router in `docs/design/src/hifi.jsx` § "Router".

import SwiftUI
import CoreSession
import DesignSystem

public struct ExecutionView: View {
    @State private var viewModel: ExecutionViewModel
    @State private var showEndConfirm = false

    public init(viewModel: ExecutionViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ZStack {
            DSColors.background
                .ignoresSafeArea()

            switch viewModel.state.route {
            case .today:
                // Defensive: should never render. The shell should be
                // showing TodayView while the session is on `.today`.
                Color.clear
            case .active:
                ActiveView(
                    viewModel: viewModel,
                    onEndRequested: requestEndConfirmation
                )
            case .transition:
                BlockTransitionView(viewModel: viewModel)
            case .rest:
                RestView(
                    viewModel: viewModel,
                    onEndRequested: requestEndConfirmation
                )
            case .complete:
                CompleteView(viewModel: viewModel)
            }
        }
        // Keep End confirmation owned by the stable execution router so
        // route changes can dismiss it deterministically instead of leaving
        // route-local alert state attached to a discarded Active/Rest view.
        .alert("End workout?", isPresented: $showEndConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("End", role: .destructive) {
                viewModel.complete()
            }
        } message: {
            Text("Unlogged sets won't be recorded. You can still save & done.")
        }
        .onChange(of: viewModel.state.route) { oldRoute, newRoute in
            if ExecutionView.shouldDismissEndConfirmation(oldRoute: oldRoute, newRoute: newRoute) {
                showEndConfirm = false
            }
        }
    }

    static func shouldDismissEndConfirmation(
        oldRoute: SessionState.Route,
        newRoute: SessionState.Route
    ) -> Bool {
        oldRoute != newRoute
    }

    private func requestEndConfirmation() {
        showEndConfirm = true
    }
}
