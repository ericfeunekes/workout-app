# OAuth 2.0 and PKCE Implementation

OAuth 2.0 authorization code flow with PKCE (Proof Key for Code Exchange) is the recommended pattern for both public and confidential clients.

## Flow Overview

```
1. Client generates code_verifier (random string)
2. Client computes code_challenge = SHA256(code_verifier)
3. Client redirects to /authorize with code_challenge
4. User authenticates, authorization server issues code
5. Client exchanges code + code_verifier for tokens
6. Authorization server verifies SHA256(code_verifier) == code_challenge
7. Tokens issued
```

## PKCE Implementation

### Generate Code Verifier and Challenge

```python
import secrets
import hashlib
import base64

def generate_pkce_pair() -> tuple[str, str]:
    """Generate code_verifier and code_challenge for PKCE."""
    # code_verifier: 43-128 characters, URL-safe
    code_verifier = secrets.token_urlsafe(32)  # 43 chars

    # code_challenge: SHA256 hash, base64url encoded
    digest = hashlib.sha256(code_verifier.encode()).digest()
    code_challenge = base64.urlsafe_b64encode(digest).rstrip(b'=').decode()

    return code_verifier, code_challenge

# Usage
verifier, challenge = generate_pkce_pair()
# Store verifier in session, send challenge to authorize endpoint
```

### Authorization Request

```python
from urllib.parse import urlencode

def build_authorize_url(
    authorize_endpoint: str,
    client_id: str,
    redirect_uri: str,
    code_challenge: str,
    scope: str = "openid profile email",
    state: str | None = None
) -> str:
    """Build OAuth authorization URL with PKCE."""
    if state is None:
        state = secrets.token_urlsafe(16)

    params = {
        "response_type": "code",
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "scope": scope,
        "state": state,
        "code_challenge": code_challenge,
        "code_challenge_method": "S256",  # Always use SHA256
    }

    return f"{authorize_endpoint}?{urlencode(params)}"
```

### Token Exchange

```python
import httpx

async def exchange_code_for_tokens(
    token_endpoint: str,
    client_id: str,
    code: str,
    code_verifier: str,
    redirect_uri: str,
    client_secret: str | None = None  # For confidential clients
) -> dict:
    """Exchange authorization code for tokens."""
    data = {
        "grant_type": "authorization_code",
        "client_id": client_id,
        "code": code,
        "code_verifier": code_verifier,
        "redirect_uri": redirect_uri,
    }

    if client_secret:
        data["client_secret"] = client_secret

    async with httpx.AsyncClient() as client:
        response = await client.post(
            token_endpoint,
            data=data,
            headers={"Content-Type": "application/x-www-form-urlencoded"}
        )
        response.raise_for_status()
        return response.json()
```

## Security Requirements

### State Parameter

Prevents CSRF attacks on the callback:

```python
from starlette.requests import Request
from starlette.responses import RedirectResponse

async def initiate_login(request: Request):
    verifier, challenge = generate_pkce_pair()
    state = secrets.token_urlsafe(16)

    # Store in session (server-side)
    request.session["oauth_state"] = state
    request.session["oauth_verifier"] = verifier

    url = build_authorize_url(
        authorize_endpoint=AUTH_URL,
        client_id=CLIENT_ID,
        redirect_uri=REDIRECT_URI,
        code_challenge=challenge,
        state=state
    )
    return RedirectResponse(url)

async def oauth_callback(request: Request):
    # Verify state matches
    returned_state = request.query_params.get("state")
    expected_state = request.session.get("oauth_state")

    if not returned_state or returned_state != expected_state:
        raise HTTPException(400, "Invalid state parameter")

    # Clear state to prevent replay
    del request.session["oauth_state"]

    # Continue with code exchange...
```

### Redirect URI Validation

Authorization servers must validate redirect URIs exactly:

```python
# Server-side: exact match required
REGISTERED_REDIRECT_URIS = {
    "https://app.example.com/callback",
    "https://app.example.com/oauth/callback",
}

def validate_redirect_uri(uri: str) -> bool:
    # Exact match - no wildcards, no path manipulation
    return uri in REGISTERED_REDIRECT_URIS
```

Client-side: use exact registered URIs:

```python
# CORRECT
redirect_uri = "https://app.example.com/callback"

# WRONG - path parameters can be manipulated
redirect_uri = f"https://app.example.com/callback?next={user_input}"
```

### Token Storage

```python
# Browser (SPA) - use secure, httpOnly cookies or memory
# NEVER localStorage for access tokens (XSS vulnerable)

# Backend - encrypt at rest
from cryptography.fernet import Fernet

class TokenStore:
    def __init__(self, encryption_key: bytes):
        self.fernet = Fernet(encryption_key)

    def store(self, user_id: str, tokens: dict):
        encrypted = self.fernet.encrypt(json.dumps(tokens).encode())
        self.db.set(f"tokens:{user_id}", encrypted)

    def retrieve(self, user_id: str) -> dict | None:
        encrypted = self.db.get(f"tokens:{user_id}")
        if not encrypted:
            return None
        decrypted = self.fernet.decrypt(encrypted)
        return json.loads(decrypted)
```

## FastAPI Integration

### OAuth2 with PKCE Flow

```python
from fastapi import FastAPI, Depends, HTTPException, Request
from fastapi.responses import RedirectResponse
from authlib.integrations.starlette_client import OAuth

app = FastAPI()
oauth = OAuth()

oauth.register(
    name="azure",
    client_id=CLIENT_ID,
    client_secret=CLIENT_SECRET,
    server_metadata_url=f"https://login.microsoftonline.com/{TENANT_ID}/v2.0/.well-known/openid-configuration",
    client_kwargs={"scope": "openid profile email"}
)

@app.get("/login")
async def login(request: Request):
    redirect_uri = request.url_for("callback")
    return await oauth.azure.authorize_redirect(request, redirect_uri)

@app.get("/callback")
async def callback(request: Request):
    token = await oauth.azure.authorize_access_token(request)
    user_info = token.get("userinfo")
    # Create session, store tokens
    return RedirectResponse("/")
```

### Protecting Routes

```python
from fastapi import Depends, HTTPException
from fastapi.security import OAuth2PasswordBearer

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

async def get_current_user(token: str = Depends(oauth2_scheme)):
    try:
        payload = verify_token(token)  # See jwt-validation.md
        return payload
    except InvalidTokenError:
        raise HTTPException(401, "Invalid token")

@app.get("/protected")
async def protected_route(user: dict = Depends(get_current_user)):
    return {"user": user}
```

## Common Vulnerabilities

### 1. Missing PKCE

```python
# VULNERABLE - no PKCE, authorization code can be intercepted
params = {
    "response_type": "code",
    "client_id": client_id,
    "redirect_uri": redirect_uri,
    # Missing code_challenge
}

# FIXED - always use PKCE
params = {
    "response_type": "code",
    "client_id": client_id,
    "redirect_uri": redirect_uri,
    "code_challenge": challenge,
    "code_challenge_method": "S256",
}
```

### 2. State Not Validated

```python
# VULNERABLE - CSRF possible
@app.get("/callback")
async def callback(code: str):
    # No state validation
    tokens = await exchange_code(code)

# FIXED
@app.get("/callback")
async def callback(request: Request, code: str, state: str):
    if state != request.session.get("oauth_state"):
        raise HTTPException(400, "Invalid state")
    tokens = await exchange_code(code)
```

### 3. Open Redirect via redirect_uri

```python
# VULNERABLE - user-controlled redirect
@app.get("/login")
async def login(redirect_uri: str):  # User controls this!
    return oauth.authorize_redirect(redirect_uri)

# FIXED - hardcoded or allowlisted
ALLOWED_REDIRECTS = {"https://app.example.com/callback"}

@app.get("/login")
async def login():
    redirect_uri = "https://app.example.com/callback"  # Fixed
    return oauth.authorize_redirect(redirect_uri)
```

### 4. Token in URL Fragment/Query

```python
# VULNERABLE - implicit flow, token in URL
response_type = "token"  # Token in fragment, logged in browser history

# FIXED - authorization code flow
response_type = "code"  # Code exchanged server-side
```

## Refresh Token Handling

```python
async def refresh_tokens(refresh_token: str) -> dict:
    """Exchange refresh token for new tokens."""
    async with httpx.AsyncClient() as client:
        response = await client.post(
            TOKEN_ENDPOINT,
            data={
                "grant_type": "refresh_token",
                "client_id": CLIENT_ID,
                "client_secret": CLIENT_SECRET,
                "refresh_token": refresh_token,
            }
        )

        if response.status_code == 400:
            # Refresh token expired or revoked
            raise TokenExpiredError("Re-authentication required")

        response.raise_for_status()
        return response.json()

# Proactive refresh before expiry
async def get_valid_token(user_id: str) -> str:
    tokens = token_store.retrieve(user_id)

    if is_expired(tokens["access_token"]):
        if is_expired(tokens["refresh_token"]):
            raise AuthenticationRequired()

        new_tokens = await refresh_tokens(tokens["refresh_token"])
        token_store.store(user_id, new_tokens)
        return new_tokens["access_token"]

    return tokens["access_token"]
```

## Audit Checklist

- [ ] Is PKCE used for all authorization code flows?
- [ ] Is state parameter generated, stored, and validated?
- [ ] Are redirect URIs exact-match validated?
- [ ] Are tokens stored securely (not localStorage)?
- [ ] Is the implicit flow avoided?
- [ ] Are refresh tokens rotated on use?
- [ ] Is token expiry checked before use?

## References

- RFC 7636 (PKCE)
- RFC 9700 (OAuth 2.0 Security Best Current Practice)
- RFC 6749 (OAuth 2.0)
- Microsoft Identity Platform documentation
