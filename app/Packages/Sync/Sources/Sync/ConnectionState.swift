// ConnectionState.swift
//
// Pure enum describing the four user-visible connection states plus an
// intermediate `serverUnreachable`. Kept in its own file to avoid the enum
// living inside `ConnectionManager` — the state is a value that flows out to
// the UI layer via an `AsyncStream`, and the manager is infrastructure around
// it.

import Foundation

/// What the sync layer is currently doing from the UI's perspective. Rendered
/// by the "offline pill" surface documented in `docs/sync.md` § "Offline
/// behavior".
public enum ConnectionState: Sendable, Equatable {
    /// No connectivity or no sync has happened yet this session. The neutral
    /// default.
    case offline
    /// A pull or push is in flight.
    case syncing
    /// Last sync succeeded at the given instant. Pending pushes (if any) will
    /// flush on the next tick.
    case online(lastSyncAt: Date)
    /// Server returned 401. User must rotate the token before further requests
    /// are attempted — see `docs/sync.md` § "Auth posture".
    case tokenRejected
    /// URL resolves but requests repeatedly time out or DNS fails. Distinct
    /// from `.offline` so UI can surface "check your server address" guidance
    /// if we want it later. The manager treats this as equivalent to offline
    /// for retry purposes.
    case serverUnreachable
}
