# Anti-Patterns to Avoid

Common mistakes and anti-patterns in Python code, and how to fix them.

## Table of Contents

1. [Dependency Injection Anti-Patterns](#dependency-injection-anti-patterns)
2. [Error Handling Anti-Patterns](#error-handling-anti-patterns)
3. [Async Anti-Patterns](#async-anti-patterns)
4. [Architecture Anti-Patterns](#architecture-anti-patterns)
5. [General Anti-Patterns](#general-anti-patterns)

## Dependency Injection Anti-Patterns

### Service Locator Pattern

**❌ Bad:** Global container that hides dependencies.

```python
# Anti-pattern: service locator
class ServiceLocator:
    _services = {}

    @classmethod
    def get_service(cls, name: str):
        return cls._services[name]

class OrderService:
    def __init__(self):
        # Dependencies hidden - hard to test
        self.repo = ServiceLocator.get_service("order_repo")
        self.email = ServiceLocator.get_service("email")
```

**✅ Good:** Explicit constructor injection.

```python
class OrderService:
    def __init__(self, repo: OrderRepository, email_service: EmailService):
        self.repo = repo
        self.email_service = email_service
```

### Over-Injection

**❌ Bad:** Too many dependencies create bloated constructors.

```python
class OrderService:
    def __init__(
        self,
        order_repo: OrderRepository,
        user_repo: UserRepository,
        product_repo: ProductRepository,
        payment_service: PaymentService,
        email_service: EmailService,
        sms_service: SMSService,
        notification_service: NotificationService,
        audit_service: AuditService,
        cache_service: CacheService
    ):
        # Too many dependencies!
        pass
```

**✅ Good:** Compose services or use facade.

```python
class NotificationFacade:
    """Single service combining notification methods."""
    def __init__(
        self,
        email: EmailService,
        sms: SMSService,
        push: NotificationService
    ):
        self.email = email
        self.sms = sms
        self.push = push

class OrderService:
    def __init__(
        self,
        order_repo: OrderRepository,
        payment_service: PaymentService,
        notification: NotificationFacade
    ):
        self.order_repo = order_repo
        self.payment_service = payment_service
        self.notification = notification
```

### Scope Mismanagement

**❌ Bad:** Sharing state across requests or tests.

```python
# Global state shared across requests
cache = {}

@router.get("/users/{user_id}")
async def get_user(user_id: str):
    if user_id in cache:
        return cache[user_id]
    # ...
    cache[user_id] = user
    return user
```

**✅ Good:** Request-scoped dependencies.

```python
async def get_cache() -> AsyncGenerator[dict, None]:
    """Request-scoped cache."""
    cache = {}
    yield cache

@router.get("/users/{user_id}")
async def get_user(
    user_id: str,
    cache: Annotated[dict, Depends(get_cache)]
):
    if user_id in cache:
        return cache[user_id]
    # ...
```

## Error Handling Anti-Patterns

### Catching Too Broadly

**❌ Bad:** Catching all exceptions indiscriminately.

```python
async def process_request():
    try:
        return await do_work()
    except Exception as e:  # Too broad!
        logger.error(f"Error: {e}")
        return None  # Now what?
```

**✅ Good:** Catch specific exceptions you know how to handle.

```python
async def process_request():
    try:
        return await do_work()
    except ValidationError as e:
        logger.warning(f"Invalid input: {e}")
        raise HTTPException(status_code=400, detail=str(e))
    except ResourceNotFoundError as e:
        logger.info(f"Resource not found: {e}")
        raise HTTPException(status_code=404, detail=str(e))
    # Let other exceptions propagate
```

### Logging Same Exception Multiple Times

**❌ Bad:** Logging at every layer.

```python
async def level_3():
    try:
        await do_work()
    except Exception as e:
        logger.error(f"Error in level_3: {e}")
        raise

async def level_2():
    try:
        await level_3()
    except Exception as e:
        logger.error(f"Error in level_2: {e}")
        raise

async def level_1():
    try:
        await level_2()
    except Exception as e:
        logger.error(f"Error in level_1: {e}")
        raise
```

**✅ Good:** Log once at the boundary.

```python
async def process_request():
    try:
        await level_1()
    except Exception as e:
        logger.error(f"Request failed: {e}", exc_info=True)
        raise HTTPException(status_code=500)

async def level_1():
    await level_2()  # No logging

async def level_2():
    await level_3()  # No logging
```

### Swallowing Exceptions

**❌ Bad:** Catching exceptions without handling them.

```python
try:
    important_operation()
except Exception:
    pass  # Silently swallowed!
```

**✅ Good:** Only catch exceptions you can handle.

```python
try:
    important_operation()
except SpecificExpectedError as e:
    logger.warning(f"Expected error occurred: {e}")
    return default_value()
# Let unexpected exceptions propagate
```

## Async Anti-Patterns

### Mixing Sync and Async

**❌ Bad:** Calling sync blocking code in async functions.

```python
async def fetch_data():
    time.sleep(1)  # Blocks entire event loop!
    return data
```

**✅ Good:** Use async equivalents.

```python
async def fetch_data():
    await asyncio.sleep(1)  # Yields to event loop
    return data
```

### Not Using TaskGroup Properly

**❌ Bad:** Using `gather()` without exception handling.

```python
async def process_items(items: list[Item]):
    await asyncio.gather(
        *[process_item(item) for item in items]
    )
    # If any task fails, other tasks may be in undefined state
```

**✅ Good:** Use TaskGroup with proper exception handling.

```python
async def process_items(items: list[Item]):
    try:
        async with asyncio.TaskGroup() as tg:
            for item in items:
                tg.create_task(process_item(item))
    except* ValidationError as eg:
        logger.error(f"Validation errors: {len(eg.exceptions)}")
    # All tasks properly cleaned up
```

### Creating New Event Loop

**❌ Bad:** Creating event loops in async code.

```python
async def bad_pattern():
    loop = asyncio.new_event_loop()  # Don't do this in async code!
    return loop.run_until_complete(some_task())
```

**✅ Good:** Just await.

```python
async def good_pattern():
    return await some_task()
```

### Not Using Context Managers for Resources

**❌ Bad:** Manual resource cleanup.

```python
async def fetch_data():
    client = httpx.AsyncClient()
    response = await client.get(url)
    await client.aclose()  # What if exception occurs?
    return response
```

**✅ Good:** Use async context manager.

```python
async def fetch_data():
    async with httpx.AsyncClient() as client:
        response = await client.get(url)
        return response
    # Client automatically closed
```

## Architecture Anti-Patterns

### Business Logic in HTTP Layer

**❌ Bad:** Business logic mixed with HTTP handling.

```python
@router.post("/orders")
async def create_order(data: dict, db: Session):
    # Validation logic in route
    if not data.get("items"):
        raise HTTPException(400, "Items required")

    # Business logic in route
    total = sum(item["price"] * item["qty"] for item in data["items"])
    if total < 10:
        raise HTTPException(400, "Minimum order $10")

    # Database access in route
    order = Order(**data, total=total)
    db.add(order)
    db.commit()

    return order
```

**✅ Good:** Separate concerns into layers.

```python
@router.post("/orders")
async def create_order(
    data: CreateOrderRequest,
    service: Annotated[OrderService, Depends(get_order_service)]
):
    try:
        order = await service.create_order(data)
        return order
    except ValidationError as e:
        raise HTTPException(400, str(e))
```

### God Service

**❌ Bad:** Service that does everything.

```python
class BusinessService:
    def create_user(self, ...): pass
    def create_order(self, ...): pass
    def process_payment(self, ...): pass
    def send_email(self, ...): pass
    def generate_report(self, ...): pass
    # 50 more methods...
```

**✅ Good:** Single-responsibility services.

```python
class UserService:
    def create_user(self, ...): pass
    def update_user(self, ...): pass

class OrderService:
    def create_order(self, ...): pass
    def cancel_order(self, ...): pass

class PaymentService:
    def process_payment(self, ...): pass
```

### Leaky Abstractions

**❌ Bad:** Repository exposing database models.

```python
class UserRepository:
    async def get_by_id(self, user_id: str) -> SQLAlchemyUser:
        return await self.db.get(SQLAlchemyUser, user_id)
```

**✅ Good:** Repository returning domain models.

```python
class UserRepository:
    async def get_by_id(self, user_id: str) -> User:
        model = await self.db.get(SQLAlchemyUser, user_id)
        return self._to_domain(model)

    def _to_domain(self, model: SQLAlchemyUser) -> User:
        return User(id=model.id, name=model.name, email=model.email)
```

## General Anti-Patterns

### Mutable Default Arguments

**❌ Bad:** Using mutable defaults.

```python
def add_item(item: str, items: list[str] = []):
    items.append(item)
    return items
```

**✅ Good:** Use None and create new list.

```python
def add_item(item: str, items: list[str] | None = None) -> list[str]:
    if items is None:
        items = []
    items.append(item)
    return items
```

### Using Old Typing Syntax

**❌ Bad:** Pre-3.10 typing imports.

```python
from typing import List, Dict, Optional, Union

def process(items: List[str]) -> Optional[Dict[str, Union[int, str]]]:
    pass
```

**✅ Good:** Modern built-in syntax (Python 3.10+).

```python
def process(items: list[str]) -> dict[str, int | str] | None:
    pass
```

### Not Using Frozen Dataclasses

**❌ Bad:** Mutable dataclasses that can be accidentally modified.

```python
@dataclass
class User:
    id: str
    name: str

user = User(id="123", name="Alice")
user.name = "Bob"  # Accidental mutation
```

**✅ Good:** Frozen dataclasses prevent mutations.

```python
@dataclass(frozen=True)
class User:
    id: str
    name: str

user = User(id="123", name="Alice")
# user.name = "Bob"  # FrozenInstanceError!

# Create new instance instead
updated_user = dataclass.replace(user, name="Bob")
```

### String Formatting in Logs

**❌ Bad:** String formatting before logging.

```python
logger.info(f"User {user_id} created order {order_id}")
```

**✅ Good:** Structured logging with extra fields.

```python
logger.info("User created order", extra={
    "user_id": user_id,
    "order_id": order_id
})
```

### Not Using Context Managers

**❌ Bad:** Manual resource cleanup.

```python
f = open("file.txt")
data = f.read()
f.close()  # What if error occurs?
```

**✅ Good:** Context manager ensures cleanup.

```python
with open("file.txt") as f:
    data = f.read()
# File automatically closed
```

### Reinventing the Wheel

**❌ Bad:** Implementing standard library functionality.

```python
def my_custom_http_client():
    # Custom implementation of HTTP client
    pass

def my_json_parser(text: str):
    # Custom JSON parsing
    pass
```

**✅ Good:** Use standard library or well-maintained packages.

```python
import httpx
import json

async def fetch_data():
    async with httpx.AsyncClient() as client:
        response = await client.get(url)
        return json.loads(response.text)
```

### Complex Comprehensions

**❌ Bad:** Unreadable nested comprehensions.

```python
result = {
    k: [x for x in v if x > 0]
    for k, v in data.items()
    if k.startswith("prefix_") and len(v) > 0
}
```

**✅ Good:** Break into readable steps.

```python
def filter_positive(values: list[int]) -> list[int]:
    return [x for x in values if x > 0]

def should_include_key(key: str, values: list[int]) -> bool:
    return key.startswith("prefix_") and len(values) > 0

result = {
    key: filter_positive(values)
    for key, values in data.items()
    if should_include_key(key, values)
}
```
