// FirstRunViewModel.swift
//
// Drives the first-run connection flow: URL + token entry → /api/version
// handshake → persist connection → hand off to the shell. Pattern mirrors
// `TodayViewModel` / `ExecutionViewModel`: `@Observable @MainActor final
// class`, state transitions set via plain property assignments, async
// entry points are regular `func` methods.
//
// Why a dedicated state enum rather than individual booleans:
//   The screen is a finite state machine (welcome → connecting → complete
//   | failed) and SwiftUI views switch on `state`. Individual flags would
//   let the UI drift into impossible combinations ("is loading AND has
//   error"). A single enum stays honest.
//
// Scope boundary — FirstRun validates, AppBootstrap hydrates:
//   FirstRun only fires `GET /api/version` as a cheap "is this a workoutdb
//   server with a valid token" handshake. It does NOT fire `GET
//   /api/sync/pull` — that job belongs to `Shell.AppBootstrap`, which
//   maps DTOs to Domain, writes them to the local cache, and builds the
//   Today + Execution view models. Running the pull here too would be a
//   duplicate network call and a stranding hazard: if this-layer pull
//   succeeded but bootstrap's pull later failed, the user could land on
//   `.empty` with no way back to FirstRun to pick a different server.
//   One owner for the initial pull is the fix.
//
// TokenStore writes happen *only after* /api/version returns 200. We do
// not want to persist a token that produces 401 on every subsequent call.

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
        /// Terminal success — `onComplete` has been invoked and the shell
        /// is expected to route past this screen. The shell's
        /// BootstrapLoadingView takes over from here and owns the first
        /// `/api/sync/pull`.
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
        /// Server returned 401 on `/api/version`. Distinct from
        /// `.unreachable` because per docs/sync.md § "Auth posture" a 401
        /// is "token rejected — re-enter credentials", not a transient
        /// network blip.
        case tokenRejected
        /// Transport-level failure: DNS, timeout, connection refused, or
        /// any non-2xx non-401 HTTP status. Retrying makes sense.
        case unreachable
        /// Body decoded as something other than the expected shape.
        /// Usually means "this URL answered but it's not a workoutdb
        /// server" — fixable by correcting the URL.
        case decode
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
        case .connecting, .complete:
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
    ///
    /// `initialURL` / `initialToken` pre-fill the fields — used by the
    /// "change server" recovery route from `.empty` so Eric doesn't have
    /// to retype a URL he likely wants to edit rather than replace.
    public init(
        tokenStore: any TokenStore,
        transportBuilder: @escaping @Sendable (URL) -> any HTTPTransport,
        onComplete: @escaping @Sendable () -> Void,
        initialURL: String = "",
        initialToken: String = ""
    ) {
        self.tokenStore = tokenStore
        self.transportBuilder = transportBuilder
        self.onComplete = onComplete
        self.decoder = JSONDecoder()
        self.url = initialURL
        self.token = initialToken
    }

    /// Convenience for production callers: always builds a
    /// `URLSessionTransport`. Tests use the primary init with a fake.
    public convenience init(
        tokenStore: any TokenStore,
        onComplete: @escaping @Sendable () -> Void,
        initialURL: String = "",
        initialToken: String = ""
    ) {
        self.init(
            tokenStore: tokenStore,
            transportBuilder: { url in URLSessionTransport(baseURL: url) },
            onComplete: onComplete,
            initialURL: initialURL,
            initialToken: initialToken
        )
    }

    // MARK: - Intent

    /// Kick off the connect → version → save → done pipeline.
    /// Idempotent on failure: the view lets the user edit and call this
    /// again. Every call starts from `.connecting` and runs to a terminal
    /// state (`.complete` or `.failed`).
    ///
    /// Re-entrancy guard: a second tap while the pipeline is mid-flight
    /// (state is `.connecting` or `.complete`) is a no-op. Without this
    /// guard, double-tapping "connect" enqueues two concurrent Task {
    /// await connect() } pipelines that both reach `TokenStore.save` and
    /// `onComplete`, producing duplicate saves. The view layer also
    /// disables the primary button while the flow is in flight; this
    /// guard is the belt-and-braces backstop for test / programmatic
    /// callers.
    public func connect() async {
        switch state {
        case .welcome, .failed:
            break
        case .connecting, .complete:
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

        // Step 2 — persist. The shell's AppBootstrap fires the actual
        // first pull after `onComplete`; see the scope-boundary comment
        // at the top of the file. If the save itself throws we treat it
        // as unreachable so the user can retry.
        do {
            try tokenStore.saveConnection(url: baseURL, token: bearer)
        } catch {
            state = .failed(reason: .unreachable)
            return
        }

        state = .complete
        onComplete()
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
