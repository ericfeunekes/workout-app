# API Security (Generalizable Patterns)

Apply this checklist for HTTP APIs and service-to-service endpoints (including internal APIs).

## Core Invariants

### Object-Level Authorization (BOLA)

- Treat resource identifiers (`id`, `account_id`, `org_id`, `tenant_id`) from the caller as untrusted.
- Enforce authorization at the point of data access:
  - Filter queries by the authenticated principal/tenant (server-derived), not by caller-provided tenant fields.
  - Validate that each requested object belongs to the authenticated principal/tenant before returning or mutating it.
- Prefer consistent guardrails:
  - Use a single authorization primitive in a shared layer (dependency/middleware/repository wrapper) to reduce missed checks.

### Function-Level Authorization (BFLA)

- Apply explicit allowlists for privileged actions (admin operations, exports, billing, user management).
- Do not rely on “UI hiding” or client-side gating as authorization.
- Treat “mode” flags (e.g. `is_admin`, `run_as`, `role=...`) as untrusted input unless cryptographically asserted and authorized.

### Property-Level Authorization (BOPLA / Mass Assignment)

- Allowlist writable fields for update endpoints (deny-by-default).
- Allowlist readable fields for responses when sensitive fields exist.
- Validate nested objects and arrays explicitly; reject unexpected fields.

### Resource Consumption & Abuse

- Bound every untrusted input dimension:
  - Pagination (`limit`/`page_size`) upper bounds.
  - Query complexity and filters (avoid unbounded “search everything” endpoints).
  - File sizes, request body size, and upload limits.
  - Concurrency and job fan-out limits for async workloads.
- Add protective controls for expensive operations:
  - Rate limits and quotas per user/tenant.
  - Timeouts on outbound HTTP/database calls.
  - Circuit breakers for dependency failures (avoid cascading retries).

### Sensitive Business Flows

- Add step-up protections for high-value actions:
  - Re-authentication, MFA, confirmations, and idempotency keys where applicable.
  - Explicit user intent checks (especially for irreversible actions).
- Prevent automation abuse:
  - Require throttles/cooldowns and anomaly detection hooks for flows like password reset, bulk export, and invite spam.

### Safe Consumption of Upstream APIs

- Treat upstream responses as untrusted:
  - Validate response schemas and status handling.
  - Avoid blindly proxying upstream errors/body to clients (information leakage).
- Constrain outbound requests:
  - Allowlist domains and URL schemes when caller influences destinations.
  - Apply timeouts, size limits, redirect limits, and DNS/IP blocking where applicable.

## Verification Questions (Audit Checklist)

- Where are object-level checks enforced, and are they impossible to bypass (including list endpoints)?
- Is tenant/principal derived server-side (not caller-provided), and is it enforced in queries/caches/joins?
- Are privileged actions guarded by explicit authorization (function-level) and not by UI-only checks?
- Are update endpoints deny-by-default for writable fields (no mass assignment)?
- Are limits/quotas/timeouts in place for endpoints that can be abused for cost or DoS?
- Are upstream calls constrained and validated (timeouts, allowlists, schema validation)?

## See Also

- `references/auth_boundaries.md`
- `references/input-output/ssrf.md`
- `references/input-output/file-upload.md`
- `references/input-output/cors.md`
