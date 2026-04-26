## LLM & Agent Trust Boundaries (Generalizable Patterns)

### Model Outputs Are Untrusted

- Treat all model output as untrusted input when it is:
  - Rendered (HTML/Markdown),
  - Executed (tool calls, code execution),
  - Stored (logs, databases), or
  - Used to make authorization decisions.

### The High-Risk Combination (Prompt Injection “Trifecta”)

Risk spikes when all are true:

- Untrusted content is ingested (RAG, web pages, user uploads, tool outputs).
- Sensitive data is accessible to the agent (PII, internal docs, tokens/secrets).
- The agent can take actions (write, send, delete, execute, call privileged APIs).

### Control Patterns That Generalize

- Separate roles:
  - Retrieval returns **data**, never **instructions**.
  - The system prompt defines rules; retrieved text is treated as content to analyze.
- Constrain actions:
  - Minimize tool surface area and default-deny dangerous operations.
  - Require explicit, user-visible confirmation for irreversible or high-impact actions.
  - Bind tool permissions to the authenticated user and the current task context.
- Validate tool inputs:
  - Use structured schemas; reject unexpected fields and suspicious values.
  - Apply allowlists (domains, file paths, resources) before executing side effects.
- Reduce data exposure:
  - Retrieve the minimum necessary context.
  - Redact secrets before they reach the model where feasible.
  - Keep tokens out of prompts and out of model-visible tool outputs.

### Output Rendering Safety (UI/Docs)

- Do not render raw HTML from model output unless strictly required and aggressively sanitized.
- Prefer safe markdown rendering modes that do not allow HTML passthrough.
- Treat links as potentially malicious:
  - Display the destination clearly,
  - Consider allowlisting domains,
  - Use safe link attributes (`noopener`, `noreferrer`) where applicable.

### Verification Questions (Audit Checklist)

- What untrusted inputs can reach the model (and via which paths)?
- What sensitive data can reach the model (and why)?
- What actions can the agent take (and what authorization gates exist)?
- Where is model output rendered/executed, and what sanitization/allowlists exist?
