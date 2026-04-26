# FastAPI Instrumentation

Complete setup for FastAPI with OpenTelemetry and Azure Monitor.

## Installation

```bash
pip install azure-monitor-opentelemetry
pip install opentelemetry-instrumentation-fastapi
pip install opentelemetry-instrumentation-asyncpg
pip install opentelemetry-instrumentation-httpx  # for outgoing requests
```

## App Initialization with Lifespan

Integrate tracing into FastAPI app lifecycle with clear error handling:

```python
# app/telemetry.py
import os
import logging
from contextlib import asynccontextmanager
from typing import Optional

from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider

logger = logging.getLogger(__name__)

class TelemetryConfig:
    """Telemetry configuration with validation."""

    def __init__(self):
        self.connection_string = os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING")
        self.service_name = os.environ.get("SERVICE_NAME", "fastapi-service")
        self.service_version = os.environ.get("SERVICE_VERSION", "0.0.0")
        self.environment = os.environ.get("ENVIRONMENT", "development")
        self.sampling_ratio = float(os.environ.get("OTEL_SAMPLING_RATIO", "1.0"))
        self.enabled = os.environ.get("TELEMETRY_ENABLED", "true").lower() == "true"

    def validate(self) -> list[str]:
        """Return list of configuration errors."""
        errors = []
        if self.enabled and not self.connection_string:
            errors.append(
                "APPLICATIONINSIGHTS_CONNECTION_STRING required when TELEMETRY_ENABLED=true"
            )
        if not 0 <= self.sampling_ratio <= 1:
            errors.append(f"OTEL_SAMPLING_RATIO must be 0-1, got {self.sampling_ratio}")
        return errors


_telemetry_initialized = False


def configure_telemetry(app) -> None:
    """
    Configure OpenTelemetry for the FastAPI app.

    Raises:
        RuntimeError: If configuration is invalid
    """
    global _telemetry_initialized

    config = TelemetryConfig()

    # Validate configuration
    errors = config.validate()
    if errors:
        error_msg = "Telemetry configuration errors:\n" + "\n".join(f"  - {e}" for e in errors)
        logger.error(error_msg)
        raise RuntimeError(error_msg)

    if not config.enabled:
        logger.info("Telemetry disabled via TELEMETRY_ENABLED=false")
        return

    if _telemetry_initialized:
        logger.warning("Telemetry already initialized, skipping")
        return

    try:
        from azure.monitor.opentelemetry import configure_azure_monitor
        from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
        from opentelemetry.instrumentation.asyncpg import AsyncPGInstrumentor
        from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
        from opentelemetry.sdk.resources import Resource, SERVICE_NAME, SERVICE_VERSION

        # Create resource
        resource = Resource.create({
            SERVICE_NAME: config.service_name,
            SERVICE_VERSION: config.service_version,
            "deployment.environment": config.environment,
        })

        # Configure Azure Monitor
        configure_azure_monitor(
            connection_string=config.connection_string,
            resource=resource,
            sampling_ratio=config.sampling_ratio,
            logger_name=config.service_name,
        )

        # Instrument FastAPI
        FastAPIInstrumentor.instrument_app(
            app,
            excluded_urls="health,ready,metrics,favicon.ico",
        )

        # Instrument database (if available)
        try:
            AsyncPGInstrumentor().instrument()
        except Exception as e:
            logger.debug(f"asyncpg instrumentation skipped: {e}")

        # Instrument HTTP client (if available)
        try:
            HTTPXClientInstrumentor().instrument()
        except Exception as e:
            logger.debug(f"httpx instrumentation skipped: {e}")

        _telemetry_initialized = True
        logger.info(
            f"Telemetry configured: service={config.service_name}, "
            f"env={config.environment}, sampling={config.sampling_ratio}"
        )

    except ImportError as e:
        error_msg = f"Missing telemetry dependency: {e}. Install azure-monitor-opentelemetry"
        logger.error(error_msg)
        raise RuntimeError(error_msg) from e
    except Exception as e:
        error_msg = f"Failed to configure telemetry: {e}"
        logger.error(error_msg)
        raise RuntimeError(error_msg) from e


def shutdown_telemetry() -> None:
    """Flush and shutdown telemetry providers."""
    global _telemetry_initialized

    if not _telemetry_initialized:
        return

    try:
        provider = trace.get_tracer_provider()
        if isinstance(provider, TracerProvider):
            provider.force_flush(timeout_millis=5000)
            provider.shutdown()
        logger.info("Telemetry shutdown complete")
    except Exception as e:
        logger.warning(f"Error during telemetry shutdown: {e}")
    finally:
        _telemetry_initialized = False
```

```python
# app/main.py
from contextlib import asynccontextmanager
from fastapi import FastAPI

from app.telemetry import configure_telemetry, shutdown_telemetry


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan with telemetry initialization."""
    # Startup
    configure_telemetry(app)

    yield

    # Shutdown
    shutdown_telemetry()


app = FastAPI(lifespan=lifespan)


@app.get("/health")
async def health():
    return {"status": "healthy"}
```

## Startup Validation

For strict environments where telemetry must work:

```python
# Fail fast if telemetry misconfigured
@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        configure_telemetry(app)
    except RuntimeError as e:
        if os.environ.get("REQUIRE_TELEMETRY", "false").lower() == "true":
            # In production, fail if telemetry broken
            raise
        else:
            # In development, warn but continue
            logger.warning(f"Continuing without telemetry: {e}")

    yield

    shutdown_telemetry()
```

## Basic Setup (Simple Version)

For simpler apps without lifespan management:

```python
import os
from fastapi import FastAPI, Request
from azure.monitor.opentelemetry import configure_azure_monitor
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.asyncpg import AsyncPGInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor

# Configure Azure Monitor BEFORE creating app
configure_azure_monitor(
    connection_string=os.environ["APPLICATIONINSIGHTS_CONNECTION_STRING"],
    # Optional: enable log correlation
    logger_name="myapp",
)

app = FastAPI()

# Instrument libraries
FastAPIInstrumentor.instrument_app(
    app,
    excluded_urls="health,ready,metrics",  # Don't trace health checks
)
AsyncPGInstrumentor().instrument()
HTTPXClientInstrumentor().instrument()
```

## Custom Attributes via Request Hooks

Add application-specific context to every span:

```python
from opentelemetry.trace import Span

def server_request_hook(span: Span, scope: dict):
    """Called when request starts - add custom attributes."""
    if span and span.is_recording():
        # Extract from request state (set by auth middleware)
        if "state" in scope and hasattr(scope["state"], "user_id"):
            span.set_attribute("user.id", scope["state"].user_id)
            span.set_attribute("tenant.id", scope["state"].tenant_id)

def client_request_hook(span: Span, request):
    """Called for outgoing HTTP requests."""
    if span and span.is_recording():
        span.set_attribute("http.request.target_service", request.url.host)

def client_response_hook(span: Span, message):
    """Called when response received."""
    pass  # Add response-based attributes if needed

FastAPIInstrumentor.instrument_app(
    app,
    server_request_hook=server_request_hook,
    client_request_hook=client_request_hook,
    client_response_hook=client_response_hook,
)
```

## Exception Handling

Ensure exceptions are captured in traces:

```python
from opentelemetry import trace
from opentelemetry.trace import Status, StatusCode

tracer = trace.get_tracer(__name__)

@app.post("/api/documents")
async def upload_document(file: UploadFile):
    with tracer.start_as_current_span(
        "process_upload",
        record_exception=True,       # Auto-record exception details
        set_status_on_exception=True # Auto-set ERROR status
    ) as span:
        span.set_attribute("document.filename", file.filename)
        span.set_attribute("document.size", file.size)

        try:
            result = await process_file(file)
            span.set_attribute("document.pages", result.page_count)
            return result
        except ValidationError as e:
            # Exception is auto-recorded, but we can add context
            span.set_attribute("error.type", "validation")
            raise HTTPException(status_code=400, detail=str(e))
        # Other exceptions propagate with full stack trace in span
```

## Database Instrumentation

### asyncpg Auto-Instrumentation

Basic setup captures query timing automatically:

```python
AsyncPGInstrumentor().instrument()
```

### Enhanced Query Tracking

For better query analysis, wrap database calls:

```python
import re
from opentelemetry import trace

tracer = trace.get_tracer(__name__)

def generate_query_summary(sql: str) -> str:
    """Extract operation and table for low-cardinality grouping."""
    sql_upper = sql.strip().upper()
    operation = sql_upper.split()[0] if sql_upper else "QUERY"

    # Extract table names
    tables = []
    for pattern in [r'\bFROM\s+(\w+)', r'\bINTO\s+(\w+)', r'^UPDATE\s+(\w+)']:
        match = re.search(pattern, sql_upper)
        if match:
            tables.append(match.group(1).lower())

    return f"{operation} {' '.join(tables)}" if tables else operation

def sanitize_query(sql: str) -> str:
    """Replace literals with placeholders."""
    sql = re.sub(r"'[^']*'", "?", sql)
    sql = re.sub(r'\b\d+\b', "?", sql)
    return sql

class TracedConnection:
    def __init__(self, conn):
        self._conn = conn

    async def fetch(self, query: str, *args):
        summary = generate_query_summary(query)
        with tracer.start_as_current_span(summary) as span:
            span.set_attribute("db.system.name", "postgresql")
            span.set_attribute("db.query.summary", summary)
            span.set_attribute("db.query.text", sanitize_query(query))

            result = await self._conn.fetch(query, *args)
            span.set_attribute("db.response.rows", len(result))
            return result
```

## Structured Logging with Trace Correlation

```python
import logging
import json
from opentelemetry import trace

class TraceIdFilter(logging.Filter):
    def filter(self, record):
        span = trace.get_current_span()
        if span.is_recording():
            ctx = span.get_span_context()
            record.trace_id = format(ctx.trace_id, '032x')
            record.span_id = format(ctx.span_id, '016x')
        else:
            record.trace_id = "0" * 32
            record.span_id = "0" * 16
        return True

# Configure logger
logger = logging.getLogger("myapp")
logger.addFilter(TraceIdFilter())

# Log format includes trace context
formatter = logging.Formatter(
    '{"time":"%(asctime)s","level":"%(levelname)s",'
    '"trace_id":"%(trace_id)s","span_id":"%(span_id)s",'
    '"message":"%(message)s"}'
)
```

## CORS Configuration for Trace Propagation

Backend must accept trace headers from frontend and expose response headers for correlation.

**Critical:** If these headers are blocked by CORS, distributed tracing breaks silently.

```python
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://app.example.com"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=[
        # Standard headers
        "Content-Type",
        "Authorization",
        # W3C Trace Context (required for distributed tracing)
        "traceparent",
        "tracestate",
        # OpenTelemetry baggage
        "baggage",
        # Application Insights specific (for legacy correlation)
        "Request-Id",
        "Request-Context",
        "correlation-context",
    ],
    # Expose headers so browser SDK can read correlation response
    expose_headers=[
        "Request-Context",  # Required for App Insights correlation
    ],
)
```

### Troubleshooting Correlation Issues

If you see "Failed to get Request-Context correlation header" in browser console:

1. **Check CORS allow_headers** - Must include `Request-Context`, `traceparent`
2. **Check CORS expose_headers** - Must expose `Request-Context`
3. **Check frontend config** - Ensure `enableCorsCorrelation: true` and domain is in `correlationHeaderDomains`
4. **Check browser DevTools** - Network tab should show `traceparent` header on requests

## Middleware for Request Context

```python
from starlette.middleware.base import BaseHTTPMiddleware
from opentelemetry import trace

class RequestContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        span = trace.get_current_span()

        # Add request context to span
        if span.is_recording():
            span.set_attribute("http.client_ip", request.client.host)
            if auth := request.headers.get("authorization"):
                # Don't log the actual token
                span.set_attribute("auth.present", True)

        response = await call_next(request)

        # Add response context
        if span.is_recording():
            span.set_attribute("http.response.size",
                              response.headers.get("content-length", 0))

        return response

app.add_middleware(RequestContextMiddleware)
```

## Outgoing Request Instrumentation

For calls to other services:

```python
import httpx
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor

# Auto-instrument all httpx clients
HTTPXClientInstrumentor().instrument()

# Context is automatically propagated
async with httpx.AsyncClient() as client:
    # traceparent header automatically added
    response = await client.post(
        "http://agent-service/run",
        json={"prompt": prompt}
    )
```

## Health Check Exclusion

Don't pollute traces with health checks:

```python
FastAPIInstrumentor.instrument_app(
    app,
    excluded_urls="health,ready,metrics,favicon.ico",
)

# Or use regex patterns
FastAPIInstrumentor.instrument_app(
    app,
    excluded_urls=r"health.*|metrics|\.ico$",
)
```
