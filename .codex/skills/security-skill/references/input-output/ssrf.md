# SSRF Prevention

Server-Side Request Forgery (SSRF) occurs when an attacker can make the server issue requests to arbitrary URLs, potentially accessing internal services or cloud metadata.

## The Risk

Attackers provide URLs that the server fetches:

```python
# VULNERABLE - user controls URL
@app.post("/fetch")
async def fetch_url(url: str):
    response = await httpx.get(url)
    return response.text

# Attacker requests:
# - http://169.254.169.254/latest/meta-data/  (AWS metadata)
# - http://localhost:8080/admin  (internal service)
# - http://10.0.0.1:6379/  (internal Redis)
# - file:///etc/passwd  (local files)
```

## Attack Targets

| Target | Risk | Example URL |
|--------|------|-------------|
| Cloud metadata | Credential theft | `http://169.254.169.254/latest/meta-data/iam/` |
| Internal services | Access control bypass | `http://localhost:8080/admin` |
| Private networks | Internal reconnaissance | `http://192.168.1.0/24` |
| Localhost services | Redis, Memcached access | `http://127.0.0.1:6379/` |
| File system | Local file read | `file:///etc/passwd` |

## Defense Strategies

### 1. URL Allowlist (Strongest)

```python
from urllib.parse import urlparse

ALLOWED_HOSTS = {
    "api.example.com",
    "cdn.example.com",
    "images.example.com",
}

ALLOWED_SCHEMES = {"https"}  # HTTP is also risky

def validate_url(url: str) -> str:
    """Validate URL against allowlist."""
    try:
        parsed = urlparse(url)
    except Exception:
        raise ValueError("Invalid URL")

    if parsed.scheme not in ALLOWED_SCHEMES:
        raise ValueError(f"Scheme not allowed: {parsed.scheme}")

    if parsed.hostname not in ALLOWED_HOSTS:
        raise ValueError(f"Host not allowed: {parsed.hostname}")

    # Rebuild URL to prevent parsing tricks
    return f"{parsed.scheme}://{parsed.hostname}{parsed.path}"
```

### 2. Block Private/Reserved IPs

When allowlist isn't possible, block dangerous destinations:

```python
import ipaddress
import socket
from urllib.parse import urlparse

BLOCKED_NETWORKS = [
    ipaddress.ip_network("0.0.0.0/8"),        # Current network
    ipaddress.ip_network("10.0.0.0/8"),       # Private
    ipaddress.ip_network("127.0.0.0/8"),      # Loopback
    ipaddress.ip_network("169.254.0.0/16"),   # Link-local (AWS metadata!)
    ipaddress.ip_network("172.16.0.0/12"),    # Private
    ipaddress.ip_network("192.168.0.0/16"),   # Private
    ipaddress.ip_network("::1/128"),          # IPv6 loopback
    ipaddress.ip_network("fc00::/7"),         # IPv6 private
    ipaddress.ip_network("fe80::/10"),        # IPv6 link-local
]

def is_ip_blocked(ip_str: str) -> bool:
    """Check if IP is in blocked ranges."""
    try:
        ip = ipaddress.ip_address(ip_str)
        return any(ip in network for network in BLOCKED_NETWORKS)
    except ValueError:
        return True  # Invalid IP = blocked

def validate_url_destination(url: str) -> str:
    """Validate URL doesn't resolve to blocked IP."""
    parsed = urlparse(url)

    if parsed.scheme not in {"http", "https"}:
        raise ValueError(f"Scheme not allowed: {parsed.scheme}")

    hostname = parsed.hostname
    if not hostname:
        raise ValueError("No hostname in URL")

    # Resolve hostname to IP
    try:
        ip = socket.gethostbyname(hostname)
    except socket.gaierror:
        raise ValueError(f"Cannot resolve hostname: {hostname}")

    if is_ip_blocked(ip):
        raise ValueError(f"Destination IP blocked: {ip}")

    return url
```

### 3. DNS Rebinding Protection

Attacker's DNS returns safe IP initially, then switches to internal IP:

```python
import socket
import httpx

class SSRFSafeTransport(httpx.AsyncHTTPTransport):
    """Transport that validates IPs after DNS resolution."""

    async def handle_async_request(self, request):
        # Resolve and validate before connecting
        host = request.url.host
        try:
            ip = socket.gethostbyname(host)
        except socket.gaierror:
            raise ValueError(f"Cannot resolve: {host}")

        if is_ip_blocked(ip):
            raise ValueError(f"Blocked IP: {ip}")

        # Pin the IP to prevent rebinding
        # Force connection to resolved IP
        request = request.copy(
            extensions={"sni_hostname": host}
        )
        return await super().handle_async_request(request)

# Usage
async with httpx.AsyncClient(transport=SSRFSafeTransport()) as client:
    response = await client.get(user_url)
```

### 4. Timeout and Size Limits

Prevent DoS and slow-loris attacks:

```python
async def safe_fetch(url: str, max_size: int = 10_000_000) -> bytes:
    """Fetch URL with safety limits."""
    validate_url_destination(url)

    async with httpx.AsyncClient(
        timeout=httpx.Timeout(10.0, connect=5.0),
        follow_redirects=False,  # Or validate each redirect
    ) as client:
        async with client.stream("GET", url) as response:
            response.raise_for_status()

            content = b""
            async for chunk in response.aiter_bytes():
                content += chunk
                if len(content) > max_size:
                    raise ValueError("Response too large")

            return content
```

### 5. Redirect Validation

Each redirect can lead to internal URLs:

```python
async def safe_fetch_with_redirects(
    url: str,
    max_redirects: int = 5
) -> httpx.Response:
    """Follow redirects with validation at each step."""
    validate_url_destination(url)

    async with httpx.AsyncClient(follow_redirects=False) as client:
        for _ in range(max_redirects):
            response = await client.get(url)

            if response.status_code not in (301, 302, 303, 307, 308):
                return response

            # Validate redirect target
            redirect_url = response.headers.get("location")
            if not redirect_url:
                raise ValueError("Redirect without location")

            # Handle relative redirects
            redirect_url = urljoin(url, redirect_url)

            # Validate the new URL
            validate_url_destination(redirect_url)
            url = redirect_url

        raise ValueError("Too many redirects")
```

### 6. Cloud Metadata Protection

Block the metadata endpoint specifically:

```python
CLOUD_METADATA_IPS = {
    "169.254.169.254",  # AWS, GCP, Azure
    "169.254.170.2",    # AWS ECS
    "fd00:ec2::254",    # AWS IPv6
}

def block_cloud_metadata(url: str):
    parsed = urlparse(url)
    hostname = parsed.hostname

    # Direct IP check
    if hostname in CLOUD_METADATA_IPS:
        raise ValueError("Cloud metadata access blocked")

    # DNS resolution check
    try:
        ip = socket.gethostbyname(hostname)
        if ip in CLOUD_METADATA_IPS:
            raise ValueError("Cloud metadata access blocked (via DNS)")
    except socket.gaierror:
        pass  # Cannot resolve, will fail anyway

# AWS IMDSv2 requires a token - enable it!
# This doesn't prevent SSRF but limits impact
```

## Framework-Specific Patterns

### FastAPI

```python
from fastapi import FastAPI, Query, HTTPException
from pydantic import AnyHttpUrl

app = FastAPI()

@app.get("/fetch")
async def fetch_url(url: AnyHttpUrl = Query(...)):
    """Fetch external URL with SSRF protection."""
    url_str = str(url)

    try:
        validate_url_destination(url_str)
    except ValueError as e:
        raise HTTPException(400, f"URL not allowed: {e}")

    try:
        content = await safe_fetch(url_str)
        return {"content": content.decode()}
    except Exception as e:
        raise HTTPException(502, f"Fetch failed: {e}")
```

### Webhook Validation

```python
from pydantic import BaseModel, AnyHttpUrl, field_validator

class WebhookConfig(BaseModel):
    url: AnyHttpUrl
    secret: str

    @field_validator("url")
    @classmethod
    def validate_webhook_url(cls, v):
        url_str = str(v)

        # Must be HTTPS
        if not url_str.startswith("https://"):
            raise ValueError("Webhook URL must use HTTPS")

        # Validate destination
        validate_url_destination(url_str)

        return v
```

## Testing SSRF Protection

```python
import pytest

SSRF_TEST_URLS = [
    # Cloud metadata
    "http://169.254.169.254/latest/meta-data/",
    "http://metadata.google.internal/",
    # Localhost
    "http://localhost/admin",
    "http://127.0.0.1:8080/",
    "http://[::1]/",
    # Private networks
    "http://10.0.0.1/",
    "http://192.168.1.1/",
    "http://172.16.0.1/",
    # File protocol
    "file:///etc/passwd",
    # DNS rebinding (use your own test domain)
    # "http://rebind.example.com/",
]

@pytest.mark.parametrize("url", SSRF_TEST_URLS)
def test_ssrf_blocked(url):
    with pytest.raises(ValueError):
        validate_url_destination(url)
```

## Audit Checklist

- [ ] Are user-provided URLs validated before fetching?
- [ ] Is there an allowlist of permitted hosts (preferred)?
- [ ] Are private/reserved IP ranges blocked?
- [ ] Is cloud metadata endpoint specifically blocked?
- [ ] Are redirects validated at each hop?
- [ ] Are DNS rebinding attacks mitigated?
- [ ] Are timeouts and size limits enforced?
- [ ] Is the `file://` scheme blocked?
- [ ] Is IMDSv2 enabled on AWS instances?

## References

- OWASP SSRF Prevention Cheat Sheet
- AWS IMDSv2 documentation
- PortSwigger SSRF research
