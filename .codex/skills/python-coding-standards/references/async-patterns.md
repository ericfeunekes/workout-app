# Async Patterns

Modern asyncio patterns for Python 3.11+ including TaskGroup, exception handling, and concurrency control.

## Table of Contents

1. [TaskGroup for Concurrent Operations](#taskgroup-for-concurrent-operations)
2. [Exception Handling with ExceptionGroup](#exception-handling-with-exceptiongroup)
3. [Resource Management](#resource-management)
4. [Concurrency Control](#concurrency-control)
5. [Async Generators for Streaming](#async-generators-for-streaming)
6. [Common Patterns](#common-patterns)

## TaskGroup for Concurrent Operations

Python 3.11+ provides `TaskGroup` for managing concurrent tasks with automatic cleanup and exception handling.

### Basic Usage

```python
import asyncio

async def fetch_user_data(user_id: str) -> UserData:
    async with httpx.AsyncClient() as client:
        response = await client.get(f"/users/{user_id}")
        return UserData.model_validate(response.json())

async def fetch_multiple_users(user_ids: list[str]) -> list[UserData]:
    """Fetch multiple users concurrently."""
    results: list[UserData] = []

    async with asyncio.TaskGroup() as tg:
        tasks = [
            tg.create_task(fetch_user_data(user_id))
            for user_id in user_ids
        ]

    # All tasks complete when exiting the context manager
    return [task.result() for task in tasks]
```

### Task Cancellation Behavior

**Critical:** TaskGroup cancels ALL remaining tasks if one task fails with an exception.

```python
async def task_a():
    await asyncio.sleep(1)
    print("Task A complete")

async def task_b():
    await asyncio.sleep(0.5)
    raise ValueError("Task B failed!")

async def task_c():
    await asyncio.sleep(2)
    print("Task C complete")  # Never prints

async def main():
    try:
        async with asyncio.TaskGroup() as tg:
            tg.create_task(task_a())
            tg.create_task(task_b())
            tg.create_task(task_c())  # Gets cancelled when task_b fails
    except ExceptionGroup as eg:
        print(f"Caught {len(eg.exceptions)} exceptions")
```

### Handling Exceptions Within Tasks

If you want tasks to continue despite individual failures, handle exceptions inside the task.

```python
async def fetch_with_fallback(url: str) -> str | None:
    """Fetch URL, returning None on failure instead of raising."""
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(url)
            return response.text
    except Exception as e:
        logger.error(f"Failed to fetch {url}: {e}")
        return None

async def fetch_all_urls(urls: list[str]) -> list[str | None]:
    """Fetch all URLs, continuing even if some fail."""
    results: list[str | None] = []

    async with asyncio.TaskGroup() as tg:
        tasks = [tg.create_task(fetch_with_fallback(url)) for url in urls]

    return [task.result() for task in tasks]
```

## Exception Handling with ExceptionGroup

Python 3.11+ introduces `ExceptionGroup` and `except*` syntax for handling multiple concurrent exceptions.

### Basic Exception Groups

```python
async def process_with_error_collection(items: list[str]) -> ProcessResult:
    """Process items, collecting all errors."""
    try:
        async with asyncio.TaskGroup() as tg:
            tasks = [tg.create_task(process_item(item)) for item in items]
    except* ValueError as eg:
        # Handle all ValueErrors together
        logger.error(f"Validation errors: {len(eg.exceptions)}")
        for exc in eg.exceptions:
            logger.error(f"  - {exc}")
    except* TimeoutError as eg:
        # Handle all timeouts together
        logger.error(f"Timeout errors: {len(eg.exceptions)}")
        for exc in eg.exceptions:
            logger.error(f"  - {exc}")
    except* Exception as eg:
        # Catch any other exceptions
        logger.error(f"Unexpected errors: {len(eg.exceptions)}")
        for exc in eg.exceptions:
            logger.error(f"  - {exc}")
```

### Multiple Exception Types

The `except*` syntax allows handling multiple exception types from the same group.

```python
async def robust_processing(items: list[Item]) -> ProcessResult:
    errors: dict[str, list[Exception]] = {
        "validation": [],
        "timeout": [],
        "other": []
    }

    try:
        async with asyncio.TaskGroup() as tg:
            for item in items:
                tg.create_task(process_item(item))
    except* ValidationError as eg:
        errors["validation"].extend(eg.exceptions)
    except* TimeoutError as eg:
        errors["timeout"].extend(eg.exceptions)
    except* Exception as eg:
        errors["other"].extend(eg.exceptions)

    return ProcessResult(
        success=not any(errors.values()),
        error_counts={k: len(v) for k, v in errors.items()}
    )
```

### Unhandled Exceptions Propagate

If you don't catch all exception types, unhandled exceptions propagate as an ExceptionGroup.

```python
async def partial_handling():
    try:
        async with asyncio.TaskGroup() as tg:
            tg.create_task(raises_value_error())
            tg.create_task(raises_type_error())
    except* ValueError as eg:
        print(f"Handled {len(eg.exceptions)} ValueErrors")
        # TypeError still propagates
```

## Resource Management

### Async Context Managers

Always use async context managers for resources requiring cleanup.

```python
from collections.abc import AsyncGenerator

class DatabaseConnection:
    async def __aenter__(self):
        self.conn = await connect_to_database()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.conn.close()
        return False

# Usage
async def get_user(user_id: str) -> User:
    async with DatabaseConnection() as db:
        return await db.fetch_user(user_id)
```

### Async Generator Cleanup

Async generators automatically handle cleanup with `try/finally`.

```python
async def stream_user_events(user_id: str) -> AsyncGenerator[Event, None]:
    """Stream events for user, ensuring cleanup."""
    conn = await connect_to_event_stream()
    try:
        async for event in conn.subscribe(f"user:{user_id}"):
            yield event
    finally:
        await conn.close()
        logger.info(f"Closed event stream for user {user_id}")

# Usage
async for event in stream_user_events("123"):
    await process_event(event)
# Connection automatically closed when iteration ends
```

## Concurrency Control

### Semaphores for Rate Limiting

Use semaphores to limit concurrent operations.

```python
async def fetch_with_semaphore(
    url: str,
    semaphore: asyncio.Semaphore
) -> str:
    """Fetch URL with concurrency limit."""
    async with semaphore:
        async with httpx.AsyncClient() as client:
            response = await client.get(url)
            return response.text

async def fetch_many_urls(urls: list[str], max_concurrent: int = 10) -> list[str]:
    """Fetch many URLs with concurrency limit."""
    semaphore = asyncio.Semaphore(max_concurrent)
    results: list[str] = []

    async with asyncio.TaskGroup() as tg:
        tasks = [
            tg.create_task(fetch_with_semaphore(url, semaphore))
            for url in urls
        ]

    return [task.result() for task in tasks]
```

### Timeouts

Use `asyncio.timeout()` for operation timeouts (Python 3.11+).

```python
async def fetch_with_timeout(url: str, timeout_seconds: float) -> str:
    """Fetch URL with timeout."""
    try:
        async with asyncio.timeout(timeout_seconds):
            async with httpx.AsyncClient() as client:
                response = await client.get(url)
                return response.text
    except TimeoutError:
        logger.error(f"Request to {url} timed out after {timeout_seconds}s")
        raise

# For multiple operations
async def fetch_all_with_timeout(urls: list[str]) -> list[str]:
    """Fetch all URLs with overall timeout."""
    try:
        async with asyncio.timeout(30.0):  # Total timeout for all
            return await fetch_many_urls(urls)
    except TimeoutError:
        logger.error("Batch fetch timed out")
        raise
```

## Async Generators for Streaming

### Basic Streaming Pattern

```python
async def stream_large_dataset(
    query: str
) -> AsyncGenerator[DataChunk, None]:
    """Stream large dataset in chunks."""
    offset = 0
    batch_size = 1000

    while True:
        batch = await fetch_batch(query, offset, batch_size)

        if not batch:
            break

        for item in batch:
            yield DataChunk(data=item, offset=offset)

        offset += len(batch)
```

### Streaming with Resource Management

```python
async def stream_file_lines(
    filepath: str
) -> AsyncGenerator[str, None]:
    """Stream file lines with proper cleanup."""
    async with aiofiles.open(filepath, 'r') as f:
        async for line in f:
            yield line.strip()

async def process_large_file(filepath: str) -> ProcessResult:
    """Process large file without loading into memory."""
    count = 0

    async for line in stream_file_lines(filepath):
        await process_line(line)
        count += 1

    return ProcessResult(lines_processed=count)
```

### Merging Multiple Async Generators

```python
async def merge_streams(
    *generators: AsyncGenerator[T, None]
) -> AsyncGenerator[T, None]:
    """Merge multiple async generators into single stream."""
    queue: asyncio.Queue[T | None] = asyncio.Queue()

    async def consume(gen: AsyncGenerator[T, None], queue: asyncio.Queue):
        try:
            async for item in gen:
                await queue.put(item)
        finally:
            await queue.put(None)  # Sentinel

    async with asyncio.TaskGroup() as tg:
        for gen in generators:
            tg.create_task(consume(gen, queue))

        # Yield items as they arrive
        finished = 0
        while finished < len(generators):
            item = await queue.get()
            if item is None:
                finished += 1
            else:
                yield item
```

## Common Patterns

### Retry with Exponential Backoff

```python
async def retry_with_backoff(
    operation: Callable[[], Awaitable[T]],
    max_retries: int = 3,
    base_delay: float = 1.0
) -> T:
    """Retry async operation with exponential backoff."""
    for attempt in range(max_retries):
        try:
            return await operation()
        except Exception as e:
            if attempt == max_retries - 1:
                raise

            delay = base_delay * (2 ** attempt)
            logger.warning(f"Attempt {attempt + 1} failed, retrying in {delay}s: {e}")
            await asyncio.sleep(delay)

    raise RuntimeError("Unreachable")  # Type checker satisfaction

# Usage
user = await retry_with_backoff(
    lambda: fetch_user("123"),
    max_retries=3,
    base_delay=1.0
)
```

### Parallel with Fallback

```python
async def fetch_with_fallback_sources(
    primary_url: str,
    fallback_urls: list[str]
) -> str:
    """Try primary source, fall back to alternatives."""
    try:
        async with asyncio.timeout(5.0):
            return await fetch_url(primary_url)
    except Exception as e:
        logger.warning(f"Primary source failed: {e}, trying fallbacks")

    for fallback_url in fallback_urls:
        try:
            return await fetch_url(fallback_url)
        except Exception as e:
            logger.warning(f"Fallback {fallback_url} failed: {e}")

    raise RuntimeError("All sources failed")
```

### Async Caching

```python
from functools import wraps

def async_cache(ttl_seconds: int):
    """Cache async function results with TTL."""
    def decorator(func: Callable):
        cache: dict[str, tuple[Any, float]] = {}

        @wraps(func)
        async def wrapper(*args, **kwargs):
            key = f"{func.__name__}:{args}:{kwargs}"

            if key in cache:
                value, timestamp = cache[key]
                if time.time() - timestamp < ttl_seconds:
                    return value

            result = await func(*args, **kwargs)
            cache[key] = (result, time.time())
            return result

        return wrapper
    return decorator

@async_cache(ttl_seconds=300)
async def fetch_expensive_data(query: str) -> Data:
    """Fetch data with 5-minute cache."""
    return await expensive_api_call(query)
```

### Connection Pooling

```python
class ConnectionPool:
    def __init__(self, max_connections: int):
        self.semaphore = asyncio.Semaphore(max_connections)
        self.connections: list[Connection] = []

    async def acquire(self) -> Connection:
        """Acquire connection from pool."""
        async with self.semaphore:
            if self.connections:
                return self.connections.pop()
            return await create_connection()

    async def release(self, conn: Connection) -> None:
        """Release connection back to pool."""
        self.connections.append(conn)

# Usage
pool = ConnectionPool(max_connections=10)

async def query_database(query: str) -> list[Row]:
    conn = await pool.acquire()
    try:
        return await conn.execute(query)
    finally:
        await pool.release(conn)
```
