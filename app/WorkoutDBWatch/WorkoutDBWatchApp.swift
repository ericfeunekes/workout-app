// WorkoutDBWatchApp.swift
//
// The watchOS companion shell. Per docs/architecture/swift-packages.md,
// watch UI lives in the `FeaturesWatchFaces` package and imports
// `CoreSession` + `WatchBridge` directly — no duplicate domain logic
// lives on the watch (HS-7). The watch talks to the iPhone via
// WatchConnectivity, wrapped by the `LiveWatchBridge` in the
// `WatchBridge` package (the only module allowed to import
// WatchConnectivity — FF-13).
//
// Wire-up:
//   - `LiveWatchBridge` activates a WatchConnectivity session on init.
//   - `WatchFacesViewModel` subscribes to `bridge.messages()` from `.task`.
//   - `WatchFacesView` dispatches between Idle / ActiveSet / Rest faces.

import SwiftUI
import FeaturesWatchFaces
import WatchBridge

@main
struct WorkoutDBWatchApp: App {
    @State private var viewModel = WatchFacesViewModel(bridge: LiveWatchBridge())

    var body: some Scene {
        WindowGroup {
            WatchFacesView(viewModel: viewModel)
                .preferredColorScheme(.dark)
                .task { await viewModel.start() }
        }
    }
}
