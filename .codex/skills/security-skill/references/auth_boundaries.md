## Auth Boundaries (Generalizable Patterns)

### Identity Must Be Cryptographically Asserted

- Derive the caller identity from validated authentication artifacts (for example: an ID token/access token validated against issuer, audience, signature, and time claims).
- Treat any “identity” value that arrives as an arbitrary request field (headers, query params, JSON body) as untrusted unless it is:
  - Verified cryptographically, **or**
  - Injected by a trusted gateway within a documented, enforced trust boundary.

### Headers Are Untrusted by Default

- Assume all inbound headers can be attacker-controlled on any public-facing hop.
- Do not accept `user_id`, `email`, `roles`, `tenant`, or “is_admin” claims from request headers unless the system proves the header is minted by a trusted component.

### Trusted-Gateway Header Pattern (When Necessary)

If a gateway/edge injects identity headers:

- Enforce “no direct access”: the service must only be reachable behind the gateway (network ACLs / private endpoint / internal ingress).
- Strip/overwrite at the edge: the gateway must remove any incoming identity headers from the client before setting its own.
- Bind to an authenticated session: the gateway must authenticate the user before minting identity headers.
- Minimize claims: include only what’s required; prefer stable IDs over emails; avoid role lists when possible.
- Treat forwarded token headers as sensitive: do not log them; do not propagate unless explicitly required.

### Authorization Is Separate from Authentication

- Perform authorization checks server-side for every request that touches protected resources (object-level and function-level).
- Prefer “deny by default” and explicit allowlists for privileged operations.
- Prevent confused-deputy bugs: never allow the caller to choose the principal under which an action executes (no `act_as`, `run_as`, `user=` parameters without strong authorization).

### Multi-Tenant Boundaries

- Represent tenant in the authenticated identity (or server-side session), not as a client-provided field.
- Validate tenant boundaries at every resource access (IDs, queries, joins, caches).

### Verification Questions (Audit Checklist)

- What is the single source of truth for `principal_id` / `tenant_id`?
- Can a request reach the service without passing through the identity-asserting component?
- Are identity headers stripped/overwritten at the boundary?
- Are tokens validated (issuer, audience, signature, expiry, nonce/azp where relevant)?
- Is authorization checked for: object-level access, function-level access, and sensitive flows?
