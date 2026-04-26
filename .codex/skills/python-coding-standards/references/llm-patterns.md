# LLM and Agent Patterns

Patterns for building applications with Large Language Models and AI agents.

## Table of Contents

1. [Streaming Response Handling](#streaming-response-handling)
2. [Context Window Management](#context-window-management)
3. [Prompt Construction](#prompt-construction)
4. [Response Parsing](#response-parsing)
5. [Agent Patterns](#agent-patterns)

## Streaming Response Handling

LLM APIs typically stream responses token by token. Handle streams with async generators.

### Basic Streaming Pattern

```python
from collections.abc import AsyncGenerator

async def stream_completion(
    prompt: str,
    model: str = "claude-3-sonnet"
) -> AsyncGenerator[str, None]:
    """Stream LLM completion tokens."""
    async with httpx.AsyncClient() as client:
        async with client.stream(
            "POST",
            "https://api.anthropic.com/v1/messages",
            json={
                "model": model,
                "messages": [{"role": "user", "content": prompt}],
                "stream": True,
                "max_tokens": 1024
            },
            headers={"x-api-key": API_KEY},
            timeout=30.0
        ) as response:
            async for line in response.aiter_lines():
                if line.startswith("data: "):
                    data = json.loads(line[6:])

                    if data["type"] == "content_block_delta":
                        yield data["delta"]["text"]
```

### Streaming with Error Recovery

```python
@dataclass(frozen=True)
class StreamChunk:
    content: str
    metadata: dict[str, Any]

async def robust_stream(
    prompt: str
) -> AsyncGenerator[StreamChunk, None]:
    """Stream with automatic retry on connection errors."""
    max_retries = 3

    for attempt in range(max_retries):
        try:
            async for chunk in stream_completion(prompt):
                yield StreamChunk(
                    content=chunk,
                    metadata={"attempt": attempt + 1}
                )
            return  # Success

        except (httpx.TimeoutException, httpx.ConnectError) as e:
            if attempt == max_retries - 1:
                raise

            logger.warning(f"Stream interrupted, retrying: {e}")
            await asyncio.sleep(2 ** attempt)
```

### Accumulating Streamed Content

```python
async def stream_and_accumulate(
    prompt: str
) -> tuple[str, list[str]]:
    """Stream content while accumulating full response."""
    chunks: list[str] = []

    async for chunk in stream_completion(prompt):
        chunks.append(chunk)
        # Process chunk immediately (e.g., send to client)
        await send_to_client(chunk)

    # Return both accumulated content and individual chunks
    full_response = "".join(chunks)
    return full_response, chunks
```

## Context Window Management

Managing conversation history and context limits is critical for LLM applications.

### Message History as Immutable State

```python
@dataclass(frozen=True)
class Message:
    role: str  # "user" or "assistant"
    content: str
    timestamp: datetime
    token_count: int

@dataclass(frozen=True)
class Conversation:
    messages: tuple[Message, ...]
    max_tokens: int = 100_000

    @property
    def total_tokens(self) -> int:
        return sum(msg.token_count for msg in self.messages)

    def add_message(self, message: Message) -> "Conversation":
        """Return new conversation with added message."""
        return dataclass.replace(
            self,
            messages=self.messages + (message,)
        )

    def trim_to_fit(self, new_message_tokens: int) -> "Conversation":
        """Return conversation trimmed to fit new message."""
        available = self.max_tokens - new_message_tokens

        # Keep newest messages that fit
        trimmed_messages: list[Message] = []
        token_count = 0

        for msg in reversed(self.messages):
            if token_count + msg.token_count <= available:
                trimmed_messages.insert(0, msg)
                token_count += msg.token_count
            else:
                break

        return dataclass.replace(
            self,
            messages=tuple(trimmed_messages)
        )
```

### Token Counting

```python
def count_tokens(text: str, model: str = "claude-3-sonnet") -> int:
    """Estimate token count for text."""
    # Use actual tokenizer for production
    # This is a rough estimate
    return len(text) // 4

def prepare_messages_for_api(
    conversation: Conversation,
    new_message: str,
    max_context_tokens: int
) -> list[dict[str, str]]:
    """Prepare messages for API, trimming if needed."""
    new_msg_tokens = count_tokens(new_message)

    # Check if we need to trim
    if conversation.total_tokens + new_msg_tokens > max_context_tokens:
        conversation = conversation.trim_to_fit(new_msg_tokens)

    # Convert to API format
    messages = [
        {"role": msg.role, "content": msg.content}
        for msg in conversation.messages
    ]
    messages.append({"role": "user", "content": new_message})

    return messages
```

### Sliding Window Pattern

```python
def create_sliding_window(
    messages: list[Message],
    max_tokens: int
) -> list[Message]:
    """Keep most recent messages that fit in window."""
    result: list[Message] = []
    total_tokens = 0

    # Process from newest to oldest
    for msg in reversed(messages):
        if total_tokens + msg.token_count <= max_tokens:
            result.insert(0, msg)
            total_tokens += msg.token_count
        else:
            break

    return result
```

## Prompt Construction

Build prompts as pure functions with clear structure.

### Template-Based Prompts

```python
@dataclass(frozen=True)
class PromptTemplate:
    system: str
    user_template: str

    def format(self, **kwargs) -> str:
        """Format template with values."""
        return self.user_template.format(**kwargs)

# Define templates
SUMMARIZE_TEMPLATE = PromptTemplate(
    system="You are a helpful assistant that creates concise summaries.",
    user_template="""
Please summarize the following text in {max_sentences} sentences or less:

{text}

Summary:
""".strip()
)

def create_summarize_prompt(text: str, max_sentences: int = 3) -> str:
    """Create summarization prompt."""
    return SUMMARIZE_TEMPLATE.format(text=text, max_sentences=max_sentences)
```

### Few-Shot Prompt Construction

```python
@dataclass(frozen=True)
class Example:
    input: str
    output: str

def build_few_shot_prompt(
    task_description: str,
    examples: list[Example],
    query: str
) -> str:
    """Build few-shot prompt with examples."""
    parts = [task_description, ""]

    # Add examples
    for i, example in enumerate(examples, 1):
        parts.append(f"Example {i}:")
        parts.append(f"Input: {example.input}")
        parts.append(f"Output: {example.output}")
        parts.append("")

    # Add query
    parts.append("Now your turn:")
    parts.append(f"Input: {query}")
    parts.append("Output:")

    return "\n".join(parts)
```

## Response Parsing

Parse LLM responses with fallback strategies.

### Structured Output Parsing

```python
from typing import TypeVar
from pydantic import BaseModel, ValidationError

T = TypeVar('T', bound=BaseModel)

def parse_json_response(
    response: str,
    model: type[T],
    fallback: T | None = None
) -> T | None:
    """Parse JSON response with fallback."""
    # Try to extract JSON from response
    json_str = extract_json_from_text(response)

    try:
        data = json.loads(json_str)
        return model.model_validate(data)
    except (json.JSONDecodeError, ValidationError) as e:
        logger.warning(f"Failed to parse response: {e}")
        return fallback

def extract_json_from_text(text: str) -> str:
    """Extract JSON object from text."""
    # Find JSON object between curly braces
    start = text.find("{")
    end = text.rfind("}")

    if start == -1 or end == -1:
        raise ValueError("No JSON object found in text")

    return text[start:end + 1]
```

### Multiple Parse Attempts

```python
def parse_with_fallbacks(
    response: str,
    parsers: list[Callable[[str], T | None]]
) -> T | None:
    """Try multiple parsing strategies."""
    for parser in parsers:
        try:
            result = parser(response)
            if result is not None:
                return result
        except Exception as e:
            logger.debug(f"Parser failed: {e}")
            continue

    return None

# Example usage
def parse_classification(response: str) -> Classification | None:
    return parse_with_fallbacks(
        response,
        [
            parse_json_classification,
            parse_structured_text_classification,
            parse_simple_text_classification
        ]
    )
```

## Agent Patterns

Patterns for building AI agents that can use tools and make decisions.

### Tool Definition

```python
@dataclass(frozen=True)
class Tool:
    name: str
    description: str
    parameters: dict[str, Any]
    function: Callable

# Define available tools
SEARCH_TOOL = Tool(
    name="search",
    description="Search the knowledge base for information",
    parameters={
        "query": {"type": "string", "description": "Search query"}
    },
    function=search_knowledge_base
)

CALCULATE_TOOL = Tool(
    name="calculate",
    description="Perform mathematical calculations",
    parameters={
        "expression": {"type": "string", "description": "Math expression"}
    },
    function=calculate
)
```

### Agent Loop

```python
@dataclass(frozen=True)
class AgentState:
    conversation: Conversation
    tools: tuple[Tool, ...]
    max_iterations: int = 10

async def run_agent(
    initial_query: str,
    state: AgentState
) -> tuple[str, AgentState]:
    """Run agent loop until task complete or max iterations."""
    current_state = state
    iteration = 0

    while iteration < state.max_iterations:
        # Get LLM response
        response = await get_llm_response(
            current_state.conversation,
            current_state.tools
        )

        # Check if agent wants to use a tool
        if tool_call := parse_tool_call(response):
            # Execute tool
            tool_result = await execute_tool(tool_call, current_state.tools)

            # Add to conversation
            current_state = add_tool_exchange(
                current_state,
                tool_call,
                tool_result
            )
        else:
            # Agent provided final answer
            return response, current_state

        iteration += 1

    return "Max iterations reached", current_state
```

### Parallel Tool Execution

```python
async def execute_tools_parallel(
    tool_calls: list[ToolCall],
    tools: tuple[Tool, ...]
) -> list[ToolResult]:
    """Execute multiple tool calls concurrently."""
    async def execute_one(call: ToolCall) -> ToolResult:
        tool = find_tool(call.name, tools)
        try:
            result = await tool.function(**call.parameters)
            return ToolResult(success=True, output=result)
        except Exception as e:
            return ToolResult(success=False, error=str(e))

    results: list[ToolResult] = []

    async with asyncio.TaskGroup() as tg:
        tasks = [tg.create_task(execute_one(call)) for call in tool_calls]

    return [task.result() for task in tasks]
```

### Conversation State Management

```python
def add_tool_exchange(
    state: AgentState,
    tool_call: ToolCall,
    tool_result: ToolResult
) -> AgentState:
    """Add tool call and result to conversation."""
    # Create messages for tool exchange
    tool_call_msg = Message(
        role="assistant",
        content=format_tool_call(tool_call),
        timestamp=datetime.now(),
        token_count=count_tokens(format_tool_call(tool_call))
    )

    tool_result_msg = Message(
        role="user",
        content=format_tool_result(tool_result),
        timestamp=datetime.now(),
        token_count=count_tokens(format_tool_result(tool_result))
    )

    # Add to conversation
    new_conversation = (
        state.conversation
        .add_message(tool_call_msg)
        .add_message(tool_result_msg)
    )

    return dataclass.replace(state, conversation=new_conversation)
```
