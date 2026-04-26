# LLM Tool Safety

When LLMs can invoke tools, compromised or manipulated agents can cause real-world harm. Tool safety requires limiting capabilities, validating inputs, and controlling execution context.

## The Risk Model

Tools extend what an LLM can do:
- **Read tools**: Access databases, files, APIs, emails
- **Write tools**: Create records, send messages, modify state
- **Execute tools**: Run code, shell commands, workflows

An attacker who controls LLM behavior (via prompt injection) gains these capabilities.

## Principle: Minimal Authority

Grant only the permissions the agent actually needs:

```python
# BAD - overpowered tool
class DatabaseTool:
    def execute(self, sql: str) -> list[dict]:
        """Execute any SQL query."""
        return self.conn.execute(sql).fetchall()

# GOOD - scoped to specific operations
class UserLookupTool:
    def get_user_by_email(self, email: str) -> dict | None:
        """Look up a user by email address."""
        # Parameterized, read-only, single-table
        return self.conn.execute(
            "SELECT id, name, email FROM users WHERE email = $1",
            email
        ).fetchone()
```

## Tool Design Patterns

### Pattern 1: Typed, Validated Inputs

Use Pydantic to constrain what the LLM can pass:

```python
from pydantic import BaseModel, EmailStr, Field
from enum import Enum

class Priority(str, Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"

class CreateTicketInput(BaseModel):
    title: str = Field(max_length=200)
    description: str = Field(max_length=2000)
    priority: Priority
    assignee_email: EmailStr

def create_ticket(input: CreateTicketInput) -> dict:
    """Create a support ticket."""
    # Input is validated - can't inject arbitrary fields
    return ticket_service.create(
        title=input.title,
        description=input.description,
        priority=input.priority,
        assignee=input.assignee_email
    )
```

### Pattern 2: Allowlisted Parameters

For sensitive operations, constrain to known-good values:

```python
ALLOWED_REPORT_TYPES = {"sales", "inventory", "users"}
ALLOWED_DATE_RANGES = {"today", "week", "month", "quarter"}

class GenerateReportInput(BaseModel):
    report_type: str
    date_range: str

def generate_report(input: GenerateReportInput) -> str:
    if input.report_type not in ALLOWED_REPORT_TYPES:
        raise ValueError(f"Unknown report type: {input.report_type}")
    if input.date_range not in ALLOWED_DATE_RANGES:
        raise ValueError(f"Unknown date range: {input.date_range}")

    return report_service.generate(input.report_type, input.date_range)
```

### Pattern 3: Resource Scoping

Tools should only access resources the user owns:

```python
class FileReadTool:
    def __init__(self, user_id: str, allowed_paths: list[Path]):
        self.user_id = user_id
        self.allowed_paths = allowed_paths

    def read_file(self, path: str) -> str:
        resolved = Path(path).resolve()

        # Check path is within allowed directories
        if not any(resolved.is_relative_to(p) for p in self.allowed_paths):
            raise PermissionError(f"Access denied: {path}")

        # Check user owns the file (app-specific logic)
        if not self.file_service.user_owns(self.user_id, resolved):
            raise PermissionError(f"Not your file: {path}")

        return resolved.read_text()
```

### Pattern 4: Rate Limiting

Prevent runaway tool usage:

```python
from functools import wraps
import time

class RateLimiter:
    def __init__(self, max_calls: int, period_seconds: int):
        self.max_calls = max_calls
        self.period = period_seconds
        self.calls = []

    def check(self):
        now = time.time()
        self.calls = [t for t in self.calls if now - t < self.period]
        if len(self.calls) >= self.max_calls:
            raise RateLimitError(f"Max {self.max_calls} calls per {self.period}s")
        self.calls.append(now)

# Usage
email_limiter = RateLimiter(max_calls=5, period_seconds=60)

def send_email(to: str, subject: str, body: str):
    email_limiter.check()  # Raises if exceeded
    return email_service.send(to, subject, body)
```

### Pattern 5: Confirmation for Sensitive Actions

Require human approval for high-impact operations:

```python
from enum import Enum

class ActionRisk(str, Enum):
    LOW = "low"      # Read-only, reversible
    MEDIUM = "medium"  # Write, but reversible
    HIGH = "high"    # Irreversible or external

TOOL_RISK_LEVELS = {
    "read_file": ActionRisk.LOW,
    "list_users": ActionRisk.LOW,
    "create_draft": ActionRisk.MEDIUM,
    "send_email": ActionRisk.HIGH,
    "delete_record": ActionRisk.HIGH,
    "execute_payment": ActionRisk.HIGH,
}

async def execute_tool(tool_name: str, args: dict, ui: UserInterface):
    risk = TOOL_RISK_LEVELS.get(tool_name, ActionRisk.HIGH)

    if risk == ActionRisk.HIGH:
        confirmed = await ui.confirm(
            f"Agent wants to: {tool_name}\n"
            f"With: {json.dumps(args, indent=2)}\n"
            f"Allow?"
        )
        if not confirmed:
            return {"status": "cancelled", "reason": "user_denied"}

    return tools[tool_name](**args)
```

## LangChain / LangGraph Patterns

### Defining Safe Tools

```python
from langchain.tools import tool
from pydantic import BaseModel, Field

class SearchInput(BaseModel):
    query: str = Field(description="Search query", max_length=500)
    max_results: int = Field(default=10, ge=1, le=50)

@tool(args_schema=SearchInput)
def search_documents(query: str, max_results: int = 10) -> list[dict]:
    """Search internal documents. Returns titles and snippets."""
    # Input validated by Pydantic schema
    return doc_service.search(query, limit=max_results)
```

### Tool Permission Boundaries

```python
from langgraph.graph import StateGraph

def create_agent_with_permissions(user_permissions: set[str]):
    # Only bind tools the user is authorized for
    available_tools = [
        t for t in ALL_TOOLS
        if t.name in user_permissions
    ]

    return agent.bind_tools(available_tools)

# User A gets read-only tools
agent_a = create_agent_with_permissions({"search", "read_file"})

# User B gets write tools too
agent_b = create_agent_with_permissions({"search", "read_file", "send_email"})
```

### Intercepting Tool Calls

```python
from langgraph.prebuilt import ToolNode

class AuditedToolNode(ToolNode):
    def __init__(self, tools, audit_log):
        super().__init__(tools)
        self.audit_log = audit_log

    async def __call__(self, state):
        # Log before execution
        for tool_call in state.get("tool_calls", []):
            self.audit_log.record(
                tool=tool_call["name"],
                args=tool_call["args"],
                user=state.get("user_id"),
                timestamp=datetime.utcnow()
            )

        # Execute
        result = await super().__call__(state)

        # Log result
        self.audit_log.record_result(result)

        return result
```

## Sandboxing Code Execution

If agents can execute code:

```python
import subprocess
import tempfile
import os

class SandboxedPythonExecutor:
    def __init__(self, timeout_seconds: int = 5):
        self.timeout = timeout_seconds

    def execute(self, code: str) -> str:
        # Write to temp file
        with tempfile.NamedTemporaryFile(
            mode='w', suffix='.py', delete=False
        ) as f:
            f.write(code)
            script_path = f.name

        try:
            # Run with restrictions
            result = subprocess.run(
                [
                    "python", "-u", script_path
                ],
                capture_output=True,
                text=True,
                timeout=self.timeout,
                env={
                    "PATH": "/usr/bin",
                    # No access to secrets
                },
                cwd=tempfile.gettempdir(),  # Isolated directory
                # Consider: Docker, gVisor, or Firecracker for stronger isolation
            )
            return result.stdout[:10000]  # Limit output size
        except subprocess.TimeoutExpired:
            return "Execution timed out"
        finally:
            os.unlink(script_path)
```

For production, use proper sandboxes:
- Docker containers with seccomp profiles
- gVisor or Firecracker for stronger isolation
- E2B, Modal, or other sandboxed code execution services

## Audit Checklist

- [ ] Do tools accept typed, validated inputs (Pydantic)?
- [ ] Are parameters constrained to allowlists where applicable?
- [ ] Do tools respect user resource boundaries?
- [ ] Are high-risk actions rate-limited?
- [ ] Do sensitive operations require confirmation?
- [ ] Are tool calls logged for audit?
- [ ] Is code execution sandboxed?
- [ ] Are tool permissions scoped per-user?

## References

- LangChain tool documentation
- Pydantic AI toolsets guide
- OWASP LLM Top 10: LLM07 (Insecure Plugin Design)
