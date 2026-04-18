// Protocols.swift
//
// Public API surface of the HealthKitBridge package. Features and the app
// shell consume these protocols; nothing outside this package imports
// HealthKit. FF-13 enforces that at lint time via `.swiftlint.yml`.

import Foundation

// MARK: - Values

/// A single heart-rate reading during a live workout session.
/// `bpm` is rounded to the nearest beat-per-minute; HealthKit reports in
/// `count/min` doubles but the domain stores `Int` (see SetLog.hrAvgBpm).
public struct HeartRateSample: Sendable, Equatable {
    public let timestamp: Date
    public let bpm: Int

    public init(timestamp: Date, bpm: Int) {
        self.timestamp = timestamp
        self.bpm = bpm
    }
}

// MARK: - Errors

public enum HealthKitError: Error, Equatable, Sendable {
    /// HealthKit is not available on this platform (e.g. macOS, iPad without
    /// the capability). Callers should treat this as "no HR / body-weight
    /// data available" rather than an error to surface.
    case notAvailable
    /// The user hasn't granted the required authorization. Callers should
    /// prompt via `HealthAuthorization.requestAuthorization()` and retry.
    case notAuthorized
    /// HealthKit itself failed the underlying query. Message is for logs.
    case queryFailed(String)
}

// MARK: - Protocols

/// Authorization handshake for HR, cadence, and body-mass read access.
/// `isAuthorized` is a best-effort check — HealthKit intentionally does not
/// expose a reliable read-authorization status (for privacy), so callers
/// should treat `true` as "we've asked and the user didn't refuse" and
/// continue to handle query failures gracefully.
public protocol HealthAuthorization: Sendable {
    func requestAuthorization() async throws
    var isAuthorized: Bool { get }
}

/// Subscribes to live heart-rate samples while a workout session is active.
/// The returned stream finishes when `endWorkoutSession()` is called or when
/// the underlying `HKWorkoutSession` ends for any reason.
public protocol HeartRateObserver: Sendable {
    /// Starts an HKWorkoutSession + HKLiveWorkoutBuilder and returns a stream
    /// of HR samples as HealthKit delivers them. The stream is finite: it
    /// terminates cleanly when the session ends.
    func startWorkoutSession() async throws -> AsyncThrowingStream<HeartRateSample, Error>

    /// Ends the active session and finishes the stream. Safe to call if no
    /// session is active.
    func endWorkoutSession() async
}

/// Reads the most recent `bodyMass` sample from HealthKit.
/// Per `docs/prescription.md` § "Bodyweight and weighted bodyweight", the
/// app reads body-weight from `user_parameters` first and falls back to
/// HealthKit when no parameter has been pushed.
public protocol BodyWeightReader: Sendable {
    func latestBodyWeightKg() async throws -> Double?
}
