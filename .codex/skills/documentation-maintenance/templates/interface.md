---
title: "Interface: <API/Event Name>"
last_reviewed: <YYYY-MM-DD>
owner: @username
---

# Interface: <API/Event Name>

<One sentence: what this interface provides.>

## Source of Truth

| Type | Location |
|------|----------|
| OpenAPI spec | `api/openapi.yaml` |
| Proto definitions | `proto/service.proto` |
| JSON Schema | `schemas/event.json` |

## Versioning

**Current version**: v2

**Version policy**:
- Breaking changes → increment major version
- New fields → additive, no version change
- Deprecation → 6-month notice in changelog

**Supported versions**:
| Version | Status | End of Life |
|---------|--------|-------------|
| v2 | Current | — |
| v1 | Deprecated | 2024-06-01 |

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v2/resources` | List resources |
| GET | `/api/v2/resources/{id}` | Get resource |
| POST | `/api/v2/resources` | Create resource |
| PUT | `/api/v2/resources/{id}` | Update resource |
| DELETE | `/api/v2/resources/{id}` | Delete resource |

## Examples

### List Resources

**Request**:
```http
GET /api/v2/resources?limit=10&offset=0 HTTP/1.1
Authorization: Bearer <token>
```

**Response**:
```json
{
  "data": [
    {"id": "abc", "name": "Resource 1"},
    {"id": "def", "name": "Resource 2"}
  ],
  "pagination": {
    "total": 42,
    "limit": 10,
    "offset": 0
  }
}
```

### Create Resource

**Request**:
```http
POST /api/v2/resources HTTP/1.1
Authorization: Bearer <token>
Content-Type: application/json

{
  "name": "New Resource",
  "type": "standard"
}
```

**Success Response** (201):
```json
{
  "id": "ghi",
  "name": "New Resource",
  "type": "standard",
  "created_at": "2024-01-15T10:00:00Z"
}
```

**Error Response** (400):
```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Field 'name' is required",
    "details": [
      {"field": "name", "issue": "required"}
    ]
  }
}
```

## Error Codes

| Code | HTTP Status | Meaning | Retry? |
|------|-------------|---------|--------|
| `VALIDATION_ERROR` | 400 | Invalid input | No |
| `NOT_FOUND` | 404 | Resource doesn't exist | No |
| `RATE_LIMITED` | 429 | Too many requests | Yes (backoff) |
| `INTERNAL_ERROR` | 500 | Server error | Yes (backoff) |

## Change Policy

1. **Proposal**: Open RFC in #api-design
2. **Review**: 2 approvals from API owners
3. **Implementation**: Feature flagged rollout
4. **Notification**: Changelog + email to consumers
5. **Deprecation**: 6-month notice before removal

## Related

- [Feature doc](../features/feature-name.md) — Full feature documentation
- [AGENTS.md](../../src/api/AGENTS.md) — API development conventions
