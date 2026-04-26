---
name: vcr-http-testing
description: Use this skill when writing tests that need to record and replay HTTP interactions. Covers VCR (vcrpy) configuration for httpx, cassette management, parameterized fixtures, and patterns for LLM API testing, manual cassette editing, and selective endpoint mocking.
---
# VCR HTTP Testing

Record HTTP interactions once, replay them in tests forever. VCR eliminates flaky network dependencies while preserving realistic API behavior.

## When to Use VCR

- **LLM API testing**: Record responses from multiple providers, validate parsers against all
- **Integration tests**: Real LLM calls + mocked infrastructure endpoints
- **Edge case testing**: Edit cassettes to inject unusual responses (tool calls, errors, malformed JSON)
- **Cross-provider validation**: Same test logic against OpenAI, Azure, Bedrock, Vertex responses

## Core Benefits

1. **Record once, replay many**: Single recording drives multiple test assertions
2. **Deterministic tests**: No network flakiness, same response every time
3. **Fast execution**: Replay is instant, no API latency
4. **Editable fixtures**: Modify cassettes to craft scenarios that are hard to trigger naturally

## Quick Start

### Installation

```toml
# pyproject.toml
dependencies = [
    "vcrpy>=6.0.2",  # 6.0.2+ required for httpx streaming
]
```

### Basic Configuration

```python
# tests/conftest.py
import pytest

@pytest.fixture(scope="module")
def vcr_config():
    return {
        "record_mode": "new_episodes",
        "cassette_library_dir": "tests/data/cassettes",
        "match_on": ["method", "scheme", "host", "port", "path"],
        "filter_headers": ["authorization", "x-api-key", "api-key"],
    }
```

### Recording and Replaying

```python
import vcr

def test_llm_response(vcr_config):
    recorder = vcr.VCR(**vcr_config)

    with recorder.use_cassette("test_llm_response.yaml"):
        # First run: records real HTTP calls
        # Subsequent runs: replays from cassette
        response = call_llm_api("What is 2+2?")
        assert "4" in response
```

## Patterns

### Parameterized Multi-Model Testing

Record once per model, run same tests against all:

```python
from dataclasses import dataclass

@dataclass(frozen=True)
class ModelConfig:
    model_id: str
    has_streaming: bool

MODELS = [
    ModelConfig("openai.gpt-4", has_streaming=True),
    ModelConfig("azure.gpt-4", has_streaming=True),
    ModelConfig("bedrock.claude-3", has_streaming=True),
]

@pytest.fixture(scope="module", params=MODELS, ids=lambda m: m.model_id)
def model_response(request, vcr_config):
    config = request.param
    cassette_name = config.model_id.replace(".", "_").replace("/", "_")

    recorder = vcr.VCR(**vcr_config)
    with recorder.use_cassette(f"{cassette_name}.yaml"):
        response = run_model(config.model_id)

    return config, response

class TestCrossModelBehavior:
    def test_produces_valid_output(self, model_response):
        config, response = model_response
        assert response.content is not None
```

### Selective Endpoint Mocking

Real LLM calls + mocked infrastructure:

```python
@pytest.fixture(scope="module")
def vcr_config():
    return {
        "record_mode": "new_episodes",
        "cassette_library_dir": "tests/data/cassettes",
        "match_on": ["method", "scheme", "host", "port", "path"],
        "filter_headers": ["authorization", "x-api-key"],
        # Let Databricks calls through (don't record)
        "ignore_hosts": ["adb-*.azuredatabricks.net"],
    }
```

Or use `before_record_request` for fine-grained control:

```python
def filter_databricks_requests(request):
    """Skip recording Databricks API calls."""
    if "databricks" in request.host:
        return None  # Don't record
    return request

@pytest.fixture(scope="module")
def vcr_config():
    return {
        "record_mode": "new_episodes",
        "cassette_library_dir": "tests/data/cassettes",
        "before_record_request": filter_databricks_requests,
    }
```

### Fixture Scope Considerations

VCR cassettes work best with module-scoped fixtures when recording is expensive:

```python
# CORRECT: Module-scoped fixture with VCR
@pytest.fixture(scope="module", params=MODELS, ids=lambda m: m.model_id)
def parsed_events(request, vcr_config):
    recorder = vcr.VCR(**vcr_config)
    with recorder.use_cassette(str(cassette_path)):
        chunks = run_graph()  # Expensive - only runs once per model
    return parse_stream(chunks)

# Tests run many times against same recorded data
class TestEventKinds:
    def test_has_completion(self, parsed_events):
        assert any(e.kind == "completion" for e in parsed_events)

    def test_has_tool_calls(self, parsed_events):
        assert any(e.kind == "tool_call" for e in parsed_events)
```

## Cassette Management

### Directory Structure

```
tests/
  data/
    cassettes/
      .gitkeep
      openai_gpt-4.yaml
      azure_gpt-4.yaml
      bedrock_claude-3.yaml
```

### Naming Conventions

Sanitize model IDs for filesystem safety:

```python
import re

def sanitize_cassette_name(model_id: str) -> str:
    """Convert model ID to filesystem-safe cassette name."""
    sanitized = re.sub(r"[^A-Za-z0-9_-]+", "_", model_id).strip("_")
    return sanitized or "default"

# "openai.gpt-4.1-mini" -> "openai_gpt-4_1-mini"
# "bedrock/anthropic.claude-3" -> "bedrock_anthropic_claude-3"
```

### Refreshing Stale Cassettes

When API responses change:

```bash
# Delete specific cassette and re-record
rm tests/data/cassettes/openai_gpt-4.yaml
pytest tests/test_llm.py -k "openai" -v

# Or delete all and re-record
rm -rf tests/data/cassettes/*.yaml
pytest tests/test_llm.py -v
```

## Editing Cassettes for Edge Cases

Cassettes are YAML files that can be manually edited to test scenarios that are hard to trigger naturally.

### Tool Call Variations

Record a basic tool call, then duplicate and modify:

```yaml
# Original recorded response
- request:
    uri: https://api.openai.com/v1/chat/completions
  response:
    body:
      string: '{"choices":[{"message":{"tool_calls":[{"function":{"name":"search","arguments":"{\"query\":\"tax rules\"}"}}]}}]}'

# Duplicate and edit for edge case: multiple tool calls
- request:
    uri: https://api.openai.com/v1/chat/completions
  response:
    body:
      string: '{"choices":[{"message":{"tool_calls":[{"function":{"name":"search","arguments":"{\"query\":\"tax rules\"}"}},{"function":{"name":"calculate","arguments":"{\"expr\":\"100*0.15\"}"}}]}}]}'
```

### Error Response Testing

Inject error responses to test error handling:

```yaml
- request:
    uri: https://api.openai.com/v1/chat/completions
  response:
    status:
      code: 429
      message: Too Many Requests
    body:
      string: '{"error":{"message":"Rate limit exceeded","type":"rate_limit_error"}}'
```

### Malformed Response Testing

Test parser resilience:

```yaml
- request:
    uri: https://api.openai.com/v1/chat/completions
  response:
    body:
      string: '{"choices":[{"message":{"content":"partial response'  # Truncated JSON
```

## Troubleshooting

### Scope Mismatch Error

```
ScopeMismatch: You tried to access the function scoped fixture 'vcr'
with a module scoped request object
```

**Fix**: Use `vcr.VCR()` directly instead of pytest-recording's `vcr` fixture:

```python
# BAD: pytest-recording's vcr fixture is function-scoped
@pytest.fixture(scope="module")
def data(vcr):  # Scope mismatch!
    with vcr.use_cassette("test.yaml"):
        ...

# GOOD: Create VCR instance directly
@pytest.fixture(scope="module")
def data(vcr_config):
    recorder = vcr.VCR(**vcr_config)
    with recorder.use_cassette("test.yaml"):
        ...
```

### Cassette Not Matching

VCR can't find a matching request in the cassette.

**Common causes**:
1. Request body changed (timestamps, UUIDs)
2. Query parameters differ
3. Headers changed

**Fix**: Adjust `match_on` to ignore volatile fields:

```python
vcr_config = {
    "match_on": ["method", "host", "path"],  # Ignore query, body
}
```

### Streaming Responses Not Recording

**Requirement**: vcrpy >= 6.0.2 for httpx streaming support.

```bash
uv add "vcrpy>=6.0.2"
```

### Cassettes Growing Too Large

Streaming responses create large cassettes.

**Options**:
1. Compress in git (cassettes are highly compressible YAML)
2. Use binary cassette format
3. Record shorter interactions for unit tests

## Resources

For detailed patterns, see:
- `references/configuration.md` - Complete VCR configuration options
- `references/cassette-editing.md` - Safe cassette modification patterns
- `references/selective-mocking.md` - Mixing real and mocked endpoints
