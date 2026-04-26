# Observability Patterns

Common patterns for cache instrumentation, exception handling, service boundaries, and query fingerprinting.

## Exception Handling

### Automatic Recording

Use span options for automatic exception capture:

```python
from opentelemetry import trace

tracer = trace.get_tracer(__name__)

with tracer.start_as_current_span(
    "risky_operation",
    record_exception=True,       # Capture exception details
    set_status_on_exception=True # Set span status to ERROR
) as span:
    span.set_attribute("operation.id", operation_id)
    result = perform_risky_operation()
```

If an exception is raised:
- Exception type, message, and stack trace are recorded as span event
- Span status is set to ERROR
- Exception propagates normally

### Manual Recording with Context

Add context before re-raising:

```python
from opentelemetry.trace import Status, StatusCode

with tracer.start_as_current_span("process_document") as span:
    try:
        result = process(document)
    except ValidationError as e:
        # Add context about what was being validated
        span.set_attribute("validation.field", e.field)
        span.set_attribute("validation.value", str(e.value)[:100])
        span.set_status(Status(StatusCode.ERROR, f"Validation failed: {e.field}"))
        raise
    except ExternalServiceError as e:
        # Capture external service details
        span.set_attribute("external.service", e.service_name)
        span.set_attribute("external.status_code", e.status_code)
        span.record_exception(e)
        span.set_status(Status(StatusCode.ERROR, "External service failure"))
        raise
```

### Error Classification

Add attributes for error analysis:

```python
ERROR_CATEGORIES = {
    ValidationError: "validation",
    PermissionError: "authorization",
    ConnectionError: "connectivity",
    TimeoutError: "timeout",
    ValueError: "bad_input",
}

with tracer.start_as_current_span("operation") as span:
    try:
        result = perform_operation()
    except Exception as e:
        error_category = ERROR_CATEGORIES.get(type(e), "unknown")
        span.set_attribute("error.category", error_category)
        span.set_attribute("error.type", type(e).__name__)
        span.set_attribute("error.retriable", error_category in ["connectivity", "timeout"])
        raise
```

## Cache Instrumentation

No official OTEL semantic convention exists. Use consistent custom attributes.

### Basic Pattern

```python
from opentelemetry import trace
from typing import TypeVar, Optional, Callable

T = TypeVar('T')
tracer = trace.get_tracer(__name__)

async def cached_get(
    key: str,
    fetch_func: Callable[[], T],
    backend: str = "redis",
    ttl_seconds: int = 300,
) -> T:
    """Get from cache or fetch and cache."""

    with tracer.start_as_current_span("cache.get") as span:
        span.set_attribute("cache.backend", backend)
        span.set_attribute("cache.key", key)
        span.set_attribute("cache.ttl_seconds", ttl_seconds)

        # Try cache
        cached_value = await redis.get(key)

        if cached_value is not None:
            span.set_attribute("cache.hit", True)
            return deserialize(cached_value)

        span.set_attribute("cache.hit", False)

    # Cache miss - fetch fresh data
    with tracer.start_as_current_span("cache.fetch") as span:
        span.set_attribute("cache.key", key)
        value = await fetch_func()

    # Store in cache
    with tracer.start_as_current_span("cache.set") as span:
        span.set_attribute("cache.backend", backend)
        span.set_attribute("cache.key", key)
        await redis.setex(key, ttl_seconds, serialize(value))

    return value
```

### Cache Metrics

Track cache performance over time:

```python
from opentelemetry import metrics

meter = metrics.get_meter(__name__)

cache_hits = meter.create_counter(
    "cache.hits",
    description="Number of cache hits",
    unit="1"
)

cache_misses = meter.create_counter(
    "cache.misses",
    description="Number of cache misses",
    unit="1"
)

cache_latency = meter.create_histogram(
    "cache.latency",
    description="Cache operation latency",
    unit="ms"
)

async def get_cached(key: str, backend: str = "redis") -> Optional[bytes]:
    start = time.monotonic()

    result = await redis.get(key)

    latency_ms = (time.monotonic() - start) * 1000
    labels = {"backend": backend, "key_prefix": key.split(":")[0]}

    cache_latency.record(latency_ms, labels)

    if result is not None:
        cache_hits.add(1, labels)
    else:
        cache_misses.add(1, labels)

    return result
```

### Key Prefix Tracking

Group cache operations by key pattern:

```python
def extract_key_prefix(key: str) -> str:
    """Extract prefix from cache key for grouping."""
    # user:123:profile -> user
    # doc:abc:content -> doc
    parts = key.split(":")
    return parts[0] if parts else "unknown"

span.set_attribute("cache.key_prefix", extract_key_prefix(key))
```

## Database Query Fingerprinting

Use `db.query.summary` for low-cardinality grouping.

### Summary Generation

```python
import re
from typing import Optional

def generate_query_summary(sql: str) -> str:
    """
    Generate low-cardinality summary from SQL.

    Examples:
        SELECT * FROM users WHERE id = ? -> SELECT users
        INSERT INTO orders (id, ...) VALUES (?, ...) -> INSERT orders
        UPDATE users SET name = ? WHERE id = ? -> UPDATE users
    """
    sql_upper = sql.strip().upper()

    # Extract operation
    operation_match = re.match(r'^(\w+)', sql_upper)
    operation = operation_match.group(1) if operation_match else "QUERY"

    # Extract tables
    tables = []

    # FROM clause
    from_matches = re.findall(r'\bFROM\s+["\']?(\w+)["\']?', sql_upper)
    tables.extend(from_matches)

    # INTO clause
    into_match = re.search(r'\bINTO\s+["\']?(\w+)["\']?', sql_upper)
    if into_match:
        tables.append(into_match.group(1))

    # UPDATE clause
    update_match = re.search(r'^UPDATE\s+["\']?(\w+)["\']?', sql_upper)
    if update_match:
        tables.append(update_match.group(1))

    # JOIN clauses
    join_matches = re.findall(r'\bJOIN\s+["\']?(\w+)["\']?', sql_upper)
    tables.extend(join_matches)

    # Remove duplicates, preserve order
    seen = set()
    unique_tables = []
    for t in tables:
        t_lower = t.lower()
        if t_lower not in seen:
            seen.add(t_lower)
            unique_tables.append(t_lower)

    return f"{operation} {' '.join(unique_tables)}" if unique_tables else operation


def sanitize_query(sql: str) -> str:
    """Replace literals with placeholders."""
    # String literals
    sql = re.sub(r"'[^']*'", "?", sql)
    # Numeric literals (not in identifiers)
    sql = re.sub(r'(?<![a-zA-Z_])\d+(?![a-zA-Z_])', "?", sql)
    # Collapse IN clauses
    sql = re.sub(r'\bIN\s*\(\s*\?\s*(?:,\s*\?\s*)*\)', "IN (?)", sql)
    return sql
```

### Database Wrapper

```python
class TracedDatabase:
    def __init__(self, pool):
        self._pool = pool
        self._tracer = trace.get_tracer(__name__)

    async def fetch(self, query: str, *args) -> list:
        summary = generate_query_summary(query)

        with self._tracer.start_as_current_span(
            summary,
            kind=trace.SpanKind.CLIENT
        ) as span:
            span.set_attribute("db.system.name", "postgresql")
            span.set_attribute("db.query.summary", summary)
            span.set_attribute("db.query.text", sanitize_query(query))
            span.set_attribute("db.operation.name", summary.split()[0])

            try:
                async with self._pool.acquire() as conn:
                    result = await conn.fetch(query, *args)
                    span.set_attribute("db.response.rows", len(result))
                    return result
            except Exception as e:
                span.set_attribute("db.response.status_code",
                                 getattr(e, 'sqlstate', 'ERROR'))
                raise

    async def execute(self, query: str, *args) -> str:
        summary = generate_query_summary(query)

        with self._tracer.start_as_current_span(summary) as span:
            span.set_attribute("db.system.name", "postgresql")
            span.set_attribute("db.query.summary", summary)

            async with self._pool.acquire() as conn:
                result = await conn.execute(query, *args)
                # result is like "INSERT 0 1" or "UPDATE 5"
                span.set_attribute("db.response.status", result)
                return result
```

### Identifying Caching Candidates

Query Azure Monitor for high-frequency, slow reads:

```kusto
dependencies
| where timestamp > ago(24h)
| where type == "postgresql"
| extend query_summary = tostring(customDimensions["db.query.summary"])
| where query_summary startswith "SELECT"
| summarize
    executions = count(),
    avg_duration_ms = avg(duration),
    p95_duration_ms = percentile(duration, 95),
    total_time_ms = sum(duration)
    by query_summary
| where executions > 100 and avg_duration_ms > 10
| extend cache_benefit_score = executions * avg_duration_ms / 1000
| order by cache_benefit_score desc
| take 20
```

## Service Boundary Patterns

### Span Naming Conventions

| Context | Pattern | Example |
|---------|---------|---------|
| HTTP Server | `{method} {route}` | `POST /api/documents` |
| HTTP Client | `HTTP {method}` | `HTTP POST` |
| Database | `{operation} {table}` | `SELECT users` |
| Cache | `cache.{operation}` | `cache.get` |
| Queue | `{operation} {queue}` | `publish orders` |
| Custom | `{domain}.{action}` | `document.process` |

### Required Attributes at Boundaries

```python
# Service identification
span.set_attribute("service.name", "caila-api")
span.set_attribute("service.version", "1.2.0")

# Downstream service
span.set_attribute("peer.service", "agent-service")

# Request correlation
span.set_attribute("http.request.id", request_id)
span.set_attribute("user.id", user_id)
span.set_attribute("tenant.id", tenant_id)
```

### Outgoing Request Context

```python
import httpx
from opentelemetry import trace
from opentelemetry.propagate import inject

tracer = trace.get_tracer(__name__)

async def call_downstream_service(endpoint: str, payload: dict) -> dict:
    with tracer.start_as_current_span(
        "HTTP POST",
        kind=trace.SpanKind.CLIENT
    ) as span:
        span.set_attribute("http.request.method", "POST")
        span.set_attribute("url.full", endpoint)
        span.set_attribute("peer.service", "agent-service")

        # Inject trace context into headers
        headers = {}
        inject(headers)

        async with httpx.AsyncClient() as client:
            response = await client.post(endpoint, json=payload, headers=headers)

            span.set_attribute("http.response.status_code", response.status_code)

            if not response.is_success:
                span.set_attribute("error", True)

            return response.json()
```

### Incoming Request Context

```python
from opentelemetry.propagate import extract
from fastapi import Request

@app.middleware("http")
async def extract_trace_context(request: Request, call_next):
    # Extract trace context from incoming headers
    context = extract(request.headers)

    # Context is automatically used for spans created during request handling
    with tracer.start_as_current_span(
        f"{request.method} {request.url.path}",
        context=context,
        kind=trace.SpanKind.SERVER
    ):
        response = await call_next(request)
        return response
```

## Retry and Circuit Breaker Tracing

### Retry Tracking

```python
from tenacity import retry, stop_after_attempt, wait_exponential

@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=1, max=10),
    before_sleep=lambda retry_state: log_retry(retry_state)
)
async def call_external_service():
    with tracer.start_as_current_span("external_call") as span:
        span.set_attribute("retry.attempt",
                          call_external_service.retry.statistics.get("attempt_number", 1))
        return await make_request()

def log_retry(retry_state):
    span = trace.get_current_span()
    if span.is_recording():
        span.add_event("retry_scheduled", {
            "retry.attempt": retry_state.attempt_number,
            "retry.wait_seconds": retry_state.next_action.sleep,
        })
```

### Circuit Breaker State

```python
class TracedCircuitBreaker:
    def __init__(self, name: str):
        self.name = name
        self.state = "closed"
        self.tracer = trace.get_tracer(__name__)

    async def call(self, func):
        with self.tracer.start_as_current_span(f"circuit_breaker:{self.name}") as span:
            span.set_attribute("circuit_breaker.name", self.name)
            span.set_attribute("circuit_breaker.state", self.state)

            if self.state == "open":
                span.set_attribute("circuit_breaker.rejected", True)
                raise CircuitBreakerOpen(self.name)

            try:
                result = await func()
                self._on_success()
                return result
            except Exception as e:
                self._on_failure()
                span.set_attribute("circuit_breaker.new_state", self.state)
                raise
```

## Background Job Tracing

For async tasks (Celery, ARQ, etc.):

```python
from opentelemetry.propagate import inject, extract

# Producer: Create task with trace context
def enqueue_task(task_name: str, payload: dict):
    with tracer.start_as_current_span(
        f"enqueue:{task_name}",
        kind=trace.SpanKind.PRODUCER
    ) as span:
        # Inject trace context into task metadata
        carrier = {}
        inject(carrier)

        task_message = {
            "name": task_name,
            "payload": payload,
            "trace_context": carrier,
        }

        queue.publish(task_message)
        span.set_attribute("messaging.destination", task_name)

# Consumer: Extract and continue trace
def process_task(task_message: dict):
    # Extract trace context from task
    context = extract(task_message.get("trace_context", {}))

    with tracer.start_as_current_span(
        f"process:{task_message['name']}",
        context=context,
        kind=trace.SpanKind.CONSUMER,
        links=[trace.Link(context)]  # Link to producer span
    ) as span:
        span.set_attribute("messaging.operation", "process")
        # Process the task...
```
