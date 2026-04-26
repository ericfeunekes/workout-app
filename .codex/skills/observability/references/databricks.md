# Databricks Pipeline Instrumentation

Observability patterns for Spark, Delta Live Tables (DLT), and streaming pipelines on Databricks.

## Architecture Options

| Approach | Captures | Setup Complexity | Best For |
|----------|----------|------------------|----------|
| JVM Java Agent | Spark metrics, storage traces, logs | High | Production clusters |
| StreamingQueryListener | Per-batch spans | Medium | Structured Streaming |
| DLT Event Log | Pipeline events, lineage | None (built-in) | DLT pipelines |
| Custom PySpark spans | ETL stage timing | Low | Batch jobs |

## Recommended: Hybrid Approach

Combine multiple approaches for comprehensive observability.

## 1. JVM Agent for Automatic Instrumentation

Deploy Azure Monitor Java agent to Databricks cluster.

### Cluster Init Script

```bash
#!/bin/bash
# init_script.sh - Save to DBFS

# Download Azure Monitor Java agent
wget -O /tmp/applicationinsights-agent.jar \
  https://github.com/microsoft/ApplicationInsights-Java/releases/download/3.4.13/applicationinsights-agent-3.4.13.jar

# Create config
cat > /tmp/applicationinsights.json << 'EOF'
{
  "connectionString": "${APPLICATIONINSIGHTS_CONNECTION_STRING}",
  "role": {
    "name": "databricks-cluster"
  },
  "instrumentation": {
    "logging": {
      "level": "INFO"
    }
  },
  "jmxMetrics": [
    {
      "name": "spark.executor.threadpool.activeTasks",
      "objectName": "metrics:name=spark.*.executor.threadpool.activeTasks,type=gauges",
      "attribute": "Value"
    },
    {
      "name": "spark.executor.memory.used",
      "objectName": "metrics:name=spark.*.executor.memory.used,type=gauges",
      "attribute": "Value"
    }
  ]
}
EOF

# Copy to driver/executor paths
cp /tmp/applicationinsights-agent.jar /databricks/jars/
cp /tmp/applicationinsights.json /databricks/jars/
```

### Cluster Spark Config

```
spark.driver.extraJavaOptions -javaagent:/databricks/jars/applicationinsights-agent.jar
spark.executor.extraJavaOptions -javaagent:/databricks/jars/applicationinsights-agent.jar
```

### What's Captured

- Spark JMX metrics (tasks, memory, shuffle)
- Storage traces (ADLS, SQL Server)
- Java/Scala logs
- Automatic dependency tracking

## 2. Python/PySpark Custom Spans

For notebook and job instrumentation:

```python
# Cell 1: Setup OpenTelemetry
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from azure.monitor.opentelemetry.exporter import AzureMonitorTraceExporter
import os

# Initialize tracer
trace.set_tracer_provider(TracerProvider())
tracer = trace.get_tracer(__name__)

# Export to Azure Monitor
exporter = AzureMonitorTraceExporter(
    connection_string=dbutils.secrets.get("observability", "appinsights-connection-string")
)
trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(exporter)
)
```

```python
# Cell 2: Instrumented ETL Pipeline
with tracer.start_as_current_span("etl_pipeline") as pipeline:
    pipeline.set_attribute("pipeline.name", "customer_data_sync")
    pipeline.set_attribute("pipeline.run_id", dbutils.notebook.entry_point.getDbutils()
                          .notebook().getContext().currentRunId().get())

    # Extract
    with tracer.start_as_current_span("extract") as extract:
        df = spark.read.format("delta").load("/data/bronze/customers")
        row_count = df.count()
        extract.set_attribute("extract.rows", row_count)
        extract.set_attribute("extract.source", "/data/bronze/customers")

    # Transform
    with tracer.start_as_current_span("transform") as transform:
        df_clean = (df
            .filter(df.email.isNotNull())
            .dropDuplicates(["customer_id"])
        )
        transform.set_attribute("transform.input_rows", row_count)
        transform.set_attribute("transform.output_rows", df_clean.count())

    # Load
    with tracer.start_as_current_span("load") as load:
        df_clean.write.format("delta").mode("overwrite").save("/data/silver/customers")
        load.set_attribute("load.destination", "/data/silver/customers")
```

## 3. StreamingQueryListener for Structured Streaming

Track micro-batch performance:

```python
from pyspark.sql.streaming import StreamingQueryListener
from opentelemetry import trace
from datetime import datetime

class OpenTelemetryStreamingListener(StreamingQueryListener):
    def __init__(self):
        self.tracer = trace.get_tracer(__name__)

    def onQueryStarted(self, event):
        """Called when streaming query starts."""
        with self.tracer.start_as_current_span("streaming_query_started") as span:
            span.set_attribute("spark.streaming.query_id", str(event.id))
            span.set_attribute("spark.streaming.query_name", event.name or "unnamed")
            span.set_attribute("spark.streaming.run_id", str(event.runId))

    def onQueryProgress(self, event):
        """Called on each micro-batch completion."""
        progress = event.progress
        start_time_ns = int(
            datetime.fromisoformat(progress.timestamp.replace('Z', '+00:00'))
            .timestamp() * 1_000_000_000
        )

        with self.tracer.start_span(
            name=f"streaming_batch:{progress.name or 'unnamed'}",
            start_time=start_time_ns,
            kind=trace.SpanKind.SERVER,
        ) as span:
            # Core metrics
            span.set_attribute("spark.streaming.query_name", progress.name or "unnamed")
            span.set_attribute("spark.streaming.batch_id", progress.batchId)
            span.set_attribute("spark.streaming.num_input_rows", progress.numInputRows)
            span.set_attribute("spark.streaming.input_rows_per_second", progress.inputRowsPerSecond)
            span.set_attribute("spark.streaming.processed_rows_per_second", progress.processedRowsPerSecond)

            # Duration metrics
            if progress.durationMs:
                span.set_attribute("spark.streaming.trigger_execution_ms",
                                 progress.durationMs.get("triggerExecution", 0))
                span.set_attribute("spark.streaming.get_batch_ms",
                                 progress.durationMs.get("getBatch", 0))

            # Source metrics (e.g., Kafka offsets)
            if progress.sources:
                for i, source in enumerate(progress.sources):
                    span.set_attribute(f"spark.streaming.source.{i}.description",
                                     source.get("description", ""))
                    span.set_attribute(f"spark.streaming.source.{i}.num_input_rows",
                                     source.get("numInputRows", 0))

            # Calculate end time
            batch_duration_ms = progress.batchDuration if progress.batchDuration else 0
            end_time_ns = start_time_ns + (batch_duration_ms * 1_000_000)
            span.end(end_time=end_time_ns)

    def onQueryTerminated(self, event):
        """Called when streaming query stops."""
        with self.tracer.start_as_current_span("streaming_query_terminated") as span:
            span.set_attribute("spark.streaming.query_id", str(event.id))
            span.set_attribute("spark.streaming.run_id", str(event.runId))

            if event.exception:
                span.set_attribute("error", True)
                span.set_attribute("error.message", str(event.exception))
                span.record_exception(Exception(event.exception))
            else:
                span.set_attribute("error", False)

    def onQueryIdle(self, event):
        """Called when query has no data to process."""
        pass  # Optionally track idle time

# Register listener
listener = OpenTelemetryStreamingListener()
spark.streams.addListener(listener)
```

## 4. DLT Built-in Observability

Delta Live Tables maintains an event log automatically.

### Accessing Event Log

```python
# Event log is stored in pipeline storage location
event_log_path = f"/pipelines/{pipeline_id}/system/events"

events_df = spark.read.format("delta").load(event_log_path)

# Query update events
updates = events_df.filter("event_type = 'update_progress'")

# Query flow events
flows = events_df.filter("event_type = 'flow_progress'")
```

### Key Event Types

| Event Type | Contains |
|------------|----------|
| `update_progress` | Pipeline update status, duration |
| `flow_progress` | Row counts, data quality metrics |
| `dataset_definition` | Schema, expectations |
| `planning_information` | Execution plan |

### Streaming Metrics in DLT UI

DLT provides built-in streaming observability (Public Preview):

- Backlog seconds/bytes/records
- Processing rates
- Source-specific metrics (Kafka, Auto Loader)

Access: Pipeline UI → Select streaming flow → View metrics panel

## 5. Observable Metrics in Streaming

Define custom metrics that can be observed:

```python
from pyspark.sql.functions import count, avg, max, min

# Define stream with observable metrics
query = (
    spark.readStream
    .format("kafka")
    .option("kafka.bootstrap.servers", "...")
    .option("subscribe", "events")
    .load()
    .observe(
        "batch_metrics",
        count("*").alias("row_count"),
        avg("value_size").alias("avg_size"),
        max("timestamp").alias("max_ts")
    )
    .writeStream
    .format("delta")
    .start("/data/events")
)

# Access metrics via listener
class MetricsListener(StreamingQueryListener):
    def onQueryProgress(self, event):
        if event.progress.observedMetrics:
            metrics = event.progress.observedMetrics.get("batch_metrics", {})
            print(f"Rows: {metrics.get('row_count')}, Avg size: {metrics.get('avg_size')}")
```

## Python-Java Trace Correlation

**Limitation:** Python OTEL spans and Java telemetry (from JVM agent) don't automatically share trace context.

### Workaround: MDC Correlation

```python
from opentelemetry import trace
import logging

# Get current trace context
span = trace.get_current_span()
trace_id = format(span.get_span_context().trace_id, '032x')

# Set in Spark MDC for Java log correlation
spark.sparkContext.setLocalProperty("mdc.pyspark_trace_id", trace_id)
```

Then query in Azure Monitor:

```kusto
// Correlate Python spans with Java logs
let python_trace_id = dependencies
| where name == "etl_pipeline"
| project operation_Id
| limit 1;

traces
| where (operation_Id in (python_trace_id))
   or (customDimensions["mdc.pyspark_trace_id"] in (python_trace_id))
```

## Best Practices

### 1. Use Pipeline Run IDs

Always include run context:

```python
run_id = dbutils.notebook.entry_point.getDbutils().notebook().getContext().currentRunId().get()
span.set_attribute("databricks.run_id", run_id)
```

### 2. Track Data Quality

```python
with tracer.start_as_current_span("data_quality_check") as span:
    null_count = df.filter(df.email.isNull()).count()
    duplicate_count = df.count() - df.dropDuplicates(["id"]).count()

    span.set_attribute("dq.null_emails", null_count)
    span.set_attribute("dq.duplicates", duplicate_count)

    if null_count > threshold:
        span.set_attribute("dq.passed", False)
        raise ValueError(f"Too many null emails: {null_count}")

    span.set_attribute("dq.passed", True)
```

### 3. Flush Before Notebook Ends

```python
# Last cell of notebook
from opentelemetry.sdk.trace import TracerProvider

# Force flush to ensure all spans are exported
provider = trace.get_tracer_provider()
if isinstance(provider, TracerProvider):
    provider.force_flush()
```

## Reference Implementation

See [Azure-Samples/databricks-observability](https://github.com/Azure-Samples/databricks-observability) for complete Terraform-deployed solution with:
- Cluster init scripts
- Sample notebooks
- KQL queries
- Application Map visualization
