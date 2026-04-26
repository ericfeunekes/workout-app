# MLflow Agent Tracing

Configure MLflow tracing for LLM agents alongside Azure Monitor for operational observability.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Agent Service (FastAPI)                                     │
│                                                              │
│  ┌─────────────────┐    ┌─────────────────┐                │
│  │ OTEL/Azure      │    │ MLflow          │                │
│  │ Instrumentation │    │ Autolog         │                │
│  └────────┬────────┘    └────────┬────────┘                │
│           │                      │                          │
│           │ HTTP, DB spans       │ LLM spans                │
│           ▼                      ▼                          │
│  ┌─────────────────┐    ┌─────────────────┐                │
│  │ Azure Monitor   │    │ MLflow Server   │                │
│  │ (ops)           │    │ (GenAI)         │                │
│  └─────────────────┘    └─────────────────┘                │
└─────────────────────────────────────────────────────────────┘
```

**Key principle:** Azure Monitor is source of truth for operational observability. MLflow is source of truth for agent runs (token usage, model parameters, evaluation).

## Basic Setup

```python
import os
import mlflow
from azure.monitor.opentelemetry import configure_azure_monitor
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

# 1. Configure Azure Monitor for HTTP/DB spans
configure_azure_monitor(
    connection_string=os.environ["APPLICATIONINSIGHTS_CONNECTION_STRING"],
)

# 2. Configure MLflow for LLM traces
mlflow.set_tracking_uri(os.environ["MLFLOW_TRACKING_URI"])
mlflow.set_experiment("agent-traces")

# 3. Enable autologging for your LLM provider
mlflow.openai.autolog()      # For OpenAI
# mlflow.anthropic.autolog()  # For Anthropic
# mlflow.langchain.autolog()  # For LangChain

# 4. Instrument FastAPI
app = FastAPI()
FastAPIInstrumentor.instrument_app(app)
```

## Supported Autolog Providers

| Provider | Autolog Function | What's Captured |
|----------|------------------|-----------------|
| OpenAI | `mlflow.openai.autolog()` | Prompts, completions, tokens, latency |
| Anthropic | `mlflow.anthropic.autolog()` | Messages, tokens, model info |
| LangChain | `mlflow.langchain.autolog()` | Chain execution, tool calls |
| LlamaIndex | `mlflow.llama_index.autolog()` | Index operations, queries |
| AutoGen | `mlflow.autogen.autolog()` | Agent interactions |

## Manual Tracing

For custom agent logic:

```python
from mlflow import trace

@trace
def run_agent(prompt: str, context: dict) -> str:
    """Function is automatically traced."""
    # Prepare context
    messages = build_messages(prompt, context)

    # Call LLM (autologged separately)
    response = client.chat.completions.create(
        model="gpt-4",
        messages=messages
    )

    # Post-process
    return parse_response(response)

# Or with decorator options
@trace(name="custom_agent", attributes={"agent.type": "qa"})
def qa_agent(question: str) -> str:
    ...
```

Using context manager:

```python
import mlflow

with mlflow.start_span(name="document_processing") as span:
    span.set_attribute("document.id", doc_id)

    # Nested spans
    with mlflow.start_span(name="extract_text") as child:
        text = extract_text(document)
        child.set_attribute("text.length", len(text))

    with mlflow.start_span(name="generate_summary") as child:
        summary = generate_summary(text)
        child.set_attribute("summary.length", len(summary))
```

## Logging Inputs and Outputs

```python
import mlflow

@mlflow.trace
def process_query(query: str, documents: list[str]) -> dict:
    # Log inputs (visible in MLflow UI)
    mlflow.log_input(
        mlflow.data.from_dict({"query": query, "doc_count": len(documents)})
    )

    result = run_rag_pipeline(query, documents)

    # Log outputs
    mlflow.log_output(result)

    return result
```

## Token Usage and Cost Tracking

MLflow autolog captures tokens automatically. Access them:

```python
# After a traced run
run = mlflow.active_run()
metrics = mlflow.get_run(run.info.run_id).data.metrics

# Available metrics (when using autolog):
# - prompt_tokens
# - completion_tokens
# - total_tokens
```

For cost calculation:

```python
COST_PER_1K = {
    "gpt-4": {"input": 0.03, "output": 0.06},
    "gpt-3.5-turbo": {"input": 0.0005, "output": 0.0015},
}

def calculate_cost(model: str, input_tokens: int, output_tokens: int) -> float:
    rates = COST_PER_1K.get(model, {"input": 0, "output": 0})
    return (input_tokens / 1000 * rates["input"] +
            output_tokens / 1000 * rates["output"])

# Log as custom metric
with mlflow.start_span(name="llm_call") as span:
    response = client.chat.completions.create(...)
    cost = calculate_cost(
        model="gpt-4",
        input_tokens=response.usage.prompt_tokens,
        output_tokens=response.usage.completion_tokens
    )
    span.set_attribute("llm.cost_usd", cost)
```

## Dual Export (MLflow + Azure Monitor)

If you need LLM traces in both places:

```python
import os

# Enable OTLP export from MLflow
os.environ["MLFLOW_TRACE_ENABLE_OTLP_DUAL_EXPORT"] = "true"
os.environ["OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"] = (
    "https://<region>.in.applicationinsights.azure.com/v1/traces"
)

# MLflow sends traces to both MLflow server AND Azure Monitor
```

**Note:** This can be noisy. Usually better to keep MLflow traces separate for GenAI debugging and use Azure Monitor for operational traces.

## Combining with Azure Monitor Traces

When an HTTP request triggers an agent run:

```python
from opentelemetry import trace as otel_trace
import mlflow

tracer = otel_trace.get_tracer(__name__)

@app.post("/api/chat")
async def chat(request: ChatRequest):
    # OTEL span for HTTP handling (goes to Azure Monitor)
    with tracer.start_as_current_span("handle_chat_request") as span:
        span.set_attribute("user.id", request.user_id)

        # MLflow trace for agent execution (goes to MLflow)
        with mlflow.start_span(name="agent_run") as mlflow_span:
            mlflow_span.set_attribute("request.message_count", len(request.messages))

            response = await run_agent(request.messages)

            mlflow_span.set_attribute("response.token_count", response.usage.total_tokens)

        return {"response": response.content}
```

## Experiment Organization

```python
# Organize by use case
mlflow.set_experiment("chat-agent")      # Chat functionality
mlflow.set_experiment("doc-processor")   # Document processing
mlflow.set_experiment("eval-runs")       # Evaluation experiments

# Tag runs for filtering
with mlflow.start_run(tags={"environment": "production", "version": "1.2.0"}):
    ...
```

## Evaluation and Judges

MLflow supports LLM-as-judge evaluation:

```python
import mlflow
from mlflow.metrics import genai

# Define evaluation metrics
relevance = genai.relevance(model="openai:/gpt-4")
faithfulness = genai.faithfulness(model="openai:/gpt-4")

# Evaluate
results = mlflow.evaluate(
    model=my_agent,
    data=eval_dataset,
    model_type="text",
    evaluators="default",
    extra_metrics=[relevance, faithfulness],
)
```

## Retrieving Traces

```python
# Get traces for analysis
from mlflow import MlflowClient

client = MlflowClient()

# Search for traces
traces = client.search_traces(
    experiment_ids=["1"],
    filter_string="attributes.`llm.model` = 'gpt-4'",
    max_results=100,
)

# Analyze token usage
total_tokens = sum(
    t.info.execution_time_ms for t in traces
)
```

## Databricks Experiment Export

Export traces to Databricks MLflow experiments for team collaboration and production monitoring.

### Environment Configuration

```bash
# Required for Databricks export
DATABRICKS_HOST=https://your-workspace.cloud.databricks.com
DATABRICKS_TOKEN=your-personal-access-token
MLFLOW_EXPERIMENT_NAME=/Users/your.email@company.com/agent-traces
```

### Python Configuration

```python
import os
import mlflow

# Set tracking URI to Databricks
mlflow.set_tracking_uri("databricks")

# Set experiment (must be accessible in workspace)
experiment_name = os.environ.get(
    "MLFLOW_EXPERIMENT_NAME",
    "/Users/your.email@company.com/agent-traces"
)
mlflow.set_experiment(experiment_name)

# Enable autologging
mlflow.openai.autolog()

# All traces now export to Databricks
with mlflow.start_span(name="agent_run") as span:
    span.set_attribute("user.id", user_id)
    response = run_agent(prompt)
```

### Workspace vs Personal Experiments

```python
# Personal experiment (under your user folder)
mlflow.set_experiment("/Users/alice@example.com/my-experiment")

# Shared workspace experiment (team-accessible)
mlflow.set_experiment("/Shared/team-agents/production-traces")

# Repo-linked experiment
mlflow.set_experiment("/Repos/alice@example.com/agent-service/experiments/dev")
```

### Token Authentication Options

```python
# Option 1: Environment variables (recommended)
# DATABRICKS_HOST and DATABRICKS_TOKEN set in environment

# Option 2: Databricks CLI profile
mlflow.set_tracking_uri("databricks://my-profile")

# Option 3: Azure service principal (for production)
# Uses AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET
mlflow.set_tracking_uri("databricks")
```

### Logging Artifacts

When exporting to Databricks, you can also log artifacts:

```python
with mlflow.start_run():
    # Log model artifacts
    mlflow.log_artifact("model_config.json")

    # Log evaluation results
    mlflow.log_dict(evaluation_results, "eval/results.json")

    # Log visualizations
    mlflow.log_figure(fig, "charts/token_usage.png")

    # Trace is automatically associated with run
    with mlflow.start_span(name="evaluation") as span:
        results = evaluate_model(model, test_data)
        span.set_attribute("eval.accuracy", results["accuracy"])
```

### Querying Traces in Databricks

```python
from mlflow import MlflowClient

client = MlflowClient()

# Get experiment ID
experiment = client.get_experiment_by_name(
    "/Shared/team-agents/production-traces"
)

# Search traces by attribute
traces = client.search_traces(
    experiment_ids=[experiment.experiment_id],
    filter_string="attributes.`user.id` = 'user-123'",
    max_results=100,
)

# Analyze in Spark
traces_df = spark.read.format("mlflow-experiment").load(
    experiment.experiment_id
)
traces_df.display()
```

### Production Configuration

For production deployments, use service principals:

```python
# pyproject.toml or requirements.txt
# azure-identity>=1.15.0

import os
from azure.identity import DefaultAzureCredential

# The DefaultAzureCredential will use:
# 1. Environment variables (AZURE_CLIENT_ID, etc.)
# 2. Managed identity (in Azure resources)
# 3. Azure CLI login (local development)

os.environ["DATABRICKS_HOST"] = "https://your-workspace.cloud.databricks.com"

# MLflow uses DefaultAzureCredential automatically when
# DATABRICKS_TOKEN is not set and DATABRICKS_HOST is Azure Databricks
mlflow.set_tracking_uri("databricks")
```
