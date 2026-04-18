// SyncError.swift
//
// The error vocabulary Sync speaks. Intentionally narrow — callers branch on
// the case, not on a raw `Error`. `tokenRejected` is separate from `server`
// because per `docs/sync.md` § "Auth posture" a 401 is a distinct condition
// that pauses the push queue; silent retry does not apply.

import Foundation

public enum SyncError: Error, Equatable, Sendable {
    /// Transport-level failure — DNS, timeout, connection refused. Message is
    /// a short human-readable description for logs; callers should not parse
    /// it.
    case network(String)
    /// HTTP 401 from any endpoint. Distinct from `server(401, _)` so callers
    /// can pattern-match on just this case.
    case tokenRejected
    /// Any non-2xx status that isn't 401. `message` is the server's body if
    /// decodable as UTF-8; otherwise nil.
    case server(status: Int, message: String?)
    /// Response body could not be decoded into the expected DTO. Retrying is
    /// pointless — the server is sending garbage.
    case decode(String)
    /// Outgoing body could not be encoded. Indicates a programmer error, not
    /// a transient failure.
    case encode(String)
}
