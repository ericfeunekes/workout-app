// WatchFacesView.swift
//
// Top-level dispatcher for the watch companion. Reads the view model's
// `face` and switches to the matching face view. Tap handling is funneled
// through `viewModel.tap()`; each face propagates its tap callback here.
//
// The watch target's `WorkoutDBWatchApp` is responsible for calling
// `viewModel.start()` from a `.task` modifier on this view — placing the
// subscription at the scene root means it lives for the lifetime of the
// app and ties cleanup to scene teardown, not to face switches.

import SwiftUI
import DesignSystem

public struct WatchFacesView: View {
    @State private var viewModel: WatchFacesViewModel

    public init(viewModel: WatchFacesViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ZStack {
            DSColors.background.ignoresSafeArea()

            switch viewModel.face {
            case .idle:
                IdleFace()
            case .active(let payload):
                ActiveSetFace(payload: payload, onTap: { viewModel.tap() })
            case .rest(let payload):
                RestFace(payload: payload, onTap: { viewModel.tap() })
            }
        }
    }
}
