// FirstRunViewModel.swift
//
// Drives the first-run connection flow: URL + token entry → /api/version
// handshake → first /api/sync/pull → persist and hand off. Pattern mirrors
// `TodayViewModel` / `ExecutionViewModel`: `@Observable @MainActor final
// class`, state transitions set via plain property assignments, async
// entry points are regular `func` methods.
//
// Why a dedicated state enum rather than individual booleans:
//   The screen is a finite state machine (welcome → connecting → syncing
//   → complete | failed) and SwiftUI views switch on `state`. Individual
//   flags would let the UI drift into impossible combinations ("is
//   loading AND has error"). A single enum stays honest.
//
// Why call both /api/version and /api/sync/pull here:
//   - /api/version is the cheap handshake: 401 surfaces immediately and
//     decode failures on it mean "this isn't a workoutdb server".
//   - /api/sync/pull primes the cache so Today has data to render on
//     first entry. Per docs/sync.md § "First-run UX" the first sync is
//     all-or-nothing; crashing mid-pull restarts from scratch on next
//     launch.
//
// TokenStore writes happen *only after* /api/version returns 200. We do
// not want to persist a token that produces 401 on every subsequent call.
//
// PullSummary counts come from the pull response DTO. We decode the
// `workouts` and `exercises` array lengths locally rather than using
// `PullService` — PullService drags in the full domain mapping pipeline
// and we only need two ints here. Kept the decoder forgiving: if the
// shape doesn't match, we flip to .failed(.decode) and the user can retry.

import Foundation
import Sync
import Persistence

@Observable
@MainActor
public final class FirstRunViewModel {

    // MARK: - Public state shape

    /// Where the flow currently sits. Views switch on this.
    public enum State: Equatable, Sendable {
        /// Inputs visible, waiting for the user.
        case welcome
        /// `GET /api/version` in flight.
        case connecting
        /// `GET /api/sync/pull` in flight. Summary populates once the
        /// response decodes; before that the count chip is absent.
        case syncingFirstPull(pulled: PullSummary?)
        /// Terminal success — `onComplete` has been invoked and the shell
        /// is expected to route past this screen.
        case complete
        /// Inline-banner failure. The user remains on the welcome card
        /// with their inputs intact and can retry.
        case failed(reason: FailureReason)
    }

    /// The three failure modes the welcome card surfaces. Copy lives in
    /// the view layer (see `FailureBanner`), not here — the view model
    /// only reports *which* failure happened.
    public enum FailureReason: Error, Equatable, Sendable {
        /// `URL(string:)` failed or the URL carries no host. Validation
        /// runs before any network I/O — we never fire a request at junk
        /// input.
        case invalidURL
        /// Server returned 401 on `/api/version` or `/api/sync/pull`.
        /// Distinct from `.unreachable` because per docs/sync.md § "Auth
        /// posture" a 401 is "token rejected — re-enter credentials",
        /// not a transient network blip.
        case tokenRejected
        /// Transport-level failure: DNS, timeout, connection refused, or
        /// any non-2xx non-401 HTTP status. Retrying makes sense.
        case unreachable
        /// Body decoded as something other than the expected shape.
        /// Usually means "this URL answered but it's not a workoutdb
        /// server" — fixable by correcting the URL.
        case decode
    }

    /// Lightweight counts for the "syncing your program" card. The full
    /// mapped pull lives in Persistence once this package's consumer
    /// wires in the cache write — we deliberately don't hold the mapped
    /// rows on the view model.
    public struct PullSummary: Equatable, Sendable {
        public let sessions: Int
        public let exercises: Int

        public init(sessions: Int, exercises: Int) {
            self.sessions = sessions
            self.exercises = exercises
        }
    }

    // MARK: - Observable properties

    public var state: State = .welcome
    /// Free-form URL input. The view binds `SwiftUI.TextField` here.
    public var url: String = ""
    /// Free-form token input. The view binds `SwiftUI.SecureField` here.
    public var token: String = ""

    /// True while a connect pipeline is mid-flight. Views bind the primary
    /// button's `disabled` to this so the user can't fire a second tap
    /// while the first is still running. Mirrors the re-entrancy guard in
    /// `connect()` — both are needed: the view-side disable prevents the
    /// UX-bad "tap fires but nothing happens" state, and the guard in
    /// `connect()` protects programmatic / test callers.
    public var isConnectInFlight: Bool {
        switch state {
        case .connecting, .syncingFirstPull, .complete:
            return true
        case .welcome, .failed:
            return false
        }
    }

    // MARK: - Dependencies (private, set once at init)

    private let tokenStore: any TokenStore
    private let transportBuilder: @Sendable (URL) -> any HTTPTransport
    private let onComplete: @Sendable () -> Void
    private let decoder: JSONDecoder

    // MARK: - Init

    /// Production-shaped initializer. Callers pass a `TokenStore` (almost
    /// always `TokenStoreImpl`) and a transport *builder* — the URL we
    /// connect to isn't known until the user types it, so we can't take
    /// a pre-built `HTTPTransport`. The builder closure constructs a
    /// `URLSessionTransport` (or a fake in tests) against the entered
    /// base URL.
    public init(
        tokenStore: any TokenStore,
        transportBuilder: @escaping @Sendable (URL) -> any HTTPTransport,
        onComplete: @escaping @Sendable () -> Void
    ) {
        self.tokenStore = tokenStore
        self.transportBuilder = transportBuilder
        self.onComplete = onComplete
        self.decoder = JSONDecoder()
    }

    /// Convenience for production callers: always builds a
    /// `URLSessionTransport`. Tests use the primary init with a fake.
    public convenience init(
        tokenStore: any TokenStore,
        onComplete: @escaping @Sendable () -> Void
    ) {
        self.init(
            tokenStore: tokenStore,
            transportBuilder: { url in URLSessionTransport(baseURL: url) },
            onComplete: onComplete
        )
    }

    // MARK: - Intent

    /// Kick off the connect → version → pull → save → done pipeline.
    /// Idempotent on failure: the view lets the user edit and call this
    /// again. Every call starts from `.connecting` and runs to a terminal
    /// state (`.complete` or `.failed`).
    ///
    /// Re-entrancy guard: a second tap while the pipeline is mid-flight
    /// (state is `.connecting`, `.syncingFirstPull`, or `.complete`) is a
    /// no-op. Without this guard, double-tapping "connect" enqueues two
    /// concurrent Task { await connect() } pipelines that both reach
    /// `TokenStore.save` and `onComplete`, producing duplicate saves and
    /// duplicate pulls. The view layer also disables the primary button
    /// while the flow is in flight; this guard is the belt-and-braces
    /// backstop for test / programmatic callers.
    public func connect() async {
        switch state {
        case .welcome, .failed:
            break
        case .connecting, .syncingFirstPull, .complete:
            return
        }
        guard let baseURL = validatedURL() else {
            state = .failed(reason: .invalidURL)
            return
        }
        let bearer = token.trimmingCharacters(in: .whitespacesAndNewlines)

        state = .connecting
        let transport = transportBuilder(baseURL)

        // Step 1 — /api/version handshake. Any failure flips us to
        // .failed and returns; TokenStore is untouched.
        switch await fetchVersion(transport: transport, bearerToken: bearer) {
        case .failure(let reason):
            state = .failed(reason: reason)
            return
        case .success:
            break
        }

        // Step 2 — persist. Writing before the pull means the pair
        // survives a mid-pull crash (per docs/sync.md § "First-sync
        // crash recovery" — the connection string persists; the
        // partial cache is cleared). If the save itself throws we treat
        // it as unreachable so the user can retry.
        do {
            try tokenStore.saveConnection(url: baseURL, token: bearer)
        } catch {
            state = .failed(reason: .unreachable)
            return
        }

        // Step 3 — first pull. Report counts as soon as we have them.
        state = .syncingFirstPull(pulled: nil)
        switch await fetchFirstPull(transport: transport, bearerToken: bearer) {
        case .success(let summary):
            state = .syncingFirstPull(pulled: summary)
            state = .complete
            onComplete()
        case .failure(let reason):
            state = .failed(reason: reason)
        }
    }

    /// Shorthand for "user tapped retry after a failure." Semantically
    /// identical to `connect()` — kept as its own entry point so a
    /// future UI can differentiate (e.g. a slightly different analytics
    /// event) without touching the view.
    public func retry() async {
        await connect()
    }

    // MARK: - Private

    /// Normalize + validate the URL input. Accepts lowercase hostnames
    /// with or without a trailing slash; rejects empty, missing-scheme,
    /// or hostless URLs. Returning `nil` flips state to `.invalidURL`.
    private func validatedURL() -> URL? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let parsed = URL(string: trimmed) else { return nil }
        // A bare "foo.bar" parses as a URL but has no scheme; filter.
        guard let scheme = parsed.scheme, !scheme.isEmpty else { return nil }
        guard let host = parsed.host, !host.isEmpty else { return nil }
        return parsed
    }

    /// Fire `GET /api/version`. Success when the response is 2xx and the
    /// body decodes to `VersionProbe`. We don't actually use the decoded
    /// value — decoding it just proves the server is a workoutdb server,
    /// not some other host at that URL that happens to 200 a bearer.
    private func fetchVersion(
        transport: any HTTPTransport,
        bearerToken: String
    ) async -> Result<Void, FailureReason> {
        let response: HTTPResponse
        do {
            response = try await transport.get(
                path: "/api/version",
                query: [],
                bearerToken: bearerToken
            )
        } catch let err as SyncError {
            return .failure(mapSyncError(err))
        } catch {
            return .failure(FailureReason.unreachable)
        }

        switch response.status {
        case 200...299:
            break
        case 401:
            return .failure(FailureReason.tokenRejected)
        default:
            return .failure(FailureReason.unreachable)
        }

        // Decode as a sanity check; the value is discarded.
        do {
            _ = try decoder.decode(VersionProbe.self, from: response.body)
            return .success(())
        } catch {
            return .failure(FailureReason.decode)
        }
    }

    /// Fire `GET /api/sync/pull` (no `since`) and summarize. We only read
    /// the two count fields — we do not map DTOs to Domain here. The
    /// shell's real sync path does that on subsequent pulls.
    private func fetchFirstPull(
        transport: any HTTPTransport,
        bearerToken: String
    ) async -> Result<PullSummary, FailureReason> {
        let response: HTTPResponse
        do {
            response = try await transport.get(
                path: "/api/sync/pull",
                query: [],
                bearerToken: bearerToken
            )
        } catch let err as SyncError {
            return .failure(mapSyncError(err))
        } catch {
            return .failure(FailureReason.unreachable)
        }

        switch response.status {
        case 200...299:
            break
        case 401:
            return .failure(FailureReason.tokenRejected)
        default:
            return .failure(FailureReason.unreachable)
        }

        do {
            let probe = try decoder.decode(PullProbe.self, from: response.body)
            return .success(PullSummary(
                sessions: probe.workouts.count,
                exercises: probe.exercises.count
            ))
        } catch {
            return .failure(FailureReason.decode)
        }
    }

    /// Map Sync's error vocabulary to FirstRun's narrower one. Sync
    /// distinguishes `.tokenRejected`, `.network`, `.server`, `.decode`,
    /// `.encode`; FirstRun only needs the three branches the user can
    /// act on.
    private func mapSyncError(_ err: SyncError) -> FailureReason {
        switch err {
        case .tokenRejected: return .tokenRejected
        case .network: return .unreachable
        case .server: return .unreachable
        case .decode: return .decode
        case .encode: return .unreachable
        }
    }
}

// MARK: - Decoding probes

/// Minimal shape of `GET /api/version`. We only care that it decodes —
/// the actual value is ignored. Matching the server's `VersionInfo` keys
/// (snake_case) via `CodingKeys`.
private struct VersionProbe: Decodable {
    let serverVersion: String?

    private enum CodingKeys: String, CodingKey {
        case serverVersion = "server_version"
    }
}

/// Minimal shape of `GET /api/sync/pull` — just enough to count sessions
/// and exercises. We decode only two arrays; everything else on the
/// response is ignored until the real sync path takes over.
private struct PullProbe: Decodable {
    let workouts: [PullProbeEmpty]
    let exercises: [PullProbeEmpty]
}

private struct PullProbeEmpty: Decodable {}
