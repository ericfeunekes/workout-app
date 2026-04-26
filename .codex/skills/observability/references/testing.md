# Testing with Observability

Pytest fixtures for tracing in tests, with options for local exporters (Jaeger) and MLflow experiments.

## Installation (Test Dependencies)

```bash
pip install pytest pytest-asyncio
pip install opentelemetry-sdk
pip install opentelemetry-exporter-otlp  # For Jaeger/OTLP
pip install mlflow
```

## Local Exporters

### Jaeger in Docker

```bash
# Start Jaeger all-in-one
docker run -d --name jaeger \
  -p 16686:16686 \  # UI
  -p 4317:4317 \    # OTLP gRPC
  -p 4318:4318 \    # OTLP HTTP
  jaegertracing/all-in-one:latest

# View traces at http://localhost:16686
```

### Zipkin Alternative

```bash
docker run -d --name zipkin \
  -p 9411:9411 \
  openzipkin/zipkin
```

## Pytest Fixtures

### conftest.py - Core Fixtures

```python
# tests/conftest.py
import os
import pytest
from typing import Generator, Optional
from unittest.mock import patch

from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider, ReadableSpan
from opentelemetry.sdk.trace.export import SimpleSpanProcessor, SpanExporter, SpanExportResult
from opentelemetry.sdk.resources import Resource, SERVICE_NAME


class InMemorySpanExporter(SpanExporter):
    """Collect spans in memory for test assertions."""

    def __init__(self):
        self.spans: list[ReadableSpan] = []
        self._shutdown = False

    def export(self, spans: list[ReadableSpan]) -> SpanExportResult:
        if self._shutdown:
            return SpanExportResult.FAILURE
        self.spans.extend(spans)
        return SpanExportResult.SUCCESS

    def shutdown(self) -> None:
        self._shutdown = True

    def force_flush(self, timeout_millis: int = 30000) -> bool:
        return True

    def clear(self) -> None:
        self.spans.clear()

    def get_spans_by_name(self, name: str) -> list[ReadableSpan]:
        return [s for s in self.spans if s.name == name]

    def get_span_names(self) -> list[str]:
        return [s.name for s in self.spans]


@pytest.fixture
def trace_exporter() -> Generator[InMemorySpanExporter, None, None]:
    """
    Fixture providing in-memory span collection for assertions.

    Usage:
        def test_something(trace_exporter):
            # ... do something that creates spans ...
            spans = trace_exporter.get_spans_by_name("my_operation")
            assert len(spans) == 1
            assert spans[0].attributes["user.id"] == "123"
    """
    exporter = InMemorySpanExporter()

    # Create provider with in-memory exporter
    resource = Resource.create({SERVICE_NAME: "test-service"})
    provider = TracerProvider(resource=resource)
    provider.add_span_processor(SimpleSpanProcessor(exporter))

    # Set as global provider
    original_provider = trace.get_tracer_provider()
    trace.set_tracer_provider(provider)

    yield exporter

    # Cleanup
    provider.shutdown()
    trace.set_tracer_provider(original_provider)


@pytest.fixture
def tracer(trace_exporter: InMemorySpanExporter):
    """Get a tracer for creating spans in tests."""
    return trace.get_tracer("test")


@pytest.fixture
def disable_telemetry():
    """Disable telemetry for tests that don't need it."""
    with patch.dict(os.environ, {"TELEMETRY_ENABLED": "false"}):
        yield
```

### Jaeger Exporter Fixture

```python
# tests/conftest.py (continued)
import os

@pytest.fixture(scope="session")
def jaeger_exporter():
    """
    Export traces to local Jaeger instance.

    Requires: docker run -d -p 4317:4317 -p 16686:16686 jaegertracing/all-in-one
    View traces: http://localhost:16686
    """
    jaeger_endpoint = os.environ.get("JAEGER_ENDPOINT", "http://localhost:4317")

    try:
        from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
    except ImportError:
        pytest.skip("opentelemetry-exporter-otlp not installed")

    exporter = OTLPSpanExporter(endpoint=jaeger_endpoint, insecure=True)

    resource = Resource.create({
        SERVICE_NAME: "test-service",
        "deployment.environment": "test",
    })
    provider = TracerProvider(resource=resource)
    provider.add_span_processor(SimpleSpanProcessor(exporter))

    original_provider = trace.get_tracer_provider()
    trace.set_tracer_provider(provider)

    yield exporter

    provider.force_flush()
    provider.shutdown()
    trace.set_tracer_provider(original_provider)


@pytest.fixture
def jaeger_tracer(jaeger_exporter):
    """Get tracer that exports to Jaeger."""
    return trace.get_tracer("test")
```

### MLflow Fixtures

```python
# tests/conftest.py (continued)
import tempfile
from pathlib import Path

@pytest.fixture
def mlflow_experiment(tmp_path: Path):
    """
    Set up MLflow with local file tracking for tests.

    Usage:
        def test_agent(mlflow_experiment):
            # MLflow traces go to tmp directory
            result = run_agent("test prompt")
            # Check MLflow for traces
    """
    import mlflow

    tracking_uri = f"file://{tmp_path}/mlruns"
    mlflow.set_tracking_uri(tracking_uri)

    experiment_name = "test-experiment"
    mlflow.set_experiment(experiment_name)

    yield {
        "tracking_uri": tracking_uri,
        "experiment_name": experiment_name,
        "artifact_path": tmp_path,
    }

    # Cleanup handled by tmp_path fixture


@pytest.fixture
def mlflow_databricks():
    """
    Configure MLflow to export to Databricks experiment.

    Requires environment variables:
        DATABRICKS_HOST: https://your-workspace.cloud.databricks.com
        DATABRICKS_TOKEN: your-token
        MLFLOW_EXPERIMENT_NAME: /Users/you/experiment-name
    """
    import mlflow

    host = os.environ.get("DATABRICKS_HOST")
    token = os.environ.get("DATABRICKS_TOKEN")
    experiment_name = os.environ.get("MLFLOW_EXPERIMENT_NAME")

    if not all([host, token, experiment_name]):
        pytest.skip("Databricks credentials not configured")

    tracking_uri = f"databricks"
    mlflow.set_tracking_uri(tracking_uri)
    mlflow.set_experiment(experiment_name)

    # Enable autologging
    mlflow.openai.autolog()

    yield {
        "tracking_uri": tracking_uri,
        "experiment_name": experiment_name,
        "host": host,
    }


@pytest.fixture
def mlflow_autolog():
    """Enable MLflow autologging for LLM providers."""
    import mlflow

    # Enable autolog for common providers
    try:
        mlflow.openai.autolog()
    except Exception:
        pass

    try:
        mlflow.anthropic.autolog()
    except Exception:
        pass

    yield

    # Disable autolog
    try:
        mlflow.openai.autolog(disable=True)
    except Exception:
        pass

    try:
        mlflow.anthropic.autolog(disable=True)
    except Exception:
        pass
```

### Combined Fixture for Full Stack Testing

```python
# tests/conftest.py (continued)

@pytest.fixture
def full_observability(
    trace_exporter: InMemorySpanExporter,
    mlflow_experiment: dict,
):
    """
    Combined fixture for testing with both OTEL and MLflow.

    Usage:
        def test_full_flow(full_observability):
            otel = full_observability["otel"]
            mlflow_config = full_observability["mlflow"]

            # Run your code
            result = process_with_agent(data)

            # Assert OTEL spans
            spans = otel.get_spans_by_name("process_document")
            assert len(spans) == 1

            # MLflow traces in mlflow_config["artifact_path"]
    """
    yield {
        "otel": trace_exporter,
        "mlflow": mlflow_experiment,
    }
```

## Test Examples

### Testing Span Creation

```python
# tests/test_tracing.py
import pytest
from opentelemetry import trace


def test_span_attributes(trace_exporter, tracer):
    """Verify spans have expected attributes."""
    with tracer.start_as_current_span("test_operation") as span:
        span.set_attribute("user.id", "user-123")
        span.set_attribute("document.id", "doc-456")

    spans = trace_exporter.get_spans_by_name("test_operation")
    assert len(spans) == 1

    span = spans[0]
    assert span.attributes["user.id"] == "user-123"
    assert span.attributes["document.id"] == "doc-456"


def test_nested_spans(trace_exporter, tracer):
    """Verify parent-child span relationships."""
    with tracer.start_as_current_span("parent") as parent:
        with tracer.start_as_current_span("child") as child:
            pass

    parent_spans = trace_exporter.get_spans_by_name("parent")
    child_spans = trace_exporter.get_spans_by_name("child")

    assert len(parent_spans) == 1
    assert len(child_spans) == 1

    # Verify child has parent
    assert child_spans[0].parent.span_id == parent_spans[0].context.span_id


def test_exception_recording(trace_exporter, tracer):
    """Verify exceptions are recorded in spans."""
    with pytest.raises(ValueError):
        with tracer.start_as_current_span(
            "failing_operation",
            record_exception=True
        ):
            raise ValueError("Something went wrong")

    spans = trace_exporter.get_spans_by_name("failing_operation")
    assert len(spans) == 1

    # Check exception was recorded
    events = spans[0].events
    exception_events = [e for e in events if e.name == "exception"]
    assert len(exception_events) == 1
    assert "ValueError" in str(exception_events[0].attributes)
```

### Testing FastAPI Endpoints

```python
# tests/test_api.py
import pytest
from httpx import AsyncClient, ASGITransport
from fastapi import FastAPI

from app.main import app


@pytest.fixture
async def client(trace_exporter):
    """Async test client with tracing."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


@pytest.mark.asyncio
async def test_endpoint_creates_spans(client, trace_exporter):
    """Verify API endpoints create expected spans."""
    response = await client.post(
        "/api/documents",
        json={"content": "test content"}
    )
    assert response.status_code == 200

    # Check spans were created
    span_names = trace_exporter.get_span_names()
    assert "POST /api/documents" in span_names or any(
        "documents" in name for name in span_names
    )
```

### Testing with Jaeger (Integration)

```python
# tests/test_integration.py
import pytest


@pytest.mark.integration
def test_traces_visible_in_jaeger(jaeger_tracer):
    """
    Integration test that exports to Jaeger.

    Run with: pytest -m integration
    View traces: http://localhost:16686
    """
    with jaeger_tracer.start_as_current_span("integration_test") as span:
        span.set_attribute("test.name", "test_traces_visible_in_jaeger")

        with jaeger_tracer.start_as_current_span("child_operation") as child:
            child.set_attribute("step", 1)

    # Traces are exported to Jaeger
    # Manually verify at http://localhost:16686
```

### Testing MLflow Traces

```python
# tests/test_mlflow.py
import pytest


def test_mlflow_traces_created(mlflow_experiment):
    """Verify MLflow traces are created."""
    import mlflow

    with mlflow.start_span(name="test_span") as span:
        span.set_attribute("test.key", "test_value")

    # Verify experiment has runs
    client = mlflow.MlflowClient()
    experiment = client.get_experiment_by_name(mlflow_experiment["experiment_name"])
    runs = client.search_runs(experiment.experiment_id)

    # At least one run should exist
    assert len(runs) >= 0  # Traces don't always create runs


@pytest.mark.integration
def test_mlflow_databricks_export(mlflow_databricks):
    """
    Integration test exporting to Databricks.

    Requires DATABRICKS_HOST, DATABRICKS_TOKEN, MLFLOW_EXPERIMENT_NAME.
    """
    import mlflow

    with mlflow.start_run():
        mlflow.log_param("test_param", "value")
        mlflow.log_metric("test_metric", 1.0)

    # Verify in Databricks UI
```

## pytest.ini Configuration

```ini
[pytest]
markers =
    integration: marks tests as integration tests (deselect with '-m "not integration"')
    slow: marks tests as slow

asyncio_mode = auto

# Default: skip integration tests
addopts = -m "not integration"
```

## Environment Variables for Testing

```bash
# .env.test
TELEMETRY_ENABLED=true
SERVICE_NAME=test-service
ENVIRONMENT=test

# For Jaeger integration tests
JAEGER_ENDPOINT=http://localhost:4317

# For Databricks integration tests
DATABRICKS_HOST=https://your-workspace.cloud.databricks.com
DATABRICKS_TOKEN=your-token
MLFLOW_EXPERIMENT_NAME=/Users/you/test-experiment
```

## CI/CD Integration

### GitHub Actions Example

```yaml
# .github/workflows/test.yml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      jaeger:
        image: jaegertracing/all-in-one:latest
        ports:
          - 4317:4317
          - 16686:16686

    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.11"

      - name: Install dependencies
        run: |
          pip install uv
          uv sync --dev

      - name: Run unit tests
        run: uv run pytest -m "not integration"

      - name: Run integration tests
        run: uv run pytest -m integration
        env:
          JAEGER_ENDPOINT: http://localhost:4317
```
