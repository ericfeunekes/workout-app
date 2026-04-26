---
name: observability
description: Use when setting up observability for new services, adding or updating (distributed) tracing, instrumenting Databricks pipelines, or implementing user behavior analytics.
---
# Observability

Canonical patterns for distributed tracing and observability across React frontends, FastAPI backends, LLM agents (MLflow), and Databricks data pipelines, with Azure Monitor as the primary backend.

## When to Use This Skill

- Setting up observability for a new service or application
- Adding distributed tracing across React → FastAPI → LLM agent flows
- Instrumenting Databricks/Spark/DLT pipelines for monitoring
- Configuring Azure Application Insights for production
- Implementing user behavior analytics (sessions, funnels, retention)
- Debugging distributed systems with correlated traces
- Identifying caching opportunities from database query patterns

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│  React Frontend                                                      │
│  @microsoft/applicationinsights-web + React plugin                  │
│  - Click Analytics (automatic user interactions)                    │
│  - Custom events (trackEvent for business actions)                  │
│  - W3C traceparent header propagation                               │
└─────────────────────┬───────────────────────────────────────────────┘
                      │ traceparent: 00-{trace_id}-{span_id}-01
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│  FastAPI Backend                                                     │
│  azure-monitor-opentelemetry + FastAPIInstrumentor                  │
│  - HTTP request/response spans (automatic)                          │
│  - Database spans via asyncpg instrumentation                       │
│  - Custom spans for business logic                                  │
│  - Exception capture with record_exception=True                     │
└─────────────────────┬───────────────────────────────────────────────┘
                      │ traceparent header forwarded
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│  LLM Agent Service                                                   │
│  MLflow autolog + OpenTelemetry                                     │
│  - LLM calls traced to MLflow (token usage, model info)             │
│  - HTTP/DB spans to Azure Monitor                                   │
│  - Separate trace contexts: MLflow for GenAI, Azure for ops         │
└─────────────────────┬───────────────────────────────────────────────┘
                      │
          ┌───────────┴───────────┐
          ▼                       ▼
┌──────────────────┐    ┌──────────────────┐
│  MLflow          │    │  Azure Monitor   │
│  (GenAI traces,  │    │  (full ops       │
│   eval, judges)  │    │   observability) │
└──────────────────┘    └──────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│  Databricks / Spark Pipelines                                        │
│  - JVM agent for automatic metrics/logs                             │
│  - StreamingQueryListener for batch spans                           │
│  - DLT event log for pipeline observability                         │
│  - Custom PySpark spans for ETL stages                              │
└─────────────────────────────────────────────────────────────────────┘
```

## Decision Points

### Backend Selection

| Scenario | Primary Backend | Secondary |
|----------|-----------------|-----------|
| Web app + API observability | Azure Monitor | - |
| LLM/Agent debugging | MLflow | Azure Monitor |
| Data pipeline monitoring | Azure Monitor | DLT Event Log |
| Full stack with GenAI | Azure Monitor | MLflow (agents only) |

### Sampling Strategy

| Daily Trace Volume | Approach |
|--------------------|----------|
| < 100K | No sampling (`sampling_ratio=1.0`) |
| 100K - 1M | Head-based 50% |
| 1M - 10M | Head-based 10-20% |
| > 10M | Tail-based with OTEL Collector |

For guaranteed error capture at scale, use tail-based sampling with an OpenTelemetry Collector. See `reference:observability/sampling.md`.

## Quick Start

### FastAPI with Azure Monitor

```python
from azure.monitor.opentelemetry import configure_azure_monitor
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.asyncpg import AsyncPGInstrumentor

# Initialize before creating app
configure_azure_monitor(
    connection_string=os.environ["APPLICATIONINSIGHTS_CONNECTION_STRING"],
)

app = FastAPI()

# Instrument FastAPI and database
FastAPIInstrumentor.instrument_app(app)
AsyncPGInstrumentor().instrument()
```

See `reference:observability/fastapi.md` for complete setup including custom attributes, exception handling, and request hooks.

### React with Azure Monitor

```typescript
import { ApplicationInsights, DistributedTracingModes } from '@microsoft/applicationinsights-web';
import { ReactPlugin } from '@microsoft/applicationinsights-react-js';

const reactPlugin = new ReactPlugin();
const appInsights = new ApplicationInsights({
  config: {
    connectionString: process.env.REACT_APP_APPINSIGHTS_CONNECTION_STRING,
    extensions: [reactPlugin],
    distributedTracingMode: DistributedTracingModes.W3C,
    enableCorsCorrelation: true,  // Critical for cross-origin API calls
    enableAutoRouteTracking: true,
  }
});

appInsights.loadAppInsights();
```

See `reference:observability/react-frontend.md` for click analytics, user tracking, and custom events.

### MLflow Agent Tracing

```python
import mlflow

# MLflow handles its own traces for GenAI
mlflow.set_tracking_uri("http://mlflow-server:5000")
mlflow.openai.autolog()  # or anthropic, langchain, etc.

# Azure Monitor handles HTTP/DB spans separately
from azure.monitor.opentelemetry import configure_azure_monitor
configure_azure_monitor(connection_string="...")
```

See `reference:observability/mlflow.md` for configuration details.

### Spark Streaming Instrumentation

```python
from pyspark.sql.streaming import StreamingQueryListener
from opentelemetry import trace

class OpenTelemetryListener(StreamingQueryListener):
    def __init__(self):
        self.tracer = trace.get_tracer(__name__)

    def onQueryProgress(self, event):
        progress = event.progress
        with self.tracer.start_as_current_span("streaming_batch") as span:
            span.set_attribute("spark.streaming.batch_id", progress.batchId)
            span.set_attribute("spark.streaming.num_input_rows", progress.numInputRows)

spark.streams.addListener(OpenTelemetryListener())
```

See `reference:observability/databricks.md` for complete pipeline instrumentation.

## Key Practices

### Exception Handling

Always ensure exceptions are captured in traces:

```python
with tracer.start_as_current_span(
    "operation",
    record_exception=True,      # Auto-record exceptions
    set_status_on_exception=True # Auto-set error status
) as span:
    try:
        do_work()
    except Exception:
        # Exception already recorded, just re-raise
        raise
```

### Cache Instrumentation

No official OTEL semantic convention exists. Use custom attributes:

```python
with tracer.start_as_current_span("cache.get") as span:
    span.set_attribute("cache.backend", "redis")
    span.set_attribute("cache.key", key)
    result = await redis.get(key)
    span.set_attribute("cache.hit", result is not None)
```

### Database Query Fingerprinting

Use `db.query.summary` for low-cardinality grouping:

```python
# Query: SELECT * FROM users WHERE id = ?
# Summary: SELECT users
span.set_attribute("db.query.summary", "SELECT users")
```

This enables Azure Monitor queries to identify caching candidates. See `reference:observability/patterns.md`.

### User Analytics

Track authenticated users for session correlation:

```typescript
// After login
appInsights.setAuthenticatedUserContext(userId, tenantId, true);

// Track business events for funnels
appInsights.trackEvent({ name: 'DocumentUpload.Completed' });
```

Azure Monitor provides Users, Sessions, Funnels, Cohorts, Retention, and Impact analysis tools. See `reference:observability/azure-monitor.md`.

## References

- `reference:observability/architecture.md` - OTEL concepts, trace context propagation, local exporters
- `reference:observability/fastapi.md` - FastAPI + asyncpg instrumentation, lifespan initialization
- `reference:observability/react-frontend.md` - Browser tracing, click analytics, user tracking
- `reference:observability/mlflow.md` - LLM agent tracing, Databricks experiment export
- `reference:observability/azure-monitor.md` - Azure-specific setup, usage analytics, KQL queries
- `reference:observability/sampling.md` - Head vs tail sampling, Collector config
- `reference:observability/databricks.md` - Spark, DLT, streaming pipelines
- `reference:observability/patterns.md` - Cache, exceptions, service boundaries, query fingerprinting
- `reference:observability/testing.md` - Pytest fixtures for OTEL and MLflow, local Jaeger export

## Related Skills

- release-engineering
- security
