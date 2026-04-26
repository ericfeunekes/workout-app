---
title: "Feature: <Feature Name>"
last_reviewed: <YYYY-MM-DD>
owner: @username
---

# Feature: <Feature Name>

<One sentence: what this feature does and for whom.>

## Scope

**What it does**:
- Capability 1
- Capability 2

**What it doesn't do**:
- Out of scope 1
- Out of scope 2

## User Journeys

### Journey 1: <Primary Use Case>

1. User does X
2. System responds with Y
3. User sees Z

### Journey 2: <Secondary Use Case>

1. User does A
2. System responds with B

## Architecture

<!-- Link to diagram or describe key components -->

```
[Client] → [API Gateway] → [Service] → [Database]
                              ↓
                         [Event Bus]
```

**Key components**:
| Component | Responsibility |
|-----------|----------------|
| Service A | Handles X |
| Service B | Processes Y |

## API Contracts

### Request

```http
POST /api/v1/resource HTTP/1.1
Content-Type: application/json

{
  "field": "value"
}
```

### Success Response

```json
{
  "id": "abc123",
  "status": "created",
  "created_at": "2024-01-15T10:00:00Z"
}
```

### Error Response

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Field 'name' is required"
  }
}
```

## Limits

| Limit | Value | When Exceeded |
|-------|-------|---------------|
| Rate limit | 100 req/min | 429 Too Many Requests |
| Payload size | 1 MB | 413 Payload Too Large |
| Timeout | 30s | 504 Gateway Timeout |

## Failure Modes

| Failure | Detection | Impact | Mitigation |
|---------|-----------|--------|------------|
| DB unavailable | Health check fails | Feature disabled | Retry with backoff |
| Upstream timeout | Latency >30s | Degraded response | Circuit breaker |

See [playbook](../runbooks/feature-name-playbook.md) for incident response.

## Telemetry

**Metrics**:
- `feature.requests.total` — Request count
- `feature.latency.p99` — 99th percentile latency

**Logs**:
- `feature.created` — Successful creation
- `feature.failed` — Failure with reason

**Dashboard**: [Link](url)

## Feature Flags

| Flag | Purpose | Default |
|------|---------|---------|
| `feature_x_enabled` | Kill switch | `true` |
| `feature_x_v2` | New implementation | `false` |

## Related

- [AGENTS.md](../../src/feature/AGENTS.md) — Conventions for this feature
- [ADR-NNN](../decisions/ADR-NNN.md) — Why we built it this way
