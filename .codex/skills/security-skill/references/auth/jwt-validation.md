# JWT Validation

JSON Web Tokens must be validated correctly. Missing or incorrect validation allows token forgery and unauthorized access.

## JWT Structure

```
header.payload.signature

eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.  # Header (algorithm, type)
eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4ifQ.  # Payload (claims)
SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c  # Signature
```

## Validation Checklist

Every JWT validation must check:

1. **Signature** - Verify cryptographic signature
2. **Algorithm** - Ensure expected algorithm (no `alg: none`)
3. **Issuer (iss)** - Token from expected identity provider
4. **Audience (aud)** - Token intended for your application
5. **Expiration (exp)** - Token not expired
6. **Not Before (nbf)** - Token is active (if present)
7. **Issued At (iat)** - Token not from the future

## Python Implementation

### Using PyJWT

```python
import jwt
from jwt import InvalidTokenError, ExpiredSignatureError
from typing import Any

# For RS256 (asymmetric) - fetch from JWKS endpoint
def get_signing_key(token: str) -> str:
    """Fetch public key from identity provider's JWKS."""
    from jwt import PyJWKClient

    jwks_client = PyJWKClient(JWKS_URI)
    signing_key = jwks_client.get_signing_key_from_jwt(token)
    return signing_key.key

def validate_jwt(token: str) -> dict[str, Any]:
    """Validate JWT with all required checks."""
    try:
        # Get the signing key
        signing_key = get_signing_key(token)

        # Decode and validate
        payload = jwt.decode(
            token,
            signing_key,
            algorithms=["RS256"],  # Explicit algorithm allowlist
            audience=EXPECTED_AUDIENCE,  # Your client ID
            issuer=EXPECTED_ISSUER,  # e.g., https://login.microsoftonline.com/{tenant}/v2.0
            options={
                "require": ["exp", "iat", "iss", "aud", "sub"],
                "verify_exp": True,
                "verify_iat": True,
                "verify_iss": True,
                "verify_aud": True,
            }
        )

        return payload

    except ExpiredSignatureError:
        raise AuthenticationError("Token expired")
    except InvalidTokenError as e:
        raise AuthenticationError(f"Invalid token: {e}")
```

### JWKS Caching

```python
from functools import lru_cache
import time

class JWKSClient:
    def __init__(self, jwks_uri: str, cache_ttl: int = 3600):
        self.jwks_uri = jwks_uri
        self.cache_ttl = cache_ttl
        self._cache = None
        self._cache_time = 0

    def get_signing_key(self, kid: str):
        if self._is_cache_expired():
            self._refresh_cache()

        for key in self._cache["keys"]:
            if key.get("kid") == kid:
                return self._parse_key(key)

        # Key not found - might be rotated, refresh once
        self._refresh_cache()
        for key in self._cache["keys"]:
            if key.get("kid") == kid:
                return self._parse_key(key)

        raise InvalidTokenError(f"Unknown key ID: {kid}")

    def _is_cache_expired(self) -> bool:
        return time.time() - self._cache_time > self.cache_ttl

    def _refresh_cache(self):
        response = httpx.get(self.jwks_uri)
        response.raise_for_status()
        self._cache = response.json()
        self._cache_time = time.time()
```

## Common Vulnerabilities

### 1. Algorithm Confusion (Critical)

```python
# VULNERABLE - accepts any algorithm, including "none"
payload = jwt.decode(token, SECRET, algorithms=["HS256", "RS256", "none"])

# VULNERABLE - no algorithm specified
payload = jwt.decode(token, SECRET)

# FIXED - explicit algorithm allowlist
payload = jwt.decode(token, key, algorithms=["RS256"])  # Only accept RS256
```

The `alg: none` attack:
```python
# Attacker crafts token with alg: none
# Header: {"alg": "none", "typ": "JWT"}
# No signature required

# If library accepts "none", attacker bypasses signature verification
```

### 2. Key Confusion (HS256 vs RS256)

```python
# VULNERABLE - library uses public key as HMAC secret
# Attacker signs with public key (which is public!) using HS256

# Attack:
# 1. Get server's RSA public key
# 2. Create token signed with HMAC using public key as secret
# 3. Set alg: HS256
# 4. Server uses public key to verify HMAC = success!

# FIXED - validate algorithm matches key type
payload = jwt.decode(
    token,
    rsa_public_key,
    algorithms=["RS256"]  # ONLY RS256, not HS256
)
```

### 3. Missing Audience Validation

```python
# VULNERABLE - token for different app accepted
payload = jwt.decode(token, key, algorithms=["RS256"])
# Token with aud: "other-app" is accepted!

# FIXED - validate audience
payload = jwt.decode(
    token,
    key,
    algorithms=["RS256"],
    audience="my-app-client-id"  # Must match
)
```

### 4. Missing Issuer Validation

```python
# VULNERABLE - token from any issuer accepted
payload = jwt.decode(token, key, algorithms=["RS256"])

# FIXED - validate issuer
payload = jwt.decode(
    token,
    key,
    algorithms=["RS256"],
    issuer="https://login.microsoftonline.com/{tenant}/v2.0"
)
```

### 5. Disabled Expiration Check

```python
# VULNERABLE - expired tokens accepted
payload = jwt.decode(
    token, key,
    options={"verify_exp": False}  # NEVER do this in production
)

# FIXED - always verify expiration (default)
payload = jwt.decode(token, key, algorithms=["RS256"])
```

### 6. Clock Skew Issues

```python
# Allow small clock skew (server clocks may differ)
payload = jwt.decode(
    token,
    key,
    algorithms=["RS256"],
    leeway=timedelta(seconds=30)  # 30 second tolerance
)
```

## Azure AD / Entra ID Specifics

### ID Token vs Access Token

```python
# ID Token - for authentication, validate fully
id_token_payload = validate_jwt(
    id_token,
    audience=CLIENT_ID,  # Your app's client ID
    issuer=f"https://login.microsoftonline.com/{TENANT_ID}/v2.0"
)

# Access Token - for API authorization
# Note: Microsoft access tokens for MS Graph are NOT meant to be validated by you
# Only validate access tokens issued for YOUR API

access_token_payload = validate_jwt(
    access_token,
    audience=API_AUDIENCE,  # Your API's identifier (e.g., api://my-api)
    issuer=f"https://sts.windows.net/{TENANT_ID}/"  # Note: different format
)
```

### Required Claims for Azure AD

```python
REQUIRED_CLAIMS = {
    "iss",   # Issuer
    "sub",   # Subject (user ID)
    "aud",   # Audience
    "exp",   # Expiration
    "iat",   # Issued at
    "nbf",   # Not before
}

# Optional but useful
OPTIONAL_CLAIMS = {
    "tid",   # Tenant ID
    "oid",   # Object ID (unique user ID in Azure AD)
    "preferred_username",  # UPN or email
    "roles",  # App roles
    "scp",   # Scopes (for access tokens)
}

def validate_azure_token(token: str) -> dict:
    payload = validate_jwt(token)

    # Check required claims present
    missing = REQUIRED_CLAIMS - set(payload.keys())
    if missing:
        raise InvalidTokenError(f"Missing claims: {missing}")

    # Validate tenant if multi-tenant app
    if ALLOWED_TENANTS and payload.get("tid") not in ALLOWED_TENANTS:
        raise InvalidTokenError("Tenant not allowed")

    return payload
```

## FastAPI Dependency

```python
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

security = HTTPBearer()

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> dict:
    """Validate JWT and return user claims."""
    try:
        payload = validate_jwt(credentials.credentials)
        return {
            "sub": payload["sub"],
            "email": payload.get("preferred_username"),
            "roles": payload.get("roles", []),
        }
    except AuthenticationError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(e),
            headers={"WWW-Authenticate": "Bearer"},
        )

# Usage
@app.get("/protected")
async def protected(user: dict = Depends(get_current_user)):
    return {"message": f"Hello {user['email']}"}
```

## Token Refresh

```python
async def get_valid_access_token(user_id: str) -> str:
    """Get valid access token, refreshing if needed."""
    tokens = await token_store.get(user_id)

    if not tokens:
        raise AuthenticationRequired()

    # Check if access token is expired or expiring soon
    try:
        payload = jwt.decode(
            tokens["access_token"],
            options={"verify_signature": False}  # Just check expiry
        )
        exp = datetime.fromtimestamp(payload["exp"], tz=timezone.utc)

        # Refresh if expiring in less than 5 minutes
        if exp - datetime.now(timezone.utc) < timedelta(minutes=5):
            tokens = await refresh_tokens(tokens["refresh_token"])
            await token_store.set(user_id, tokens)

    except jwt.ExpiredSignatureError:
        tokens = await refresh_tokens(tokens["refresh_token"])
        await token_store.set(user_id, tokens)

    return tokens["access_token"]
```

## Audit Checklist

- [ ] Is algorithm explicitly specified (no `alg: none`)?
- [ ] Is audience claim validated against your app's ID?
- [ ] Is issuer claim validated against expected identity provider?
- [ ] Is expiration verified (verify_exp not disabled)?
- [ ] Are JWKS endpoints cached with appropriate TTL?
- [ ] Is clock skew handled appropriately?
- [ ] Are all required claims checked?
- [ ] Is the correct key type used (RSA for RS256)?

## References

- RFC 8725 (JWT Best Current Practices)
- RFC 7519 (JSON Web Token)
- PyJWT documentation
- Microsoft Identity Platform token reference
