# Azure Monitor Configuration

Azure Application Insights setup, configuration options, usage analytics, and KQL queries.

## Python SDK Setup

```python
from azure.monitor.opentelemetry import configure_azure_monitor

configure_azure_monitor(
    connection_string=os.environ["APPLICATIONINSIGHTS_CONNECTION_STRING"],

    # Sampling (1.0 = 100%, 0.1 = 10%)
    sampling_ratio=1.0,

    # Correlate logs with traces
    logger_name="myapp",

    # Enable trace-based log sampling
    enable_live_metrics=True,
)
```

## Connection String

Format: `InstrumentationKey=xxx;IngestionEndpoint=https://region.in.applicationinsights.azure.com/`

Store in environment variable:
```bash
export APPLICATIONINSIGHTS_CONNECTION_STRING="InstrumentationKey=..."
```

## Custom Dimensions

Add application context to all telemetry:

```python
from opentelemetry import trace
from opentelemetry.sdk.resources import Resource, SERVICE_NAME, SERVICE_VERSION

# Set at provider level (applies to all spans)
resource = Resource.create({
    SERVICE_NAME: "caila-api",
    SERVICE_VERSION: "1.2.0",
    "deployment.environment": "production",
    "cloud.region": "eastus",
})

configure_azure_monitor(
    connection_string="...",
    resource=resource,
)
```

## Usage Analytics Tools

Azure Application Insights provides built-in user behavior analytics:

### Users, Sessions, Events

Access: Application Insights → Usage → Users/Sessions/Events

| Tool | Purpose | Key Metrics |
|------|---------|-------------|
| **Users** | Unique user counts | By browser, OS, location, time |
| **Sessions** | Session analysis | Duration, page counts, patterns |
| **Events** | Feature usage | Custom event frequency, properties |

### Funnels

Track conversion through multi-step flows:

1. Navigate to Usage → Funnels
2. Click "Edit"
3. Define steps (max 6):
   - Step 1: `customEvents | where name == "Upload.Started"`
   - Step 2: `customEvents | where name == "Upload.Processing"`
   - Step 3: `customEvents | where name == "Upload.Complete"`

### User Flows

Visualize paths users take through your app:

1. Navigate to Usage → User Flows
2. Select initial event (e.g., page view or custom event)
3. View branching paths showing where users go next

### Cohorts

Group users by behavior for comparative analysis:

```kusto
// Define a cohort: users who uploaded documents in last 7 days
customEvents
| where timestamp > ago(7d)
| where name == "DocumentUpload"
| summarize by user_Id
```

### Retention

Track how often users return:

- Navigate to Workbooks → User Retention Analysis
- Shows cohort retention over time (Day 1, Day 7, Day 30)

### Impact

Analyze how performance affects behavior:

- Navigate to Workbooks → Impact Analysis
- Example: "How does page load time affect conversion rate?"

## KQL Query Examples

### Distributed Trace Analysis

```kusto
// Find all spans for a specific trace
union requests, dependencies, traces, exceptions
| where operation_Id == "abc123..."
| project timestamp, itemType, name, duration, success
| order by timestamp asc
```

### Error Analysis

```kusto
// Errors by endpoint in last 24 hours
requests
| where timestamp > ago(24h)
| where success == false
| summarize errorCount = count() by name, resultCode
| order by errorCount desc
```

### Performance Analysis

```kusto
// Slowest endpoints (p95)
requests
| where timestamp > ago(1h)
| summarize
    p50 = percentile(duration, 50),
    p95 = percentile(duration, 95),
    p99 = percentile(duration, 99),
    count = count()
    by name
| order by p95 desc
```

### Database Query Analysis

```kusto
// Identify caching candidates (frequent slow queries)
dependencies
| where type == "postgresql" or type == "SQL"
| extend query_summary = tostring(customDimensions["db.query.summary"])
| where query_summary startswith "SELECT"
| summarize
    count = count(),
    avg_duration = avg(duration),
    p95_duration = percentile(duration, 95)
    by query_summary
| where count > 100 and avg_duration > 50
| order by count desc
```

### User Journey Analysis

```kusto
// Track user through document upload funnel
customEvents
| where timestamp > ago(24h)
| where name startswith "Upload."
| summarize count() by name, bin(timestamp, 1h)
| render timechart
```

### Cache Hit/Miss Analysis

```kusto
// Cache performance by key prefix
dependencies
| where name == "cache.get"
| extend
    cache_hit = tobool(customDimensions["cache.hit"]),
    cache_backend = tostring(customDimensions["cache.backend"])
| summarize
    hits = countif(cache_hit == true),
    misses = countif(cache_hit == false),
    hit_rate = round(100.0 * countif(cache_hit == true) / count(), 2)
    by cache_backend
```

### LLM Token Usage (if exported to Azure Monitor)

```kusto
// Token usage by model
customMetrics
| where name == "llm.tokens"
| extend model = tostring(customDimensions["model"])
| summarize
    total_tokens = sum(value),
    avg_tokens = avg(value)
    by model, bin(timestamp, 1h)
| render timechart
```

## Alerts

### Error Rate Alert

```kusto
// Alert when error rate exceeds 5%
requests
| where timestamp > ago(5m)
| summarize
    total = count(),
    errors = countif(success == false)
| extend error_rate = 100.0 * errors / total
| where error_rate > 5
```

### Latency Alert

```kusto
// Alert when p95 latency exceeds 2 seconds
requests
| where timestamp > ago(5m)
| summarize p95 = percentile(duration, 95)
| where p95 > 2000
```

## Log Correlation

Logs can be correlated with traces:

```python
import logging
from opentelemetry import trace

logger = logging.getLogger("myapp")

# Logs automatically include trace context when using azure-monitor-opentelemetry
logger.info("Processing document", extra={
    "document_id": doc_id,
    "user_id": user_id,
})
```

Query correlated logs:

```kusto
// Find logs for a specific trace
traces
| where operation_Id == "abc123..."
| project timestamp, message, customDimensions
| order by timestamp asc
```

## Cost Optimization

### Sampling

```python
configure_azure_monitor(
    connection_string="...",
    sampling_ratio=0.1,  # 10% sampling
)
```

### Data Retention

Configure in Azure Portal: Application Insights → Usage and estimated costs → Data retention

| Retention | Relative Cost |
|-----------|---------------|
| 30 days | Base |
| 60 days | ~1.5x |
| 90 days | ~2x |
| 365 days | ~4x |

### Ingestion Limits

Set daily cap: Application Insights → Usage and estimated costs → Daily cap

## Live Metrics

Real-time view of application performance:

```python
configure_azure_monitor(
    connection_string="...",
    enable_live_metrics=True,
)
```

Access: Application Insights → Live Metrics

Shows:
- Incoming requests/sec
- Request duration
- Dependency calls
- Exceptions
- CPU/Memory usage
