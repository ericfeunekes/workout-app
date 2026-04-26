# Cassette Editing Guide

Manually editing VCR cassettes to create test scenarios that are difficult or impossible to trigger naturally.

## Cassette Structure

VCR cassettes are YAML files with a simple structure:

```yaml
version: 1
interactions:
- request:
    body: '{"model": "gpt-4", "messages": [...]}'
    headers:
      content-type:
      - application/json
    method: POST
    uri: https://api.openai.com/v1/chat/completions
  response:
    body:
      string: '{"id": "chatcmpl-xxx", "choices": [...]}'
    headers:
      content-type:
      - application/json
    status:
      code: 200
      message: OK
```

## Safe Editing Practices

### 1. Preserve YAML Structure

Always validate YAML after editing:

```bash
python -c "import yaml; yaml.safe_load(open('cassette.yaml'))"
```

### 2. Keep Request Matching Aligned

If editing the request, ensure it still matches the `match_on` criteria:

```yaml
# If match_on includes "path", this change breaks matching:
# BEFORE
uri: https://api.openai.com/v1/chat/completions
# AFTER (breaks!)
uri: https://api.openai.com/v2/chat/completions
```

### 3. Maintain JSON Validity in Body

Response bodies are often JSON strings. Validate after editing:

```bash
python -c "import json; json.loads('''...your json...''')"
```

### 4. Backup Before Editing

```bash
cp cassette.yaml cassette.yaml.bak
```

## Common Edit Patterns

### Inject Tool Calls

Add or modify tool calls in LLM responses:

```yaml
# Original: no tool calls
response:
  body:
    string: '{"choices":[{"message":{"role":"assistant","content":"Hello"}}]}'

# Edited: add tool call
response:
  body:
    string: '{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_123","type":"function","function":{"name":"search_documents","arguments":"{\"query\":\"tax deductions\"}"}}]}}]}'
```

### Add Multiple Tool Calls

Test handling of parallel tool calls:

```yaml
response:
  body:
    string: |
      {"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[
        {"id":"call_1","type":"function","function":{"name":"search_documents","arguments":"{\"query\":\"income tax\"}"}},
        {"id":"call_2","type":"function","function":{"name":"search_documents","arguments":"{\"query\":\"deductions\"}"}},
        {"id":"call_3","type":"function","function":{"name":"calculate","arguments":"{\"expr\":\"50000*0.22\"}"}}
      ]}}]}
```

### Inject Error Responses

Test error handling paths:

```yaml
# Rate limit error
response:
  body:
    string: '{"error":{"message":"Rate limit exceeded","type":"rate_limit_error","code":"rate_limit_exceeded"}}'
  status:
    code: 429
    message: Too Many Requests

# Server error
response:
  body:
    string: '{"error":{"message":"Internal server error","type":"server_error"}}'
  status:
    code: 500
    message: Internal Server Error

# Bad request
response:
  body:
    string: '{"error":{"message":"Invalid model specified","type":"invalid_request_error","param":"model"}}'
  status:
    code: 400
    message: Bad Request
```

### Test Malformed Responses

Verify parser resilience:

```yaml
# Truncated JSON
response:
  body:
    string: '{"choices":[{"message":{"content":"partial resp'

# Missing required field
response:
  body:
    string: '{"choices":[{"message":{}}]}'

# Extra unexpected fields
response:
  body:
    string: '{"choices":[{"message":{"content":"test","unexpected_field":123}}]}'

# Wrong type
response:
  body:
    string: '{"choices":"not an array"}'
```

### Modify Content for Edge Cases

```yaml
# Empty content
response:
  body:
    string: '{"choices":[{"message":{"content":""}}]}'

# Unicode content
response:
  body:
    string: '{"choices":[{"message":{"content":"Testing unicode: \u00e9\u00e8\u00ea \u4e2d\u6587"}}]}'

# Very long content (test truncation)
response:
  body:
    string: '{"choices":[{"message":{"content":"Lorem ipsum..."}}]}'  # Add 10k+ chars
```

### Streaming Response Edits

Streaming responses are recorded as multiple chunks. Edit carefully:

```yaml
# SSE format
response:
  body:
    string: |
      data: {"choices":[{"delta":{"role":"assistant"}}]}

      data: {"choices":[{"delta":{"content":"Hello"}}]}

      data: {"choices":[{"delta":{"content":" world"}}]}

      data: [DONE]
```

## Creating Variant Cassettes

For systematic testing, create cassette variants:

```
tests/data/cassettes/
  openai_gpt-4.yaml           # Base recording
  openai_gpt-4_rate_limit.yaml # Edited: 429 response
  openai_gpt-4_timeout.yaml    # Edited: connection timeout
  openai_gpt-4_multi_tool.yaml # Edited: multiple tool calls
```

Use in tests:

```python
@pytest.mark.parametrize("cassette,expected_error", [
    ("openai_gpt-4.yaml", None),
    ("openai_gpt-4_rate_limit.yaml", RateLimitError),
    ("openai_gpt-4_timeout.yaml", TimeoutError),
])
def test_error_handling(cassette, expected_error, vcr_config):
    recorder = vcr.VCR(**vcr_config)
    with recorder.use_cassette(cassette):
        if expected_error:
            with pytest.raises(expected_error):
                call_api()
        else:
            result = call_api()
            assert result is not None
```

## Automation: Cassette Generation Script

For systematic edge case generation:

```python
import yaml
import json
import copy

def load_cassette(path):
    with open(path) as f:
        return yaml.safe_load(f)

def save_cassette(data, path):
    with open(path, 'w') as f:
        yaml.dump(data, f, default_flow_style=False)

def inject_error(cassette, status_code, error_message):
    """Create error variant of cassette."""
    modified = copy.deepcopy(cassette)
    for interaction in modified['interactions']:
        interaction['response']['status'] = {
            'code': status_code,
            'message': error_message
        }
        interaction['response']['body']['string'] = json.dumps({
            'error': {'message': error_message, 'type': 'api_error'}
        })
    return modified

# Usage
base = load_cassette('tests/data/cassettes/openai_gpt-4.yaml')
rate_limit = inject_error(base, 429, 'Rate limit exceeded')
save_cassette(rate_limit, 'tests/data/cassettes/openai_gpt-4_rate_limit.yaml')
```

## Validation Checklist

Before committing edited cassettes:

- [ ] YAML parses without errors
- [ ] JSON bodies are valid
- [ ] Request still matches `match_on` criteria
- [ ] Status code matches expected scenario
- [ ] Headers are consistent (content-type matches body format)
- [ ] No sensitive data accidentally added
