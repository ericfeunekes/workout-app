// Transport.swift
//
// The single URLSession boundary for the entire app. Per FF-13 no other file
// in `app/Packages/**` may `import URLSession` — all network I/O funnels
// through this protocol. Tests swap in `FakeTransport`.
//
// Interface shape:
//   • `HTTPResponse` is a minimal wrapper — status + body Data. No headers,
//     no URLRequest leakage. If we grow a need for response headers, add a
//     property here rather than returning the platform type.
//   • `query` is `[(String, String)]` rather than `[String: String]` so repeat
//     keys (not currently needed for `?since=...` but easy to preserve) and a
//     stable encoding order survive through to the wire. Dictionary ordering
//     is non-deterministic and bit us in a previous iteration.
//   • `bearerToken` is passed per-call instead of held as state. Keeps the
//     transport stateless and makes token rotation trivial — the next call
//     just uses the new token.

import Foundation

/// Minimal HTTP response — what Sync consumers need and nothing more.
public struct HTTPResponse: Sendable, Equatable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// The single I/O surface. Production uses `URLSessionTransport`; tests use
/// `FakeTransport`.
public protocol HTTPTransport: Sendable {
    func get(
        path: String,
        query: [(String, String)],
        bearerToken: String
    ) async throws -> HTTPResponse

    func post(
        path: String,
        body: Data,
        bearerToken: String
    ) async throws -> HTTPResponse
}

/// Production transport backed by `URLSession`. The only file in the codebase
/// that imports `URLSession` (lint-enforced — see FF-13).
///
/// Base URL is stored as a `URL` (parsed once at construction) so each call
/// just appends a path + query. 30-second timeout on individual requests; the
/// retry cadence lives in `ConnectionManager`, not here.
public struct URLSessionTransport: HTTPTransport {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func get(
        path: String,
        query: [(String, String)],
        bearerToken: String
    ) async throws -> HTTPResponse {
        let url = try buildURL(path: path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    public func post(
        path: String,
        body: Data,
        bearerToken: String
    ) async throws -> HTTPResponse {
        let url = try buildURL(path: path, query: [])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await send(request)
    }

    private func buildURL(path: String, query: [(String, String)]) throws -> URL {
        // `URL(string:relativeTo:)` handles the join — the server routes are
        // rooted under `/api/…` so we don't have to care whether `baseURL`
        // carries a trailing slash.
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
            throw SyncError.network("invalid base URL: \(baseURL)")
        }
        // Ensure path stacking is correct. If `baseURL` is `https://host/`, the
        // new path is just `/api/...`; if `baseURL` is `https://host/sub`, we
        // append onto the existing path.
        let existingPath = components.path
        let joinedPath: String
        if existingPath.isEmpty || existingPath == "/" {
            joinedPath = path
        } else if existingPath.hasSuffix("/") && path.hasPrefix("/") {
            joinedPath = existingPath + String(path.dropFirst())
        } else if !existingPath.hasSuffix("/") && !path.hasPrefix("/") {
            joinedPath = existingPath + "/" + path
        } else {
            joinedPath = existingPath + path
        }
        components.path = joinedPath
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        guard let url = components.url else {
            throw SyncError.network("could not build URL for path \(path)")
        }
        return url
    }

    private func send(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SyncError.network("non-HTTP response")
            }
            return HTTPResponse(status: http.statusCode, body: data)
        } catch let urlError as URLError {
            throw SyncError.network("\(urlError.code.rawValue): \(urlError.localizedDescription)")
        } catch let syncError as SyncError {
            throw syncError
        } catch {
            throw SyncError.network(error.localizedDescription)
        }
    }
}
