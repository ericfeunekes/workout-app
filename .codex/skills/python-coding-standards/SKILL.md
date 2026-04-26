---
name: python-coding-standards
description: Modern Python coding standards (3.11+) for APIs, LLM/agent systems, and
---
# Python Coding Standards

Modern Python coding guidelines optimized for APIs, LLM/agent systems, and data pipelines using Python 3.11+.

## Philosophy

Write **simple code** that's easy to reason about. Favor pure functions, immutable data, and explicit dependencies. Code should be obvious in intent and straightforward to modify.

## Core Patterns

### Functional Style
- Pure functions as default - same inputs produce same outputs
- Isolate side effects into dedicated functions (one side effect per function)
- Use frozen dataclasses for immutable data structures
- Extract complex logic into small, well-named pure functions

### Type Safety
- Always use type hints with modern syntax (`list` not `List`)
- Import from `collections.abc` where applicable (`from collections.abc import Callable`)
- Use frozen dataclasses as function parameter objects for flexibility
- Boundaries that speak HTTP/JSON (e.g., FastAPI request/response models) can use Pydantic for validation, but convert to frozen dataclasses as soon as you enter the domain layer to preserve functional, immutable workflows

### Code Organization
- Start with the main operational function (meaningful name, not "main")
- Break down into meaningfully named sub-functions
- Implement recursively - each function decomposed the same way
- Group related dataclasses with functions that operate on them

## When to Read References

The following reference files provide detailed guidance for specific scenarios:

### **Starting a new project or module?**
→ Read `reference:python-coding-standards/core-patterns.md` for foundational patterns

### **Writing async code or APIs?**
→ Read `reference:python-coding-standards/async-patterns.md` for modern asyncio patterns

### **Structuring a larger application?**
→ Read `reference:python-coding-standards/architecture.md` for service layer, repository pattern, and dependency injection

### **Handling errors and logging?**
→ Read `reference:python-coding-standards/error-handling.md` for exception hierarchies and structured logging

### **Working with LLMs or agents?**
→ Read `reference:python-coding-standards/llm-patterns.md` for streaming, context management, and agent patterns

### **Building data pipelines?**
→ Read `reference:python-coding-standards/data-pipeline-patterns.md` for batch processing, checkpointing, and idempotency

### **Code review or refactoring?**
→ Read `reference:python-coding-standards/antipatterns.md` to identify common mistakes and how to fix them

## Quick Reference

**Dataclasses for everything:**
```python
from dataclasses import dataclass

@dataclass(frozen=True)
class ProcessOrderParams:
    order_id: str
    customer_id: str
    timestamp: datetime
    priority: bool = False

def process_order(params: ProcessOrderParams) -> OrderResult:
    # Easy to add/remove parameters without changing signatures
    validated = validate_order(params)
    enriched = enrich_with_customer_data(validated)
    return finalize_order(enriched)
```

**Dependency injection:**
```python
# Interface
class UserRepository(Protocol):
    async def get_by_id(self, id: str) -> User | None: ...

# Service with injected dependencies
class UserService:
    def __init__(self, repo: UserRepository, cache: CacheService):
        self.repo = repo
        self.cache = cache

    async def get_user(self, user_id: str) -> User:
        if cached := await self.cache.get(f"user:{user_id}"):
            return User.model_validate_json(cached)

        user = await self.repo.get_by_id(user_id)
        await self.cache.set(f"user:{user_id}", user.model_dump_json())
        return user
```

**Modern async (Python 3.11+):**
```python
import asyncio

async def main():
    try:
        async with asyncio.TaskGroup() as tg:
            task1 = tg.create_task(fetch_data(1))
            task2 = tg.create_task(fetch_data(2))
            task3 = tg.create_task(fetch_data(3))
    except* ValueError as eg:
        # Handle all ValueErrors together
        for exc in eg.exceptions:
            logger.error(f"Validation failed: {exc}")
    except* TimeoutError as eg:
        # Handle all timeouts together
        for exc in eg.exceptions:
            logger.error(f"Request timed out: {exc}")
```

Read the reference files above for comprehensive patterns and examples.
