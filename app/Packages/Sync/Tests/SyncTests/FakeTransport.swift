// FakeTransport.swift
//
// A scriptable HTTPTransport for tests. Either returns queued `HTTPResponse`
// values (FIFO) or throws a scripted error. Also records the last request
// for assertion.

import Foundation
import Sync

/// A single scripted outcome.
enum FakeOutcome: Sendable {
    case response(HTTPResponse)
    case throwError(SyncError)
    case throwURLError  // shorthand for "URLSession threw" — maps to SyncError.network
}

/// Recorded call.
struct FakeCall: Sendable, Equatable {
    let method: String
    let path: String
    let query: [String: String]
    let body: Data?
    let bearerToken: String
}

/// The script + log live behind an actor so test harness and async code can
/// interleave safely.
actor FakeTransportStore {
    private var script: [FakeOutcome] = []
    private(set) var calls: [FakeCall] = []

    init(outcomes: [FakeOutcome]) {
        self.script = outcomes
    }

    func append(_ outcome: FakeOutcome) {
        script.append(outcome)
    }

    func next(for call: FakeCall) -> FakeOutcome {
        calls.append(call)
        guard !script.isEmpty else {
            return .response(HTTPResponse(status: 200, body: Data()))
        }
        return script.removeFirst()
    }

    func recordedCalls() -> [FakeCall] {
        calls
    }

    func setScript(_ outcomes: [FakeOutcome]) {
        script = outcomes
    }
}

struct FakeTransport: HTTPTransport {
    let store: FakeTransportStore

    init(outcomes: [FakeOutcome] = []) {
        self.store = FakeTransportStore(outcomes: outcomes)
    }

    func get(
        path: String,
        query: [(String, String)],
        bearerToken: String
    ) async throws -> HTTPResponse {
        let call = FakeCall(
            method: "GET",
            path: path,
            query: Dictionary(uniqueKeysWithValues: query),
            body: nil,
            bearerToken: bearerToken
        )
        let outcome = await store.next(for: call)
        return try resolve(outcome)
    }

    func post(
        path: String,
        body: Data,
        bearerToken: String
    ) async throws -> HTTPResponse {
        let call = FakeCall(
            method: "POST",
            path: path,
            query: [:],
            body: body,
            bearerToken: bearerToken
        )
        let outcome = await store.next(for: call)
        return try resolve(outcome)
    }

    private func resolve(_ outcome: FakeOutcome) throws -> HTTPResponse {
        switch outcome {
        case .response(let r): return r
        case .throwError(let e): throw e
        case .throwURLError:
            throw SyncError.network("simulated URL error")
        }
    }
}
