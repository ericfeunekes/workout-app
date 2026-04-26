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
                ActiveView(viewModel: viewModel)
            case .transition:
                BlockTransitionView(viewModel: viewModel)
            case .rest:
                RestView(viewModel: viewModel)
            case .complete:
                CompleteView(viewModel: viewModel)
            }
        }
    }
}
