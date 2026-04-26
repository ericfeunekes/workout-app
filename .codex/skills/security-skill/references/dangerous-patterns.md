# Dangerous Patterns Quick Reference

Fast lookup table for code patterns that warrant security review. Each links to detailed guidance.

## Injection Vulnerabilities

| Pattern | Risk | What to Check | Reference |
|---------|------|---------------|-----------|
| `f"SELECT...{var}"` | SQL Injection | Use parameterized queries | [sql-injection.md](injection/sql-injection.md) |
| `execute(query + var)` | SQL Injection | Use bind parameters | [sql-injection.md](injection/sql-injection.md) |
| `text(f"...")` | SQL Injection | Use `text()` with `:param` syntax | [sql-injection.md](injection/sql-injection.md) |
| `subprocess.run(..., shell=True)` | Command Injection | Use array form, no shell | [command-injection.md](injection/command-injection.md) |
| `os.system(...)` | Command Injection | Use subprocess with array | [command-injection.md](injection/command-injection.md) |
| `["bash", "-c", user_input]` | Command Injection | Never pass user input to shell | [command-injection.md](injection/command-injection.md) |
| `pickle.loads(...)` | Arbitrary Code Exec | Use JSON or validate source | [deserialization.md](injection/deserialization.md) |
| `yaml.load(...)` | Arbitrary Code Exec | Use `yaml.safe_load()` | [deserialization.md](injection/deserialization.md) |
| `eval(...)` | Arbitrary Code Exec | Remove or use `ast.literal_eval` | [deserialization.md](injection/deserialization.md) |

## Authentication & Authorization

| Pattern | Risk | What to Check | Reference |
|---------|------|---------------|-----------|
| `jwt.decode(..., verify=False)` | Auth Bypass | Always verify signature | [jwt-validation.md](auth/jwt-validation.md) |
| `algorithms=["HS256", "RS256", "none"]` | Alg Confusion | Explicit single algorithm | [jwt-validation.md](auth/jwt-validation.md) |
| Missing `audience` validation | Token Reuse | Validate aud claim | [jwt-validation.md](auth/jwt-validation.md) |
| No state parameter in OAuth | CSRF | Generate and validate state | [oauth-pkce.md](auth/oauth-pkce.md) |
| Missing PKCE | Code Interception | Always use code_challenge | [oauth-pkce.md](auth/oauth-pkce.md) |
| Token in localStorage | XSS Token Theft | Use httpOnly cookies or memory | [oauth-pkce.md](auth/oauth-pkce.md) |

## LLM/Agent Security

| Pattern | Risk | What to Check | Reference |
|---------|------|---------------|-----------|
| RAG → Tool calls → External API | Data Exfiltration | Lethal trifecta present | [prompt-injection.md](llm-agent/prompt-injection.md) |
| `rehype-raw` in react-markdown | XSS via LLM output | Remove or use allowedElements | [output-rendering.md](llm-agent/output-rendering.md) |
| `dangerouslySetInnerHTML` | XSS | Use DOMPurify or avoid | [output-rendering.md](llm-agent/output-rendering.md) |
| Tool accepts `url` parameter | SSRF via agent | Validate/allowlist URLs | [tool-safety.md](llm-agent/tool-safety.md) |
| Tool accepts `path` parameter | Path Traversal | Validate within allowed dir | [tool-safety.md](llm-agent/tool-safety.md) |
| No rate limiting on tools | DoS/Abuse | Add rate limits | [tool-safety.md](llm-agent/tool-safety.md) |

## Input Handling

| Pattern | Risk | What to Check | Reference |
|---------|------|---------------|-----------|
| `requests.get(user_url)` | SSRF | Validate URL, block private IPs | [ssrf.md](input-output/ssrf.md) |
| `httpx.get(url, follow_redirects=True)` | SSRF via Redirect | Validate each redirect | [ssrf.md](input-output/ssrf.md) |
| File upload without validation | Malicious Upload | Extension + magic bytes + storage | [file-upload.md](input-output/file-upload.md) |
| Filename from user in path | Path Traversal | Sanitize or regenerate name | [file-upload.md](input-output/file-upload.md) |
| `zipfile.extractall()` | Zip Slip | Check paths before extract | [file-upload.md](input-output/file-upload.md) |

## Output Handling

| Pattern | Risk | What to Check | Reference |
|---------|------|---------------|-----------|
| `{{ var \| safe }}` in Jinja | XSS | Remove `safe` filter | [xss-prevention.md](input-output/xss-prevention.md) |
| `element.innerHTML = userInput` | XSS | Use textContent | [xss-prevention.md](input-output/xss-prevention.md) |
| `href={userInput}` | XSS via javascript: | Validate URL scheme | [xss-prevention.md](input-output/xss-prevention.md) |
| `allow_origins=["*"]` with credentials | CORS Misconfiguration | Use explicit allowlist | [cors.md](input-output/cors.md) |
| Origin reflection without validation | CORS Misconfiguration | Validate against allowlist | [cors.md](input-output/cors.md) |

## Dangerous Defaults

| Pattern | Risk | What to Check | Reference |
|---------|------|---------------|-----------|
| `verify=False` in requests/httpx | TLS Bypass | Remove or use proper certs | - |
| `DEBUG=True` in production | Info Disclosure | Ensure DEBUG=False | - |
| `CORS(allow_origins=["*"])` | Open CORS | Use explicit origins | [cors.md](input-output/cors.md) |
| No CSP header | XSS Impact | Add Content-Security-Policy | [xss-prevention.md](input-output/xss-prevention.md) |
| Missing `rel="noopener"` on links | Tab Nabbing | Add to external links | [output-rendering.md](llm-agent/output-rendering.md) |

## Secrets in Code

| Pattern | Risk | What to Check | Reference |
|---------|------|---------------|-----------|
| `password = "..."` | Credential Exposure | Use environment/vault | - |
| `AKIA[0-9A-Z]{16}` | AWS Key Exposure | Rotate and use IAM roles | - |
| `-----BEGIN.*PRIVATE KEY-----` | Key Exposure | Move to secure storage | - |
| API keys in source | Credential Exposure | Use secrets manager | - |

## Semgrep Quick Commands

```bash
# Run all security rules
uv run scripts/security_scan.py /path/to/repo

# Fast mode (high-priority rules only)
uv run scripts/security_scan.py --fast /path/to/repo

# Specific categories
semgrep --config p/python.lang.security
semgrep --config p/javascript.lang.security
semgrep --config p/secrets
semgrep --config p/owasp-top-ten
```

## Triage Priority

When multiple issues found, prioritize by:

1. **Critical**: Remote code execution, auth bypass, credential exposure
2. **High**: SQL injection, SSRF, stored XSS, privilege escalation
3. **Medium**: Reflected XSS, CORS misconfiguration, missing rate limits
4. **Low**: Missing security headers, verbose errors, weak crypto

## See Also

- [SKILL.md](../SKILL.md) - Full security review workflow
- [finding_template.md](finding_template.md) - How to document findings
