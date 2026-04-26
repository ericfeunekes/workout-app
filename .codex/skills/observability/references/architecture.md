# OpenTelemetry Architecture

Core concepts for distributed tracing and observability.

## Trace Context Propagation

### W3C Trace Context Standard

The `traceparent` header carries trace identity across service boundaries:

```
traceparent: 00-{trace_id}-{span_id}-{flags}
             │   │          │         │
             │   │          │         └─ 01 = sampled
             │   │          └─ 16 hex chars (current span)
             │   └─ 32 hex chars (trace ID, shared across all spans)
             └─ Version (always 00)
```

Example:
```
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
```

### How Context Flows

```
React Frontend                    FastAPI Backend               LLM Agent Service
     │                                  │                              │
     │ fetch('/api/chat')               │                              │
     │ + traceparent: 00-abc...-123-01  │                              │
     ├─────────────────────────────────>│                              │
     │                                  │ httpx.post('/agent/run')     │
     │                                  │ + traceparent: 00-abc...-456-01
     │                                  ├─────────────────────────────>│
     │                                  │                              │
     │                                  │<─────────────────────────────┤
     │<─────────────────────────────────┤                              │
```

All three services share the same `trace_id` (abc...), enabling end-to-end correlation.

## OTEL Components

### Tracer Provider

Global singleton that creates tracers:

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

# Set up provider (typically done once at startup)
provider = TracerProvider()
trace.set_tracer_provider(provider)

# Add exporter
provider.add_span_processor(BatchSpanProcessor(exporter))

# Get a tracer for your module
tracer = trace.get_tracer(__name__)
```

### Spans

A span represents a unit of work:

```python
with tracer.start_as_current_span("process_document") as span:
    # Set attributes (indexed, searchable)
    span.set_attribute("document.id", doc_id)
    span.set_attribute("document.pages", page_count)

    # Add events (timestamped logs within span)
    span.add_event("validation_started")

    # Do work...
    result = process(doc)

    span.add_event("validation_completed", {"valid": True})
```

### Span Kinds

| Kind | Use For |
|------|---------|
| `INTERNAL` | Default, internal operations |
| `SERVER` | Handling incoming requests |
| `CLIENT` | Making outgoing requests |
| `PRODUCER` | Async message production |
| `CONSUMER` | Async message consumption |

```python
with tracer.start_as_current_span("db_query", kind=trace.SpanKind.CLIENT) as span:
    span.set_attribute("db.system.name", "postgresql")
    ...
```

### Context Propagation

OTEL automatically manages context within a process. For cross-process propagation:

```python
from opentelemetry.propagate import inject, extract

# Inject context into outgoing request headers
headers = {}
inject(headers)
response = httpx.post(url, headers=headers)

# Extract context from incoming request headers
context = extract(request.headers)
with tracer.start_as_current_span("handle_request", context=context):
    ...
```

## Semantic Conventions

Standard attribute names for interoperability.

### HTTP Spans

```python
span.set_attribute("http.request.method", "POST")
span.set_attribute("url.path", "/api/documents")
span.set_attribute("http.response.status_code", 200)
span.set_attribute("server.address", "api.example.com")
```

### Database Spans

```python
span.set_attribute("db.system.name", "postgresql")
span.set_attribute("db.namespace", "mydb")
span.set_attribute("db.operation.name", "SELECT")
span.set_attribute("db.query.summary", "SELECT users")
span.set_attribute("db.query.text", "SELECT * FROM users WHERE id = ?")
```

### Custom Attributes

For application-specific data:

```python
span.set_attribute("user.id", user_id)
span.set_attribute("tenant.id", tenant_id)
span.set_attribute("feature.flag", "new_upload_flow")
```

## Metrics vs Traces

| Aspect | Traces | Metrics |
|--------|--------|---------|
| Purpose | Debug individual requests | Monitor aggregate behavior |
| Cardinality | High (per-request) | Low (aggregated) |
| Cost | Higher storage | Lower storage |
| Use case | "Why did this request fail?" | "What's the error rate?" |

Use traces for debugging, metrics for dashboards and alerts.

## Local Development Exporters

For local development and debugging, export traces to local backends instead of Azure Monitor.

### Jaeger (Recommended)

Start Jaeger all-in-one container:

```bash
docker run -d --name jaeger \
  -p 16686:16686 \
  -p 4317:4317 \
  -p 4318:4318 \
  jaegertracing/all-in-one:latest

# View traces at http://localhost:16686
```

Configure Python to export to Jaeger:

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource, SERVICE_NAME

# Create provider with local Jaeger exporter
resource = Resource.create({SERVICE_NAME: "my-service"})
provider = TracerProvider(resource=resource)

exporter = OTLPSpanExporter(
    endpoint="http://localhost:4317",
    insecure=True,  # No TLS for local
)
provider.add_span_processor(BatchSpanProcessor(exporter))

trace.set_tracer_provider(provider)
```

### Zipkin Alternative

```bash
docker run -d --name zipkin \
  -p 9411:9411 \
  openzipkin/zipkin

# View traces at http://localhost:9411
```

```python
from opentelemetry.exporter.zipkin.json import ZipkinExporter

exporter = ZipkinExporter(endpoint="http://localhost:9411/api/v2/spans")
```

### Console Exporter (Debugging)

Print spans to console for quick debugging:

```python
from opentelemetry.sdk.trace.export import ConsoleSpanExporter, SimpleSpanProcessor

# Add console exporter alongside other exporters
provider.add_span_processor(SimpleSpanProcessor(ConsoleSpanExporter()))
```

### Environment-Based Configuration

Switch exporters based on environment:

```python
import os
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor, SimpleSpanProcessor
from opentelemetry.sdk.resources import Resource, SERVICE_NAME

def configure_tracing(service_name: str = "my-service"):
    resource = Resource.create({SERVICE_NAME: service_name})
    provider = TracerProvider(resource=resource)

    env = os.environ.get("ENVIRONMENT", "development")

    if env == "production":
        # Azure Monitor in production
        from azure.monitor.opentelemetry.exporter import AzureMonitorTraceExporter
        exporter = AzureMonitorTraceExporter(
            connection_string=os.environ["APPLICATIONINSIGHTS_CONNECTION_STRING"]
        )
        provider.add_span_processor(BatchSpanProcessor(exporter))

    elif env == "development":
        # Jaeger for local development
        jaeger_endpoint = os.environ.get("JAEGER_ENDPOINT", "http://localhost:4317")
        try:
            from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
            exporter = OTLPSpanExporter(endpoint=jaeger_endpoint, insecure=True)
            provider.add_span_processor(BatchSpanProcessor(exporter))
        except Exception:
            # Fall back to console if Jaeger not available
            from opentelemetry.sdk.trace.export import ConsoleSpanExporter
            provider.add_span_processor(SimpleSpanProcessor(ConsoleSpanExporter()))

    elif env == "test":
        # In-memory exporter for tests (see testing.md)
        pass  # Test fixtures handle this

    trace.set_tracer_provider(provider)
    return trace.get_tracer(__name__)
```

### Required Dependencies

```bash
# For OTLP (Jaeger, any OTLP-compatible backend)
pip install opentelemetry-exporter-otlp

# For Zipkin
pip install opentelemetry-exporter-zipkin

# For Azure Monitor
pip install azure-monitor-opentelemetry
```

## Resources

- [OpenTelemetry Python SDK](https://opentelemetry.io/docs/languages/python/)
- [W3C Trace Context Spec](https://www.w3.org/TR/trace-context/)
- [Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/)
