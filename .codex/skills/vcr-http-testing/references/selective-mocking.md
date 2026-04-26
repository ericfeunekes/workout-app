# Selective Mocking Patterns

Techniques for mixing real and mocked HTTP calls in integration tests.

## Use Cases

1. **Real LLM + Mocked Infrastructure**: Test LLM behavior with deterministic database/vector search responses
2. **Mocked LLM + Real Infrastructure**: Test infrastructure integration with controlled LLM responses
3. **Partial Recording**: Record only specific endpoints, let others pass through

## Pattern 1: ignore_hosts

Simplest approach - skip recording for specific hosts.

```python
@pytest.fixture(scope="module")
def vcr_config():
    return {
        "record_mode": "new_episodes",
        "cassette_library_dir": "tests/data/cassettes",
        "match_on": ["method", "scheme", "host", "port", "path"],
        "filter_headers": ["authorization", "x-api-key"],

        # These hosts pass through to real network
        "ignore_hosts": [
            "adb-*.azuredatabricks.net",  # Databricks
            "*.blob.core.windows.net",     # Azure Blob
            "localhost",                   # Local services
        ],
    }
```

**Limitation**: Wildcards work for subdomains but not complex patterns.

## Pattern 2: before_record_request Hook

Fine-grained control over what gets recorded.

```python
def selective_record(request):
    """
    Return None to skip recording (passthrough).
    Return request to record.
    """
    host = request.host.lower()

    # Always record LLM API calls
    llm_hosts = [
        "api.openai.com",
        "api.anthropic.com",
        "bedrock-runtime",
        "generativelanguage.googleapis.com",
    ]
    if any(h in host for h in llm_hosts):
        return request

    # Skip Databricks - use real calls
    if "databricks" in host:
        return None

    # Skip internal services
    if host.startswith("internal-") or host == "localhost":
        return None

    # Record everything else
    return request

@pytest.fixture(scope="module")
def vcr_config():
    return {
        "record_mode": "new_episodes",
        "cassette_library_dir": "tests/data/cassettes",
        "before_record_request": selective_record,
        "filter_headers": ["authorization", "x-api-key"],
    }
```

## Pattern 3: Path-Based Filtering

Record based on URL path patterns.

```python
import re

def filter_by_path(request):
    """Record only specific API paths."""
    path = request.path

    # Record LLM completions
    if re.match(r".*/chat/completions", path):
        return request

    # Record embeddings
    if re.match(r".*/embeddings", path):
        return request

    # Skip health checks
    if "/health" in path or "/ping" in path:
        return None

    # Skip vector search (use real)
    if "/vector-search" in path:
        return None

    return request
```

## Pattern 4: Conditional Recording

Switch behavior based on environment or test markers.

```python
import os
import pytest

def make_selective_filter(record_llm=True, record_infra=False):
    """Factory for creating selective recording filters."""
    def filter_request(request):
        host = request.host.lower()

        is_llm = any(h in host for h in [
            "openai.com", "anthropic.com", "bedrock"
        ])
        is_infra = any(h in host for h in [
            "databricks", "blob.core.windows"
        ])

        if is_llm and record_llm:
            return request
        if is_infra and record_infra:
            return request
        if not is_llm and not is_infra:
            return request  # Record unknown hosts

        return None  # Skip

    return filter_request

@pytest.fixture(scope="module")
def vcr_config(request):
    # Check for pytest marker
    marker = request.node.get_closest_marker("vcr_mode")
    if marker:
        mode = marker.args[0]
    else:
        mode = "default"

    configs = {
        "default": {
            "before_record_request": make_selective_filter(
                record_llm=True, record_infra=False
            ),
        },
        "full_integration": {
            "before_record_request": make_selective_filter(
                record_llm=True, record_infra=True
            ),
        },
        "infra_only": {
            "before_record_request": make_selective_filter(
                record_llm=False, record_infra=True
            ),
        },
    }

    base_config = {
        "record_mode": "new_episodes",
        "cassette_library_dir": "tests/data/cassettes",
        "filter_headers": ["authorization", "x-api-key"],
    }
    base_config.update(configs.get(mode, configs["default"]))

    return base_config

# Usage in tests
@pytest.mark.vcr_mode("full_integration")
def test_full_pipeline(vcr_config):
    # Records both LLM and infrastructure calls
    ...

@pytest.mark.vcr_mode("infra_only")
def test_infrastructure(vcr_config):
    # Records only infrastructure, real LLM calls
    ...
```

## Pattern 5: Multiple Cassettes

Use separate cassettes for different concerns.

```python
import vcr

def test_with_multiple_cassettes(vcr_config):
    recorder = vcr.VCR(**vcr_config)

    # LLM responses from cassette
    with recorder.use_cassette("llm_responses.yaml"):
        llm_result = call_llm("What is 2+2?")

    # Infrastructure calls are real (no cassette)
    db_result = query_database("SELECT * FROM users")

    # Process together
    assert process(llm_result, db_result)
```

## Pattern 6: Request Modification for Replay

Normalize requests to improve cassette reuse.

```python
def normalize_request(request):
    """Normalize volatile fields for better matching."""
    import json
    import re

    # Normalize timestamps in body
    if request.body:
        try:
            body = json.loads(request.body)
            # Remove or normalize timestamps
            if "timestamp" in body:
                body["timestamp"] = "NORMALIZED"
            # Normalize UUIDs in messages
            if "messages" in body:
                for msg in body["messages"]:
                    if "content" in msg and msg["content"]:
                        msg["content"] = re.sub(
                            r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
                            "UUID",
                            msg["content"]
                        )
            request.body = json.dumps(body)
        except (json.JSONDecodeError, TypeError):
            pass

    return request

@pytest.fixture(scope="module")
def vcr_config():
    return {
        "record_mode": "new_episodes",
        "cassette_library_dir": "tests/data/cassettes",
        "before_record_request": normalize_request,
        # Match on normalized body
        "match_on": ["method", "host", "path", "body"],
    }
```

## Integration Test Example

Complete example: Real LLM reasoning with mocked document retrieval.

```python
import vcr
import pytest
from unittest.mock import patch

@pytest.fixture(scope="module")
def vcr_config():
    """Record LLM calls, skip Databricks."""
    def filter_request(request):
        if "databricks" in request.host.lower():
            return None  # Don't record
        return request

    return {
        "record_mode": "new_episodes",
        "cassette_library_dir": "tests/data/cassettes",
        "before_record_request": filter_request,
        "filter_headers": ["authorization", "x-api-key"],
    }

@pytest.fixture
def mock_retriever():
    """Provide deterministic document results."""
    with patch("myapp.retriever.search_documents") as mock:
        mock.return_value = [
            {"id": "doc1", "text": "Tax deduction rules...", "score": 0.95},
            {"id": "doc2", "text": "Income thresholds...", "score": 0.87},
        ]
        yield mock

def test_research_agent_integration(vcr_config, mock_retriever):
    """
    Test research agent with:
    - Real LLM calls (recorded in cassette)
    - Mocked document retrieval (deterministic)
    """
    recorder = vcr.VCR(**vcr_config)

    with recorder.use_cassette("research_agent_integration.yaml"):
        result = run_research_agent("What are the tax deduction limits?")

    # LLM used real reasoning (from cassette)
    assert "tax" in result.answer.lower()

    # Retriever was called with expected query
    mock_retriever.assert_called()
    call_args = mock_retriever.call_args
    assert "tax" in call_args[0][0].lower() or "deduction" in call_args[0][0].lower()
```

## Debugging Selective Mocking

Add logging to understand what's being recorded vs passed through:

```python
import logging

logger = logging.getLogger("vcr.selective")

def debug_filter(request):
    """Filter with debug logging."""
    host = request.host.lower()

    if "databricks" in host:
        logger.debug(f"PASSTHROUGH: {request.method} {request.uri}")
        return None

    logger.debug(f"RECORDING: {request.method} {request.uri}")
    return request
```

Run tests with logging enabled:

```bash
pytest tests/test_integration.py -v --log-cli-level=DEBUG
```
