// WorkoutDBWatchApp.swift
//
// The watchOS companion shell. Per docs/architecture/swift-packages.md,
// watch UI lives in the `FeaturesWatchFaces` package and consumes typed
// metrics through `HealthKitBridge`; no duplicate domain logic lives on the
// watch (HS-7). The watch talks to the iPhone via WatchConnectivity, wrapped
// by the `LiveWatchBridge` in the `WatchBridge` package (the only module
// allowed to import WatchConnectivity — FF-13).
//
// Wire-up:
//   - `LiveWatchBridge` activates a WatchConnectivity session on init.
//   - `WatchFacesViewModel` subscribes to `bridge.messages()` from `.task`.
//   - `WatchFacesView` dispatches between Idle / ActiveSet / Rest faces.

import SwiftUI
import FeaturesWatchFaces
import HealthKitBridge
import WatchBridge

@main
struct WorkoutDBWatchApp: App {
    @State private var shouldRunHealthKitProbe = Self.healthKitLiveWorkoutProbeRequested()
    @State private var viewModel = WatchFacesViewModel(
        bridge: LiveWatchBridge(),
        metricSource: HealthKitWorkoutMetricSource()
    )

    var body: some Scene {
        WindowGroup {
            Group {
                if shouldRunHealthKitProbe {
                    HealthKitLiveWorkoutProbeView()
                } else {
                    WatchFacesView(viewModel: viewModel)
                        .task {
                            await viewModel.start()
                        }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private static func healthKitLiveWorkoutProbeRequested() -> Bool {
        let envRequestsProbe = ProcessInfo.processInfo.environment["HEALTHKIT_LIVE_WORKOUT_PROBE"] == "1"
        let defaultsRequestProbe = UserDefaults.standard.bool(forKey: "HEALTHKIT_LIVE_WORKOUT_PROBE")
        let requested = ProcessInfo.processInfo.arguments.contains("--healthkit-live-workout-probe")
            || envRequestsProbe
            || defaultsRequestProbe
        guard requested else { return false }
        UserDefaults.standard.set(false, forKey: "HEALTHKIT_LIVE_WORKOUT_PROBE")
        return true
    }
}

private struct HealthKitLiveWorkoutProbeView: View {
    @State private var status = "starting"

    var body: some View {
        VStack(spacing: 8) {
            Text("HealthKit Probe")
                .font(.headline)
            Text(status)
                .font(.caption2)
                .multilineTextAlignment(.center)
        }
        .task {
            await run()
        }
    }

    private func run() async {
        status = "running"
        let result = await Task.detached(priority: .userInitiated) {
            await HealthKitLiveWorkoutProbeRunner().run()
        }.value
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(result),
           let json = String(data: data, encoding: .utf8) {
            emit("HEALTHKIT_LIVE_WORKOUT_PROBE_JSON_BEGIN")
            emit(json)
            emit("HEALTHKIT_LIVE_WORKOUT_PROBE_JSON_END")
            status = result.error == nil ? "passed" : "failed"
        } else {
            emit("HEALTHKIT_LIVE_WORKOUT_PROBE_JSON_ENCODE_FAILED")
            status = "encode failed"
        }
    }

    private func emit(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}
