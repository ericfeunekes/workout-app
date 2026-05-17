// ScriptedTransport.swift
//
// Minimal scripted HTTPTransport used by AppBootstrapTests. Returns the
// next queued outcome on each call; exhausting the queue returns a 200
// with empty body (callers that care about mismatched call counts should
// pre-populate with exact scripts).

import Foundation
import Sync

enum ScriptedOutcome: Sendable {
    case ok(Data)
    case status(Int, Data)
    case error(SyncError)
}

actor ScriptedTransportStore {
    private var getOutcomes: [ScriptedOutcome]
    private var postOutcomes: [ScriptedOutcome]
    /// Paths requested via GET, in order. Tests use this to assert that
    /// e.g. AppBootstrap fires exactly one `/api/sync/pull` per run —
    /// the invariant that FirstRun's scope-boundary fix preserves.
    private(set) var getPaths: [String] = []
    private(set) var postPaths: [String] = []
    private(set) var postBodies: [Data] = []

    init(getOutcomes: [ScriptedOutcome], postOutcomes: [ScriptedOutcome]) {
        self.getOutcomes = getOutcomes
        self.postOutcomes = postOutcomes
    }

    func nextGet(path: String) -> ScriptedOutcome {
        getPaths.append(path)
        guard !getOutcomes.isEmpty else { return .ok(Data()) }
        return getOutcomes.removeFirst()
    }

    func nextPost(path: String, body: Data) -> ScriptedOutcome {
        postPaths.append(path)
        postBodies.append(body)
        guard !postOutcomes.isEmpty else { return .ok(Data()) }
        return postOutcomes.removeFirst()
    }

    func snapshotGetPaths() -> [String] { getPaths }
    func snapshotPostPaths() -> [String] { postPaths }
    func snapshotPostBodies() -> [Data] { postBodies }
}

struct ScriptedTransport: HTTPTransport {
    let store: ScriptedTransportStore

    init(getOutcomes: [ScriptedOutcome] = [], postOutcomes: [ScriptedOutcome] = []) {
        self.store = ScriptedTransportStore(
            getOutcomes: getOutcomes,
            postOutcomes: postOutcomes
        )
    }

    func get(
        path: String,
        query: [(String, String)],
        bearerToken: String
    ) async throws -> HTTPResponse {
        try resolve(await store.nextGet(path: path))
    }

    func post(
        path: String,
        body: Data,
        bearerToken: String
    ) async throws -> HTTPResponse {
        try resolve(await store.nextPost(path: path, body: body))
    }

    private func resolve(_ outcome: ScriptedOutcome) throws -> HTTPResponse {
        switch outcome {
        case .ok(let data):
            return HTTPResponse(status: 200, body: data)
        case .status(let status, let data):
            return HTTPResponse(status: status, body: data)
        case .error(let err):
            throw err
        }
    }
}
