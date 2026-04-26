# Sampling Strategies

When and how to sample traces to balance observability with cost and performance.

## When to Sample

| Daily Trace Volume | Recommended Strategy |
|--------------------|----------------------|
| < 100K | No sampling (100%) |
| 100K - 1M | Head-based 50% |
| 1M - 10M | Head-based 10-20% |
| > 10M | Tail-based with Collector |

## Head-Based Sampling

Decision made at trace start. Simple but can't consider trace outcome.

### Azure Monitor

```python
from azure.monitor.opentelemetry import configure_azure_monitor

configure_azure_monitor(
    connection_string="...",
    sampling_ratio=0.1,  # 10% of traces
)
```

### Pure OpenTelemetry

```python
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.sampling import TraceIdRatioBased

provider = TracerProvider(
    sampler=TraceIdRatioBased(0.1)  # 10% sampling
)
```

### Parent-Based Sampling

Respect sampling decisions from upstream services:

```python
from opentelemetry.sdk.trace.sampling import ParentBasedTraceIdRatio

# Sample 10% of new traces, but always follow parent decision
sampler = ParentBasedTraceIdRatio(0.1)
```

This ensures all spans in a distributed trace are either all sampled or all dropped.

## Tail-Based Sampling

Decision made after trace completes. Can sample based on outcome (errors, latency).

**Requires:** OpenTelemetry Collector

### Collector Configuration

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  tail_sampling:
    decision_wait: 10s      # Wait for spans to arrive
    num_traces: 50000       # Buffer size
    expected_new_traces_per_sec: 1000
    policies:
      # Always keep errors
      - name: errors-policy
        type: status_code
        status_code:
          status_codes: [ERROR]

      # Always keep slow traces (> 2 seconds)
      - name: latency-policy
        type: latency
        latency:
          threshold_ms: 2000

      # Always keep traces with specific attributes
      - name: important-users
        type: string_attribute
        string_attribute:
          key: user.tier
          values: [enterprise, premium]

      # Sample 10% of remaining traces
      - name: probabilistic-policy
        type: probabilistic
        probabilistic:
          sampling_percentage: 10

  batch:
    timeout: 5s
    send_batch_size: 1000

exporters:
  azuremonitor:
    connection_string: ${APPLICATIONINSIGHTS_CONNECTION_STRING}

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [tail_sampling, batch]
      exporters: [azuremonitor]
```

### Tail Sampling Policies

| Policy Type | Use Case |
|-------------|----------|
| `status_code` | Keep all errors |
| `latency` | Keep slow traces |
| `probabilistic` | Random sampling |
| `string_attribute` | Keep traces with specific attributes |
| `numeric_attribute` | Keep traces with values above/below threshold |
| `rate_limiting` | Keep N traces per second |
| `composite` | Combine multiple policies |

### Composite Policy Example

```yaml
policies:
  - name: composite-policy
    type: composite
    composite:
      max_total_spans_per_second: 1000
      policy_order: [errors, slow, random]
      rate_allocation:
        - policy: errors
          percent: 50
        - policy: slow
          percent: 30
        - policy: random
          percent: 20
      composite_sub_policy:
        - name: errors
          type: status_code
          status_code:
            status_codes: [ERROR]
        - name: slow
          type: latency
          latency:
            threshold_ms: 1000
        - name: random
          type: probabilistic
          probabilistic:
            sampling_percentage: 100
```

## Application Configuration for Tail Sampling

Configure app to send all traces to Collector (Collector does sampling):

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.sampling import ALWAYS_ON
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace.export import BatchSpanProcessor

# Always sample locally (Collector decides)
provider = TracerProvider(sampler=ALWAYS_ON)
trace.set_tracer_provider(provider)

# Send to Collector
exporter = OTLPSpanExporter(endpoint="http://otel-collector:4317")
provider.add_span_processor(BatchSpanProcessor(exporter))
```

## Caveats

### Head-Based Limitations

- Can't know if trace will error or be slow
- Errors might be dropped
- Statistically representative but not complete

### Tail-Based Limitations

- **Decision wait time:** If spans arrive after `decision_wait`, trace may be partially sampled
- **Memory usage:** Collector buffers traces in memory
- **Complexity:** Requires running and managing Collector

### Span Arrival Timing

Long-running operations can cause issues:

```
Request starts → ... 15 seconds pass ... → Slow span completes
                     │
                     └─ decision_wait (10s) expires
                        Trace marked as "not interesting"
                        Slow span arrives too late!
```

**Mitigation:** Set `decision_wait` higher than your slowest expected operations, but this increases memory usage.

## Cost Considerations

| Approach | Traces Stored | Error Coverage | Latency Coverage |
|----------|---------------|----------------|------------------|
| 100% sampling | All | 100% | 100% |
| 10% head-based | 10% | ~10% | ~10% |
| Tail-based | Variable | 100% | 100% |

### Estimating Costs

Azure Monitor pricing (approximate):
- Ingestion: ~$2.30 per GB
- Retention: Included for 90 days

Estimate span size: ~1-2 KB per span

| Traces/Day | Avg Spans/Trace | Daily GB | Monthly Cost |
|------------|-----------------|----------|--------------|
| 100K | 5 | 0.5 GB | ~$35 |
| 1M | 5 | 5 GB | ~$350 |
| 10M | 5 | 50 GB | ~$3,500 |

## Recommendations

### Starting Fresh

Start with 100% sampling. Add sampling when:
- Costs become significant
- Performance is impacted
- You have baseline metrics to validate sampling doesn't hide issues

### Production at Scale

1. **Use tail-based sampling** if you need guaranteed error capture
2. **Set sampling ratio based on budget** rather than arbitrary percentage
3. **Monitor sampling effectiveness:** Compare error rates between sampled and actual

### Hybrid Approach

For high-volume, low-value traces:

```python
from opentelemetry.sdk.trace.sampling import Sampler, Decision, SamplingResult

class CustomSampler(Sampler):
    def should_sample(self, parent_context, trace_id, name, kind, attributes, links):
        # Always sample certain operations
        if name.startswith("critical."):
            return SamplingResult(Decision.RECORD_AND_SAMPLE)

        # Never sample health checks
        if name in ("health_check", "readiness_check"):
            return SamplingResult(Decision.DROP)

        # Sample others at 10%
        if trace_id % 10 == 0:
            return SamplingResult(Decision.RECORD_AND_SAMPLE)

        return SamplingResult(Decision.DROP)

    def get_description(self):
        return "CustomSampler"
```
