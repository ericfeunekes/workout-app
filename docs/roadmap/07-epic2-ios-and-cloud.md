# Epic 2 — iOS 1.0 + Cloud (placeholder, to be detailed later)

## Objective
Ship a production-ready iOS app backed by a minimal, reliable cloud core.

This epic depends on Epic 1 end-state:
- stable schema + migrations
- canonical JSON shapes
- deterministic generator
- seed dataset for prototyping

## Epics inside Epic 2 (high-level)
### 2.1 Core API (read/write)
Scope:
- Templates + blocks/items
- Planned workouts
- Sessions + set logs
- Tags (read-only initially)

Deliverables:
- Minimal REST (or RPC) endpoints with versioned payloads
- Input validation tied to canonical JSON shapes

### 2.2 Auth + user isolation
Scope:
- Single-user or small multi-user support
- Per-user data isolation

Deliverables:
- Auth flow (TBD: device token, email magic link, or OAuth)
- AuthN/AuthZ middleware

### 2.3 Sync + conflict strategy
Scope:
- Offline-first writes on device
- Server reconciliation on sync

Deliverables:
- Sync policy (timestamp + last-write-wins is acceptable v1)
- Minimal conflict resolution rules for core entities

### 2.4 Hosting + ops
Scope:
- Cloud environment
- Backups + monitoring

Deliverables:
- Infrastructure plan (TBD: managed DB + API hosting)
- Automated backups and restore test

### 2.5 iOS 1.0 app
Scope:
- Library browsing
- Today view (planned workout)
- Workout execution + set logging
- Minimal stimulus check-ins
- History

Deliverables:
- iOS UI + networking layer
- Local cache + sync client

## Open questions (defer until Epic 1 is stable)
- Single-user vs multi-user backend?
- API style: REST vs gRPC vs GraphQL?
- Sync model: LWW vs CRDT?
- Hosting stack: managed Postgres vs SQLite + sync service?
