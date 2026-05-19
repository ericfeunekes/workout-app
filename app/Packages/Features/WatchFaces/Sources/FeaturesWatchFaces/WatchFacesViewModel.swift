// WatchFacesViewModel.swift
//
// `@Observable` view model for the watchOS companion. Owns the current
// `Face` and the outbound `WatchBridge` handle. Subscribes to
// `bridge.messages()` on `start()`; every inbound message updates `face`.
//
// Design:
//   - The watch does NOT run the session reducer. The phone is authoritative;
//     the watch just mirrors the payloads the phone sends. A face is therefore
//     a pure function of the most recent matching message.
//   - `pushActiveBlock` → `.active(...)`, `pushRestTimer` → `.rest(...)`,
//     `pushWorkoutComplete` → `.idle`. Any other message type is ignored by
//     the watch (it is not the target).
//   - Tap handling is funneled through `tap()` so the view layer is not
//     responsible for knowing which outbound message maps to which face —
//     the view model translates face → message and calls `bridge.send(_:)`.
//
// Concurrency:
//   - `@MainActor` because SwiftUI reads `face` on the main thread.
//   - The subscription loop awaits on `bridge.messages()`, a bridge-owned
//     `AsyncStream`. It terminates when the stream finishes (the bridge
//     calls `finish()`).
//   - Outbound sends are fire-and-forget `Task`s launched from `tap()` so
//     the view layer's gesture closure stays synchronous. We use
//     `Task.detached` to satisfy the `no_direct_task_unstructured`
//     SwiftLint rule; `try? await` swallows transport errors (the user
//     tapped, we tried to send — any retry is a bridge concern).

import Foundation
import CoreSession
import HealthKitBridge
import WatchBridge

@Observable
@MainActor
public final class WatchFacesViewModel {

    // MARK: - Face shape

    /// The face currently being rendered. One of three v1 faces. The
    /// `.active` and `.rest` cases carry pre-formatted payloads so the
    /// view layer never parses message data directly — consistent with
    /// the iOS Features pattern where the view model owns derivation.
    public enum Face: Equatable, Sendable {
        case idle
        case active(ActivePayload)
        case rest(RestPayload)
    }

    /// Payload for `ActiveSetFace`. Fields mirror `ActiveBlockPayload`
    /// from WatchBridge, renamed for clarity at the render site.
    public struct ActivePayload: Equatable, Sendable {
        public let exerciseName: String
        public let prescription: String
        public let setNumber: Int
        public let setCount: Int
        public let targetRir: Int?
        public let heartRateBPM: Int?

        public init(
            exerciseName: String,
            prescription: String,
            setNumber: Int,
            setCount: Int,
            targetRir: Int?,
            heartRateBPM: Int? = nil
        ) {
            self.exerciseName = exerciseName
            self.prescription = prescription
            self.setNumber = setNumber
            self.setCount = setCount
            self.targetRir = targetRir
            self.heartRateBPM = heartRateBPM
        }
    }

    /// Payload for `RestFace`. `endsAt` is absolute (iOS convention —
    /// see `SessionState.restEndsAt`) so the view can derive remaining
    /// time with a `TimelineView` without worrying about drift.
    ///
    /// `exerciseName` is the last-active exercise name — we carry it so
    /// the rest face can show "what you just did" without a second
    /// inbound message. Defaults to empty string when the phone never
    /// sent an `ActiveBlock` (edge case: fresh watch pairing mid-rest).
    public struct RestPayload: Equatable, Sendable {
        public let endsAt: Date
        public let exerciseName: String

        public init(endsAt: Date, exerciseName: String) {
            self.endsAt = endsAt
            self.exerciseName = exerciseName
        }
    }

    // MARK: - Observable state

    /// The current face. Read by the view; mutated only by the
    /// subscription loop in `start()`.
    public private(set) var face: Face = .idle

    public private(set) var metricError: HealthKitError?

    // MARK: - Tracking state
    //
    // Context the view model needs to translate a tap into the right
    // outbound message. Populated from inbound `.pushActiveBlock` /
    // `.pushRestTimer` payloads and reset on `.pushWorkoutComplete`.

    /// The last-active block, if any. Used to hold onto the exercise
    /// name across the active→rest transition (the rest message does
    /// not carry the exercise name) and to resolve tap → setStarted /
    /// setEnded with the correct workout-item ID.
    private var lastActive: LastActiveContext?
    private var latestHeartRateBPM: Int?
    private var metricTask: Task<Void, Never>?

    /// Minimal per-item context the view model holds between messages.
    /// Minimal per-item context sent by the phone with each active payload.
    /// The phone remains authoritative, but the watch echoes this ID back so
    /// tap messages can be matched to the active primitive slot without a
    /// placeholder identity.
    private struct LastActiveContext: Equatable, Sendable {
        let workoutItemID: UUID
        let setIndex: Int
        let exerciseName: String
    }

    // MARK: - Dependencies

    private let bridge: any WatchBridge
    private let metricSource: (any WorkoutMetricSource)?

    // MARK: - Init

    public init(
        bridge: any WatchBridge,
        metricSource: (any WorkoutMetricSource)? = nil
    ) {
        self.bridge = bridge
        self.metricSource = metricSource
    }

    // MARK: - Lifecycle

    /// Subscribe to the bridge's inbound stream. Runs until the stream
    /// terminates (bridge `finish()` call, app termination, etc.). Call
    /// once per view-model lifetime — typically from a SwiftUI `.task`
    /// modifier so cancellation tears down with the view.
    public func start() async {
        defer {
            metricTask?.cancel()
        }
        for await message in bridge.messages() {
            handle(message)
        }
        await metricSource?.stop()
    }

    /// Handle a tap on whichever face is currently rendering. Idle taps
    /// are no-ops. See class header for the send-and-forget rationale.
    public func tap() {
        switch face {
        case .idle:
            return
        case .active:
            sendSetStarted()
        case .rest:
            sendSetEnded()
        }
    }

    // MARK: - Inbound routing

    private func handle(_ message: WatchMessage) {
        switch message {
        case .pushActiveBlock(let payload):
            applyActiveBlock(payload)
        case .pushRestTimer(let endsAt):
            applyRestTimer(endsAt: endsAt)
        case .pushWorkoutComplete:
            applyWorkoutComplete()
        case .setStarted, .setEnded, .quickLog:
            // Watch→phone messages. The watch is not the target; drop.
            return
        }
    }

    private func applyActiveBlock(_ payload: ActiveBlockPayload) {
        ensureMetricStreamStarted()
        let active = ActivePayload(
            exerciseName: payload.exerciseName,
            prescription: payload.prescription,
            setNumber: payload.setNumber,
            setCount: payload.setCount,
            targetRir: payload.targetRir,
            heartRateBPM: latestHeartRateBPM
        )
        lastActive = LastActiveContext(
            workoutItemID: payload.workoutItemID,
            setIndex: payload.setNumber,
            exerciseName: payload.exerciseName
        )
        face = .active(active)
    }

    private func applyRestTimer(endsAt: Date) {
        let name = lastActive?.exerciseName ?? ""
        face = .rest(RestPayload(endsAt: endsAt, exerciseName: name))
    }

    private func applyWorkoutComplete() {
        lastActive = nil
        latestHeartRateBPM = nil
        metricTask?.cancel()
        metricTask = nil
        // swiftlint:disable:next no_direct_task_unstructured
        Task { [metricSource] in
            await metricSource?.stop()
        }
        face = .idle
    }

    // MARK: - Metrics

    private func ensureMetricStreamStarted() {
        guard metricTask == nil else { return }
        // swiftlint:disable:next no_direct_task_unstructured
        metricTask = Task { @MainActor [weak self] in
            await self?.startMetricStreamIfAvailable()
        }
    }

    private func startMetricStreamIfAvailable() async {
        guard let metricSource else { return }
        do {
            let events = try await metricSource.start()
            for await event in events {
                guard !Task.isCancelled else { break }
                applyMetricEvent(event)
            }
        } catch let error as HealthKitError {
            metricError = error
        } catch {
            metricError = .queryFailed(String(describing: error))
        }
    }

    private func applyMetricEvent(_ event: WorkoutMetricEvent) {
        guard case .metric(let tick) = event else { return }
        guard let bpm = tick.heartRateBPM else { return }
        latestHeartRateBPM = Int(bpm.rounded())
        guard case .active(let active) = face else { return }
        face = .active(ActivePayload(
            exerciseName: active.exerciseName,
            prescription: active.prescription,
            setNumber: active.setNumber,
            setCount: active.setCount,
            targetRir: active.targetRir,
            heartRateBPM: latestHeartRateBPM
        ))
    }

    // MARK: - Outbound sends

    private func sendSetStarted() {
        guard let ctx = lastActive else { return }
        let now = Date()
        let message: WatchMessage = .setStarted(
            workoutItemID: ctx.workoutItemID,
            setIndex: ctx.setIndex,
            at: now
        )
        dispatchSend(message)
    }

    private func sendSetEnded() {
        guard let ctx = lastActive else { return }
        let now = Date()
        let message: WatchMessage = .setEnded(
            workoutItemID: ctx.workoutItemID,
            setIndex: ctx.setIndex,
            at: now,
            bpmAvg: latestHeartRateBPM,
            bpmMax: latestHeartRateBPM
        )
        dispatchSend(message)
    }

    private func dispatchSend(_ message: WatchMessage) {
        // Detached so the tap returns immediately; errors are swallowed
        // because the bridge queues on unreachable and a malformed
        // payload is a programmer error (caught by Codable tests).
        Task.detached { [bridge] in
            try? await bridge.send(message)
        }
    }
}

// MARK: - Route mapping helper
//
// Kept as a free function so previews and tests can reason about the
// mapping without instantiating the view model. `SessionState.Route`
// is the iOS-side concept; the watch does not hold a SessionState, but
// exposing the mapping here makes the intent explicit and gives us a
// single place to extend when new faces land in v1.1+.
public enum WatchFaceRoute {
    /// Translate a phone-side `SessionState.Route` to the watch face
    /// that should render for it. Not used on the hot path (the watch
    /// picks faces from incoming messages), but useful for tests and
    /// shell debugging.
    public static func face(for route: SessionState.Route) -> WatchFacesViewModel.Face {
        switch route {
        case .today, .transition, .complete:
            return .idle
        case .active, .rest:
            // The watch needs a payload to show active/rest, which it
            // only gets via the inbound message. Callers that need the
            // actual face should listen on the bridge; this helper
            // collapses the "no payload yet" case to `.idle`.
            return .idle
        }
    }
}
