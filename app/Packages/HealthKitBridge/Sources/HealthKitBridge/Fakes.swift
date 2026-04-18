// Fakes.swift
//
// In-memory doubles for unit tests. Exported from the HealthKitBridge module
// so Features tests can wire them without reimplementing the protocols.
//
// These are the same types used by `HealthKitBridgeTests` in this package.

import Foundation

// MARK: - FakeHealthAuthorization

/// Flips `isAuthorized` to `true` when `requestAuthorization()` is called —
/// unless the caller primed `shouldFail` with an error to throw.
public final class FakeHealthAuthorization: HealthAuthorization, @unchecked Sendable {
    private let state = FakeAuthState()

    public init(initiallyAuthorized: Bool = false, shouldFailWith: HealthKitError? = nil) {
        state.isAuthorized = initiallyAuthorized
        state.shouldFailWith = shouldFailWith
    }

    public var isAuthorized: Bool { state.isAuthorized }

    public func requestAuthorization() async throws {
        if let err = state.shouldFailWith {
            throw err
        }
        state.isAuthorized = true
    }
}

// Backing storage for the fake. Reference type so the struct-free protocol
// stays `Sendable` while the auth-flipping mutation is safe under
// `@unchecked Sendable`. Access is serialized by test code running a single
// async task at a time.
private final class FakeAuthState: @unchecked Sendable {
    nonisolated(unsafe) var isAuthorized: Bool = false
    nonisolated(unsafe) var shouldFailWith: HealthKitError?
}

// MARK: - FakeHeartRateObserver

/// Yields a pre-supplied list of HR samples when the session starts, then
/// finishes the stream. `endWorkoutSession()` records the call and finishes
/// early if the stream is still active.
public final class FakeHeartRateObserver: HeartRateObserver, @unchecked Sendable {
    private let samples: [HeartRateSample]
    private let shouldFailWith: HealthKitError?
    private let storage = FakeObserverStorage()

    public init(
        scripted samples: [HeartRateSample] = [],
        shouldFailWith: HealthKitError? = nil
    ) {
        self.samples = samples
        self.shouldFailWith = shouldFailWith
    }

    /// Number of times `endWorkoutSession()` has been called.
    public var endCallCount: Int { storage.endCallCount }

    public func startWorkoutSession() async throws -> AsyncThrowingStream<HeartRateSample, Error> {
        if let err = shouldFailWith {
            throw err
        }
        let scripted = samples
        return AsyncThrowingStream { cont in
            self.storage.continuation = cont
            for sample in scripted {
                cont.yield(sample)
            }
            cont.finish()
        }
    }

    public func endWorkoutSession() async {
        storage.endCallCount += 1
        storage.continuation?.finish()
        storage.continuation = nil
    }
}

private final class FakeObserverStorage: @unchecked Sendable {
    nonisolated(unsafe) var continuation: AsyncThrowingStream<HeartRateSample, Error>.Continuation?
    nonisolated(unsafe) var endCallCount: Int = 0
}

// MARK: - FakeBodyWeightReader

/// Returns a fixed body-weight value. Set to `nil` to simulate "no sample
/// on file" (callers should then fall back to `user_parameters`).
public final class FakeBodyWeightReader: BodyWeightReader, @unchecked Sendable {
    private let value: Double?
    private let shouldFailWith: HealthKitError?

    public init(kg: Double?, shouldFailWith: HealthKitError? = nil) {
        self.value = kg
        self.shouldFailWith = shouldFailWith
    }

    public func latestBodyWeightKg() async throws -> Double? {
        if let err = shouldFailWith {
            throw err
        }
        return value
    }
}
