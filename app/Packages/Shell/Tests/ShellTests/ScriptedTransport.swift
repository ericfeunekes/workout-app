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

    init(getOutcomes: [ScriptedOutcome], postOutcomes: [ScriptedOutcome]) {
        self.getOutcomes = getOutcomes
        self.postOutcomes = postOutcomes
    }

    func nextGet() -> ScriptedOutcome {
        guard !getOutcomes.isEmpty else { return .ok(Data()) }
        return getOutcomes.removeFirst()
    }

    func nextPost() -> ScriptedOutcome {
        guard !postOutcomes.isEmpty else { return .ok(Data()) }
        return postOutcomes.removeFirst()
    }
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
        try resolve(await store.nextGet())
    }

    func post(
        path: String,
        body: Data,
        bearerToken: String
    ) async throws -> HTTPResponse {
        try resolve(await store.nextPost())
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
