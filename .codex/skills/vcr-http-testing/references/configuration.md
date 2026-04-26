# VCR Configuration Reference

Complete reference for VCR configuration options relevant to this codebase.

## Core Configuration Options

### record_mode

Controls when VCR records new HTTP interactions.

| Mode | Behavior |
|------|----------|
| `"once"` | Record if cassette doesn't exist, never update |
| `"new_episodes"` | Record new requests, replay existing (recommended) |
| `"none"` | Only replay, fail if request not in cassette |
| `"all"` | Always record, overwrite cassette |

**Recommendation**: Use `"new_episodes"` for development. Switch to `"none"` in CI to catch missing cassettes.

### match_on

List of request attributes to match when finding recorded responses.

```python
# Default - matches everything
match_on = ["method", "scheme", "host", "port", "path", "query", "body"]

# Relaxed - ignores volatile fields
match_on = ["method", "host", "path"]

# Strict path only
match_on = ["method", "uri"]
```

**Options**:
- `"method"` - HTTP method (GET, POST, etc.)
- `"scheme"` - http or https
- `"host"` - Domain name
- `"port"` - Port number
- `"path"` - URL path
- `"query"` - Query string parameters
- `"body"` - Request body
- `"headers"` - Request headers
- `"uri"` - Full URI (scheme + host + port + path + query)

**For LLM APIs**: Avoid matching on `body` - requests contain timestamps, UUIDs, and varying message content.

### filter_headers

Remove sensitive headers before recording.

```python
filter_headers = [
    "authorization",
    "x-api-key",
    "api-key",
    "x-goog-api-key",
    "x-amz-security-token",
]
```

### filter_post_data_parameters

Remove sensitive POST body fields.

```python
filter_post_data_parameters = ["password", "api_key", "secret"]
```

### cassette_library_dir

Directory for cassette storage.

```python
cassette_library_dir = "tests/data/cassettes"
```

### ignore_hosts

List of hosts to skip recording (passthrough to real network).

```python
# Let Databricks calls through
ignore_hosts = [
    "adb-*.azuredatabricks.net",
    "*.databricks.com",
]
```

**Note**: Wildcards are supported.

### ignore_localhost

Skip recording localhost requests.

```python
ignore_localhost = True  # Default: False
```

## Request/Response Hooks

### before_record_request

Modify or filter requests before recording.

```python
def before_record_request(request):
    """Filter or modify requests before recording."""
    # Skip certain hosts
    if "internal-api" in request.host:
        return None  # Don't record

    # Scrub sensitive data from path
    if "/users/" in request.path:
        request.uri = request.uri.replace(
            request.path,
            "/users/[REDACTED]"
        )

    return request
```

### before_record_response

Modify responses before recording.

```python
def before_record_response(response):
    """Modify responses before recording."""
    # Remove large binary data
    if response["headers"].get("content-type", [""])[0].startswith("image/"):
        response["body"]["string"] = b"[IMAGE DATA REMOVED]"

    return response
```

### before_playback_response

Modify responses before replaying.

```python
def before_playback_response(request, response):
    """Modify responses before replaying."""
    # Inject dynamic timestamp
    body = response["body"]["string"]
    body = body.replace(b'"timestamp": null', f'"timestamp": "{datetime.now()}"'.encode())
    response["body"]["string"] = body

    return response
```

## Full Configuration Example

```python
# tests/conftest.py
import pytest
from datetime import datetime

def filter_sensitive_requests(request):
    """Skip internal endpoints, scrub sensitive paths."""
    if "internal" in request.host:
        return None
    return request

def filter_sensitive_responses(response):
    """Remove PII from responses before recording."""
    # Scrub email addresses (example)
    body = response["body"]["string"]
    if isinstance(body, bytes):
        body = body.replace(b"user@example.com", b"[EMAIL]")
        response["body"]["string"] = body
    return response

@pytest.fixture(scope="module")
def vcr_config():
    return {
        # Recording behavior
        "record_mode": "new_episodes",
        "cassette_library_dir": "tests/data/cassettes",

        # Request matching
        "match_on": ["method", "scheme", "host", "port", "path"],

        # Sensitive data filtering
        "filter_headers": [
            "authorization",
            "x-api-key",
            "api-key",
            "x-goog-api-key",
        ],

        # Passthrough hosts
        "ignore_hosts": ["adb-*.azuredatabricks.net"],

        # Hooks
        "before_record_request": filter_sensitive_requests,
        "before_record_response": filter_sensitive_responses,
    }
```

## httpx-Specific Configuration

VCR patches httpcore to intercept httpx requests. Ensure vcrpy >= 6.0.2 for streaming support.

```python
# No special configuration needed for httpx
# VCR automatically patches httpcore

# For streaming responses, just use the cassette normally:
with recorder.use_cassette("streaming.yaml"):
    async for chunk in client.stream("GET", url):
        process(chunk)
```

## CI Configuration

For CI environments, use strict replay mode:

```python
import os

@pytest.fixture(scope="module")
def vcr_config():
    # In CI, fail if cassette is missing
    record_mode = "none" if os.getenv("CI") else "new_episodes"

    return {
        "record_mode": record_mode,
        "cassette_library_dir": "tests/data/cassettes",
        "match_on": ["method", "scheme", "host", "port", "path"],
        "filter_headers": ["authorization", "x-api-key"],
    }
```
