# Error Handling and Logging

Modern error handling patterns, custom exceptions, and structured logging.

## Table of Contents

1. [Exception Hierarchies](#exception-hierarchies)
2. [Exception Handling Patterns](#exception-handling-patterns)
3. [Structured Logging](#structured-logging)
4. [Context Management](#context-management)
5. [Retry Patterns](#retry-patterns)

## Exception Hierarchies

Create domain-specific exception hierarchies that are meaningful to your application.

### Custom Exception Design

```python
class AppError(Exception):
    """Base exception for all application errors."""
    pass

class ValidationError(AppError):
    """Raised when data validation fails."""

    def __init__(self, field: str, message: str):
        self.field = field
        self.message = message
        super().__init__(f"{field}: {message}")

class ResourceNotFoundError(AppError):
    """Raised when a requested resource doesn't exist."""

    def __init__(self, resource_type: str, resource_id: str):
        self.resource_type = resource_type
        self.resource_id = resource_id
        super().__init__(f"{resource_type} {resource_id} not found")

class ExternalServiceError(AppError):
    """Raised when external service call fails."""

    def __init__(self, service: str, original_error: Exception):
        self.service = service
        self.original_error = original_error
        super().__init__(f"{service} error: {original_error}")
```

### When to Create Custom Exceptions

Create custom exceptions when:
- The error represents a specific domain concept
- Callers need to handle it differently from other errors
- You need to attach structured data to the exception

```python
# ✅ Good - meaningful domain exceptions
class InsufficientFundsError(AppError):
    def __init__(self, account_id: str, required: Decimal, available: Decimal):
        self.account_id = account_id
        self.required = required
        self.available = available
        super().__init__(
            f"Account {account_id}: insufficient funds "
            f"(required: {required}, available: {available})"
        )

# ❌ Bad - too generic
class ProcessingError(Exception):
    pass
```

## Exception Handling Patterns

### Handle at the Right Level

Handle exceptions where you have context to do something meaningful.

```python
# ✅ Good - handle where you know what to do
async def get_user_profile(user_id: str) -> UserProfile:
    """Get user profile with fallback to default."""
    try:
        return await fetch_user_profile(user_id)
    except ResourceNotFoundError:
        # We know how to handle this - return default
        logger.info(f"Profile not found for {user_id}, using default")
        return get_default_profile()
    # Let other exceptions propagate

# ❌ Bad - catching exception with no idea how to handle it
async def get_user_profile_bad(user_id: str) -> UserProfile:
    try:
        return await fetch_user_profile(user_id)
    except Exception as e:
        logger.error(f"Error: {e}")
        # Now what? Can't recover, can't provide meaningful result
        return None  # Type error!
```

### Specific Exception Handling

Catch specific exceptions, not broad categories.

```python
# ✅ Good - specific exception handling
async def process_payment(payment: Payment) -> PaymentResult:
    try:
        return await payment_gateway.charge(payment)
    except InsufficientFundsError as e:
        logger.warning(f"Insufficient funds: {e}")
        return PaymentResult(status="declined", reason="insufficient_funds")
    except PaymentGatewayTimeoutError as e:
        logger.error(f"Gateway timeout: {e}")
        return PaymentResult(status="error", reason="timeout")
    except PaymentGatewayError as e:
        logger.error(f"Gateway error: {e}")
        return PaymentResult(status="error", reason="gateway_error")

# ❌ Bad - catching everything
async def process_payment_bad(payment: Payment) -> PaymentResult:
    try:
        return await payment_gateway.charge(payment)
    except Exception as e:  # Too broad
        logger.error(f"Error: {e}")
        return PaymentResult(status="error")
```

### Log and Re-raise

Log exceptions only once, at the boundary where they're handled.

```python
# ✅ Good - log at handling boundary
async def api_endpoint():
    try:
        return await process_request()
    except AppError as e:
        logger.error(f"Request failed: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

# ❌ Bad - logging at every level
async def process_request():
    try:
        return await do_work()
    except Exception as e:
        logger.error(f"Error in process_request: {e}")  # First log
        raise

async def do_work():
    try:
        return await do_actual_work()
    except Exception as e:
        logger.error(f"Error in do_work: {e}")  # Second log
        raise

async def do_actual_work():
    try:
        # Some work
        pass
    except Exception as e:
        logger.error(f"Error in do_actual_work: {e}")  # Third log!
        raise
```

### Exception Groups (Python 3.11+)

Use `ExceptionGroup` for concurrent operations that may fail independently.

```python
async def process_batch(items: list[Item]) -> BatchResult:
    """Process items concurrently, collecting all errors."""
    try:
        async with asyncio.TaskGroup() as tg:
            tasks = [tg.create_task(process_item(item)) for item in items]
    except* ValidationError as eg:
        logger.error(f"Validation errors: {len(eg.exceptions)}")
        for exc in eg.exceptions:
            logger.error(f"  {exc.field}: {exc.message}")
    except* TimeoutError as eg:
        logger.error(f"Timeout errors: {len(eg.exceptions)}")
    except* Exception as eg:
        logger.error(f"Unexpected errors: {len(eg.exceptions)}")
        # May want to raise these
        raise
```

## Structured Logging

Use structured logging for production applications. Structured logs are machine-readable and easily searchable.

### JSON Logging

```python
import logging
import json
from datetime import datetime

class JSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        log_data = {
            "timestamp": datetime.utcnow().isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "module": record.module,
            "function": record.funcName,
            "line": record.lineno
        }

        # Add exception info if present
        if record.exc_info:
            log_data["exception"] = {
                "type": record.exc_info[0].__name__,
                "message": str(record.exc_info[1]),
                "traceback": self.formatException(record.exc_info)
            }

        # Add custom fields
        if hasattr(record, "user_id"):
            log_data["user_id"] = record.user_id
        if hasattr(record, "request_id"):
            log_data["request_id"] = record.request_id

        return json.dumps(log_data)

# Setup
handler = logging.FileHandler("app.log")
handler.setFormatter(JSONFormatter())

logger = logging.getLogger(__name__)
logger.addHandler(handler)
logger.setLevel(logging.INFO)
```

### Context Variables for Request Tracking

Use `contextvars` to attach context to log messages.

```python
from contextvars import ContextVar
import logging

# Context variables
request_id: ContextVar[str | None] = ContextVar("request_id", default=None)
user_id: ContextVar[str | None] = ContextVar("user_id", default=None)

class ContextFilter(logging.Filter):
    """Add context variables to log records."""

    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = request_id.get()
        record.user_id = user_id.get()
        return True

# Setup
logger = logging.getLogger(__name__)
logger.addFilter(ContextFilter())

# In request handler
async def handle_request(request: Request):
    request_id.set(request.headers.get("X-Request-ID", generate_id()))
    user_id.set(request.user.id)

    # All logs in this context include request_id and user_id
    logger.info("Processing request")
    await process_request(request)
    logger.info("Request complete")
```

### Logging Best Practices

```python
# ✅ Good - structured logging with context
logger.info(
    "Order processed",
    extra={
        "order_id": order.id,
        "user_id": order.user_id,
        "total": float(order.total),
        "items_count": len(order.items)
    }
)

# ❌ Bad - string formatting in log message
logger.info(f"Order {order.id} for user {order.user_id} total ${order.total}")

# ✅ Good - use exc_info for exception logging
try:
    await dangerous_operation()
except Exception as e:
    logger.error("Operation failed", exc_info=True)

# ❌ Bad - just logging exception message
except Exception as e:
    logger.error(f"Operation failed: {e}")  # Loses stack trace

# ✅ Good - different log levels for different purposes
logger.debug("Detailed debug info for development")
logger.info("Normal operational messages")
logger.warning("Something unexpected but handled")
logger.error("Error that needs attention")
logger.critical("System is in critical state")

# ❌ Bad - using same level for everything
logger.info("Debug info")
logger.info("Error occurred")
logger.info("System critical")
```

## Context Management

Use context managers to ensure cleanup even when exceptions occur.

### Custom Context Managers

```python
from contextlib import asynccontextmanager
from collections.abc import AsyncGenerator

@asynccontextmanager
async def database_transaction() -> AsyncGenerator[AsyncSession, None]:
    """Manage database transaction with automatic rollback on error."""
    session = await get_session()
    try:
        yield session
        await session.commit()
        logger.info("Transaction committed")
    except Exception as e:
        await session.rollback()
        logger.error(f"Transaction rolled back: {e}", exc_info=True)
        raise
    finally:
        await session.close()

# Usage
async def transfer_funds(from_account: str, to_account: str, amount: Decimal):
    async with database_transaction() as session:
        # Debit from account
        await debit_account(session, from_account, amount)

        # Credit to account
        await credit_account(session, to_account, amount)

        # If any operation fails, entire transaction rolls back
```

### Resource Cleanup

```python
@asynccontextmanager
async def managed_resource(resource_name: str) -> AsyncGenerator[Resource, None]:
    """Acquire and release resource with logging."""
    logger.info(f"Acquiring {resource_name}")
    resource = await acquire_resource(resource_name)

    try:
        yield resource
    finally:
        await resource.close()
        logger.info(f"Released {resource_name}")

# Usage
async def use_resource():
    async with managed_resource("database") as db:
        await db.query("SELECT * FROM users")
    # Resource automatically cleaned up
```

## Retry Patterns

Implement retry logic for transient failures.

### Retry with Exponential Backoff

```python
from typing import TypeVar
from collections.abc import Callable, Awaitable

T = TypeVar('T')

async def retry_with_backoff(
    operation: Callable[[], Awaitable[T]],
    max_retries: int = 3,
    base_delay: float = 1.0,
    max_delay: float = 60.0,
    exponential_base: float = 2.0
) -> T:
    """Retry operation with exponential backoff."""
    last_exception: Exception | None = None

    for attempt in range(max_retries):
        try:
            return await operation()
        except Exception as e:
            last_exception = e

            if attempt == max_retries - 1:
                # Last attempt - don't retry
                break

            delay = min(base_delay * (exponential_base ** attempt), max_delay)
            logger.warning(
                f"Attempt {attempt + 1}/{max_retries} failed, "
                f"retrying in {delay:.1f}s: {e}"
            )
            await asyncio.sleep(delay)

    # All retries exhausted
    logger.error(f"All {max_retries} attempts failed")
    raise last_exception

# Usage
data = await retry_with_backoff(
    lambda: fetch_data_from_api(),
    max_retries=5,
    base_delay=1.0
)
```

### Retry with Jitter

Add randomness to prevent thundering herd.

```python
import random

async def retry_with_jitter(
    operation: Callable[[], Awaitable[T]],
    max_retries: int = 3,
    base_delay: float = 1.0
) -> T:
    """Retry with exponential backoff and jitter."""
    for attempt in range(max_retries):
        try:
            return await operation()
        except Exception as e:
            if attempt == max_retries - 1:
                raise

            # Exponential backoff with jitter
            delay = base_delay * (2 ** attempt)
            jittered_delay = delay * (0.5 + random.random())

            logger.warning(f"Retry {attempt + 1}/{max_retries} after {jittered_delay:.1f}s")
            await asyncio.sleep(jittered_delay)

    raise RuntimeError("Unreachable")
```

### Circuit Breaker Pattern

Prevent cascading failures by "opening the circuit" after repeated failures.

```python
from dataclasses import dataclass
from datetime import datetime, timedelta
from enum import Enum

class CircuitState(Enum):
    CLOSED = "closed"  # Normal operation
    OPEN = "open"  # Failing, reject requests
    HALF_OPEN = "half_open"  # Testing if service recovered

@dataclass
class CircuitBreaker:
    failure_threshold: int = 5
    timeout: timedelta = timedelta(seconds=60)

    state: CircuitState = CircuitState.CLOSED
    failure_count: int = 0
    last_failure_time: datetime | None = None

    async def call(self, operation: Callable[[], Awaitable[T]]) -> T:
        """Execute operation through circuit breaker."""
        # Check if we should try again
        if self.state == CircuitState.OPEN:
            if datetime.now() - self.last_failure_time > self.timeout:
                self.state = CircuitState.HALF_OPEN
                logger.info("Circuit breaker entering half-open state")
            else:
                raise CircuitBreakerOpenError("Circuit breaker is open")

        try:
            result = await operation()

            # Success - reset if we were testing
            if self.state == CircuitState.HALF_OPEN:
                self.state = CircuitState.CLOSED
                self.failure_count = 0
                logger.info("Circuit breaker closed")

            return result

        except Exception as e:
            self.failure_count += 1
            self.last_failure_time = datetime.now()

            if self.failure_count >= self.failure_threshold:
                self.state = CircuitState.OPEN
                logger.error(
                    f"Circuit breaker opened after {self.failure_count} failures"
                )

            raise

# Usage
breaker = CircuitBreaker(failure_threshold=5, timeout=timedelta(seconds=60))

async def call_external_service():
    return await breaker.call(lambda: fetch_from_api())
```
