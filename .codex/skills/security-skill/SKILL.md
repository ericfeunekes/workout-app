---
name: security-skill
description: Use when reviewing code for vulnerabilities, planning security-sensitive features, or triaging issues.
---
# Security Skill

Perform practical, code-oriented security reviews. Produce fix-ready findings with impact, exploit scenario, evidence, remediation, and verification. This skill supports comprehensive audits, security-aware feature planning, vulnerability triage, and quick spot checks.

## When To Use

**Security Reviews:**
- Full security review of a repo, service, or module
- Auditing authn/authz, session management, access control
- Reviewing dangerous data flows (user input → DB, shell, templates, HTTP clients)
- Reviewing LLM/agent surfaces for prompt injection, tool abuse, output rendering

**Feature Planning:**
- Planning features that handle user input or external data
- Adding authentication/authorization to endpoints
- Integrating with external APIs or upstream services
- Building LLM/agent features with tool access

**Triage & Quick Checks:**
- Evaluating reported vulnerabilities (bug bounty, SAST, CVE)
- Spot-checking code before PR merge

## Scope

**In Scope:**
- Application security (injection, auth, input validation, output encoding)
- OAuth/OIDC implementation (PKCE, JWT validation, token handling)
- Sessions and CSRF for browser-based apps
- API security patterns (OWASP API Top 10 as generalizable checks)
- LLM/Agent safety (prompt injection, tool abuse, output rendering)
- File upload, SSRF, CORS, XSS prevention

**Out of Scope:**
- Cloud infrastructure security (IAM, Key Vault, IaC) → separate skill
- Supply chain security (dependencies, CI hardening) → separate skill
- Network security (TLS, firewall) → separate skill

---

## Workflow Selection

| Situation | Workflow |
|-----------|----------|
| Comprehensive audit of repo/service | Workflow A: Full Security Review |
| Planning a feature with security implications | Workflow B: Security-Aware Planning |
| Evaluating a reported vulnerability | Workflow C: Vulnerability Triage |
| Quick check before PR merge | Workflow D: Quick Scan |

---

## Workflow A: Full Security Review

### Step 0: Initialize Notes File

Create `scratch/_security_notes.md` (or user-specified path) using this template:

```markdown
# Security Review: [target]

**Date:** YYYY-MM-DD
**Target:** [repo/service/module path]
**Scope:** [included/excluded areas]
**Outcome:** [review only / remediation PRs / threat model]

## Phase 1: Context Gathering
- [ ] Map entry points (routes, CLI, handlers, jobs)
- [ ] Identify crown jewels (PII, tokens, money movement, admin actions)
- [ ] Document existing security controls
- [ ] For LLM systems: map untrusted inputs, sensitive data, available tools

**Observations:**

## Phase 2: Boundary Validation
- [ ] Auth boundaries (`references/auth_boundaries.md`)
- [ ] LLM trust boundaries (`references/llm_trust_boundaries.md`)
- [ ] Session/CSRF (`references/session_csrf.md`) - if cookies used
- [ ] API security (`references/api_security.md`)

**Observations:**

## Phase 3: Automated Scans
- [ ] Run quick_scan.py
- [ ] Run security_scan.py (Semgrep)
- [ ] Review output, mark leads for manual review

**Scan Leads:**

## Phase 4: Manual Review

## Phase 5: Findings

## Phase 6: Remediation
```

### Step 1: Gather Context

Map the security-relevant architecture:

1. **Entry points:** HTTP routes, CLI commands, message handlers, scheduled jobs, admin panels
2. **Trust boundaries:** Where does untrusted data enter? Where is sensitive data stored?
3. **Existing controls:** Auth middleware, RBAC, input validation, CSRF protection, WAF
4. **LLM systems:** Retrieval sources, tool surfaces, output rendering locations

After each discovery, update notes: check off item, add observation.

### Step 2: Validate Boundaries

Apply boundary checklists in order:

1. Read `references/auth_boundaries.md` → verify identity source, header trust, authz checks
2. Read `references/llm_trust_boundaries.md` → verify untrusted input isolation, action constraints
3. Read `references/session_csrf.md` (if cookies exist) → verify CSRF protection
4. Read `references/api_security.md` → verify object-level authz, mass assignment protection

For each checklist: check the box, note violations or concerns.

### Step 3: Run Automated Scans

```bash
# Lightweight pattern scan (secrets, dangerous sinks)
uv run skills/security-skill/scripts/quick_scan.py /path/to/repo

# AST-based security scan
uv run skills/security-skill/scripts/security_scan.py /path/to/repo         # Full
uv run skills/security-skill/scripts/security_scan.py --fast /path/to/repo  # High-priority only
```

Treat results as leads, not findings. Add each lead as a checkbox under "Manual Review".

### Step 4: Manual Review

For each lead:
1. Trace: source (untrusted input) → transformations → sink (dangerous operation)
2. Identify guards: authz checks, allowlists, type constraints, encoding
3. Determine: exploitable / theoretical / false positive

Check off item after review. Add finding or mark as FP.

<manual_review_example>
**Lead:** `subprocess.run(cmd, shell=True)` in `scripts/deploy.py:47`

**Trace:**
- Source: `cmd` built from `os.environ["DEPLOY_TARGET"]`
- Transformation: None
- Sink: subprocess with shell=True

**Guards:**
- Environment variable, not user input
- Only runs in CI context (checked via `CI` env var)

**Verdict:** False positive - input is trusted (CI-controlled env var)
</manual_review_example>

### Step 5: Document Findings

For each confirmed issue, use the finding template (`references/finding_template.md`):

<finding_example>
## Finding: Tenant ID from Request Body Enables Cross-Tenant Data Access

**Severity:** High

**Category:** Authz (BOLA)

**Affected Components:** `api/routes/documents.py:get_documents()`, `api/routes/documents.py:delete_document()`

**Impact:** Authenticated user can access or delete documents belonging to any tenant by modifying `tenant_id` in request body.

**Exploit Scenario:**
1. Attacker authenticates as user in tenant A
2. Attacker sends GET /documents with `{"tenant_id": "tenant_B"}`
3. Server returns tenant B's documents

**Evidence:**
```python
# api/routes/documents.py:42
@router.get("/documents")
async def get_documents(request: DocumentRequest):
    tenant_id = request.tenant_id  # From request body, not token!
    return await db.get_documents(tenant_id=tenant_id)
```

**Root Cause:** Tenant ID derived from untrusted request body instead of authenticated token claims.

**Recommended Fix:**
```python
async def get_documents(request: DocumentRequest, user: User = Depends(get_current_user)):
    tenant_id = user.tenant_id  # From validated token
    return await db.get_documents(tenant_id=tenant_id)
```

**Verification:**
```python
def test_cannot_access_other_tenant_documents(client, user_tenant_a):
    response = client.get("/documents", json={"tenant_id": "tenant_b"})
    # Should return only tenant_a documents, ignoring the request body
    assert all(doc["tenant_id"] == "tenant_a" for doc in response.json())
```
</finding_example>

### Step 6: Remediation

For each finding:
1. Fix root cause (prefer changing types/APIs over adding sanitizers)
2. Add verification test (fails pre-fix, passes post-fix)
3. Update notes with fix status and PR link

---

## Workflow B: Security-Aware Planning

Use when planning features that touch security-sensitive surfaces.

### Step 1: Identify Security Surface

Add to feature plan or notes:

```markdown
## Security Planning: [feature name]

### Security Surface
- User input: [describe inputs and sources]
- External APIs: [list services being integrated]
- Sensitive data: [what PII/secrets/tokens involved]
- Auth requirements: [who can access, required permissions]
- LLM/agent: [if applicable: tools, retrieval, output rendering]
```

### Step 2: Consult Relevant Guides

| Feature Aspect | Reference to Read |
|----------------|-------------------|
| User input → database | `references/injection/sql-injection.md` |
| User input → shell/subprocess | `references/injection/command-injection.md` |
| File uploads | `references/input-output/file-upload.md` |
| External HTTP calls | `references/input-output/ssrf.md` |
| User-provided URLs | `references/input-output/ssrf.md`, `cors.md` |
| Auth endpoints | `references/auth/oauth-pkce.md`, `jwt-validation.md` |
| Session/cookie auth | `references/session_csrf.md` |
| API endpoints | `references/api_security.md` |
| LLM with tools | `references/llm-agent/prompt-injection.md`, `tool-safety.md` |
| LLM output rendering | `references/llm-agent/output-rendering.md` |
| HTML/template output | `references/input-output/xss-prevention.md` |

### Step 3: Document Requirements

Add to feature plan:
- Required controls (parameterized queries, auth checks, input validation)
- Patterns to follow (from guides)
- Anti-patterns to avoid
- Security test cases to add

---

## Workflow C: Vulnerability Triage

Use for evaluating reported vulnerabilities.

### Step 1: Document Report

```markdown
## Triage: [vuln title/ID]

**Source:** [bug bounty / SAST / CVE / internal]
**Reported Severity:** [as reported]
**Affected Component:** [file/endpoint/function]

### Assessment
- [ ] Trace code path from source to sink
- [ ] Identify existing guards
- [ ] Determine exploitability
- [ ] Assess actual impact
```

### Step 2: Confirm or Refute

Trace the vulnerable path:
1. Can untrusted input reach the sink?
2. What guards exist? Are they bypassable?
3. What's the actual impact if exploited?

Verdict: Confirmed / Theoretical / False Positive

### Step 3: Assess Severity

| Priority | Examples |
|----------|----------|
| Critical | RCE, auth bypass, credential exposure |
| High | SQL injection, SSRF, stored XSS, privilege escalation |
| Medium | Reflected XSS, CORS misconfiguration, missing rate limits |
| Low | Missing security headers, verbose errors, weak crypto |

### Step 4: Document and Fix

Use finding template. Recommend fix with verification test.

---

## Workflow D: Quick Scan

Use for fast checks before PR merge.

### Step 1: Run Targeted Scan

```bash
uv run skills/security-skill/scripts/security_scan.py /path/to/changed/files
```

### Step 2: Validate Flagged Patterns

For each pattern flagged:
1. Is the input trusted or untrusted?
2. Is there validation/sanitization?
3. Is it following the safe alternative from `references/dangerous-patterns.md`?

No formal notes file needed unless issues found.

---

## Notes File Practices

### Update Frequency

Update notes after each completed check:
- Check off the box
- Add observation (even if "OK")
- Add new checkboxes for discovered areas

<notes_iteration_example>
**Before review:**
```markdown
## Phase 4: Manual Review
- [ ] File upload endpoint
- [ ] LLM tool permission checks
```

**After reviewing file upload (discovered sub-items):**
```markdown
## Phase 4: Manual Review
- [x] File upload endpoint - uses allowlist, validates magic bytes, OK
- [ ] LLM tool permission checks
  - [ ] Read tool - check path validation
  - [ ] Write tool - check destination restrictions
  - [ ] Execute tool - check command allowlist
```

**After reviewing LLM tools (found issue):**
```markdown
## Phase 4: Manual Review
- [x] File upload endpoint - uses allowlist, validates magic bytes, OK
- [x] LLM tool permission checks
  - [x] Read tool - FINDING: no path validation, can read /etc/passwd
  - [x] Write tool - OK, restricted to sandbox dir
  - [x] Execute tool - OK, strict command allowlist
```
</notes_iteration_example>

---

## Reference Search Patterns

For large reference files, use grep to find specific patterns:

```bash
# Find SQL injection patterns
rg "parameterized|bind.*param|text\(" references/injection/

# Find auth boundary patterns
rg "identity|principal|tenant" references/auth_boundaries.md

# Find LLM safety patterns
rg "trifecta|tool.*permission|sanitiz" references/llm-agent/

# Find XSS patterns
rg "innerHTML|dangerously|DOMPurify" references/input-output/xss-prevention.md
```

---

## Safety Guardrails

- Do not claim an exploit works without evidence (PoC, test, or clear code path)
- Redact secret values; point to file:line locations only
- Prefer low-blast-radius fixes and incremental PRs
- Treat LLM output as untrusted when rendering HTML/Markdown
- Follow repository AGENTS.md and existing error-handling patterns

---

## Bundled Resources

### Scripts
| Script | Purpose | Run Command |
|--------|---------|-------------|
| `scripts/security_scan.py` | Semgrep AST-based scan | `uv run skills/security-skill/scripts/security_scan.py <path>` |
| `scripts/quick_scan.py` | Ripgrep pattern scan | `uv run skills/security-skill/scripts/quick_scan.py <path>` |

### Boundary Checklists (read during Phase 2)
- `references/auth_boundaries.md` – identity, headers, authz
- `references/llm_trust_boundaries.md` – untrusted inputs, actions, output
- `references/session_csrf.md` – cookies, CSRF protection
- `references/api_security.md` – BOLA, BFLA, mass assignment

### Detailed Guides (read as needed)

**Injection:**
- `references/injection/sql-injection.md`
- `references/injection/command-injection.md`
- `references/injection/deserialization.md`

**Authentication:**
- `references/auth/oauth-pkce.md`
- `references/auth/jwt-validation.md`

**LLM/Agent:**
- `references/llm-agent/prompt-injection.md`
- `references/llm-agent/tool-safety.md`
- `references/llm-agent/output-rendering.md`

**Input/Output:**
- `references/input-output/file-upload.md`
- `references/input-output/ssrf.md`
- `references/input-output/cors.md`
- `references/input-output/xss-prevention.md`

### Quick Reference
- `references/dangerous-patterns.md` – pattern lookup table
- `references/finding_template.md` – finding documentation format

## Related Skills

- review
- release-engineering
