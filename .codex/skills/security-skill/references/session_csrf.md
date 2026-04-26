# Sessions & CSRF (Generalizable Patterns)

Apply this checklist for browser-based apps that use cookies/sessions (including SPAs backed by cookie auth).

## Session Invariants

- Treat the session identifier as a secret:
  - Use unpredictable, high-entropy session IDs.
  - Never place session IDs in URLs.
  - Never log session IDs or auth cookies.
- Set safe cookie attributes:
  - `HttpOnly` for auth/session cookies.
  - `Secure` in production (HTTPS only).
  - `SameSite=Lax` by default; use `SameSite=None; Secure` only when cross-site is required and understood.
  - Narrow `Domain` and `Path` as much as possible.
- Rotate session identifiers:
  - Rotate on login.
  - Rotate on privilege change (role/tenant switch).
  - Invalidate on logout.
- Expire and revoke:
  - Set reasonable idle and absolute timeouts.
  - Ensure server-side invalidation exists (not just client deletion).
- Prevent session fixation:
  - Do not accept caller-provided session IDs.
  - Do not “upgrade” an anonymous session to authenticated without rotation.

## CSRF Invariants (When Cookies Are Used)

- Assume cookie-authenticated endpoints are CSRF-reachable unless proven otherwise.
- Require a CSRF defense for state-changing requests:
  - Use synchronizer token pattern (server-issued CSRF token stored server-side and verified on POST/PUT/PATCH/DELETE).
  - Or use double-submit cookie pattern where appropriate (validate token + origin).
- Validate origin signals:
  - Prefer validating `Origin` on state-changing requests (fail closed if missing where feasible).
  - Fall back to strict `Referer` validation when `Origin` is absent (fail closed; allow only expected origins).
- Avoid “CSRF by design” footguns:
  - Do not treat `SameSite` as the only CSRF control for high-value actions.
  - Do not allow `application/json` to bypass CSRF checks if cookies are sent.
  - Do not allow GET requests to cause state changes.

## CORS and CSRF Interaction

- Do not use CORS as a CSRF defense.
- If cookies are used, avoid permissive CORS:
  - Never combine wildcard origins with credentialed requests.
  - Never reflect origins without strict allowlist validation.
  - Set `Vary: Origin` when responding dynamically.

## Verification Questions (Audit Checklist)

- Are auth/session cookies `HttpOnly`, `Secure`, and `SameSite` set appropriately?
- Is the session rotated on login and privilege change?
- Do state-changing endpoints enforce CSRF checks (token + origin/referrer validation)?
- Are any state-changing actions reachable via GET?
- Are CORS settings compatible with cookie usage (no wildcard + credentials, no origin reflection)?

## See Also

- `references/input-output/cors.md`
- `references/auth_boundaries.md`
