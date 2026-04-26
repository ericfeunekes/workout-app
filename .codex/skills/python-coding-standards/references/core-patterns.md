# Core Patterns

Foundational Python patterns for functional programming, immutable data, and type safety.

## Table of Contents

1. [Functional Programming Approach](#functional-programming-approach)
2. [Data Management with Frozen Dataclasses](#data-management-with-frozen-dataclasses)
3. [Type Safety](#type-safety)
4. [Function Organization](#function-organization)
5. [Error Handling in Pure Functions](#error-handling-in-pure-functions)

## Functional Programming Approach

### Pure Functions as Default

Pure functions are deterministic: same inputs always produce same outputs. They don't modify external state or depend on hidden state.

```python
# ✅ Good - pure function
def calculate_order_total(items: list[OrderItem]) -> Decimal:
    return sum(item.price * item.quantity for item in items)

# ❌ Bad - depends on external state
total = Decimal("0")
def calculate_order_total(items: list[OrderItem]) -> None:
    global total
    total = sum(item.price * item.quantity for item in items)
```

### Isolating Side Effects

When side effects are necessary, isolate them into dedicated functions. One side effect per function.

```python
from collections.abc import Callable

# Pure function - no side effects
def build_email_message(user: User, template: str) -> EmailMessage:
    return EmailMessage(
        to=user.email,
        subject="Welcome!",
        body=template.format(name=user.name)
    )

# Side effect isolated - sends email
async def send_email(message: EmailMessage) -> None:
    async with smtp_client() as client:
        await client.send(message)

# Orchestration
async def welcome_new_user(user: User, template: str) -> None:
    message = build_email_message(user, template)  # Pure
    await send_email(message)  # Side effect
```

### Extracting Complex Logic

Break down complex operations into smaller pure functions.

```python
@dataclass(frozen=True)
class Order:
    items: frozenset[OrderItem]
    customer_id: str
    discount_code: str | None = None

# Main function orchestrates
def process_order(order: Order) -> ProcessedOrder:
    validated_items = validate_items(order.items)
    subtotal = calculate_subtotal(validated_items)
    discount = apply_discount(subtotal, order.discount_code)
    tax = calculate_tax(subtotal - discount)
    total = subtotal - discount + tax

    return ProcessedOrder(
        items=validated_items,
        subtotal=subtotal,
        discount=discount,
        tax=tax,
        total=total
    )

# Each sub-function is pure and testable
def validate_items(items: frozenset[OrderItem]) -> frozenset[OrderItem]:
    """Validate inventory availability and pricing."""
    return frozenset(item for item in items if item.price > 0 and item.quantity > 0)

def calculate_subtotal(items: frozenset[OrderItem]) -> Decimal:
    """Calculate order subtotal before discounts."""
    return sum(item.price * item.quantity for item in items)

def apply_discount(subtotal: Decimal, code: str | None) -> Decimal:
    """Apply discount code if valid."""
    if not code:
        return Decimal("0")

    rate = DISCOUNT_RATES.get(code, Decimal("0"))
    return subtotal * rate

def calculate_tax(amount: Decimal) -> Decimal:
    """Calculate tax on taxable amount."""
    return amount * TAX_RATE
```

## Data Management with Frozen Dataclasses

### Immutable by Default

Use `@dataclass(frozen=True)` to prevent accidental mutations.

```python
from dataclasses import dataclass
from datetime import datetime

@dataclass(frozen=True)
class UserSession:
    user_id: str
    created_at: datetime
    expires_at: datetime
    permissions: frozenset[str] = frozenset()

# ✅ Good - create new instance for changes
def extend_session(session: UserSession, hours: int) -> UserSession:
    new_expiry = session.expires_at + timedelta(hours=hours)
    return dataclass.replace(session, expires_at=new_expiry)

# ❌ Bad - would raise FrozenInstanceError
def extend_session_bad(session: UserSession, hours: int) -> None:
    session.expires_at += timedelta(hours=hours)  # Error!
```

### Parameter Objects

Use dataclasses as parameter objects to simplify function signatures and make them easy to evolve.

```python
@dataclass(frozen=True)
class SearchFilters:
    query: str
    category: str | None = None
    min_price: Decimal | None = None
    max_price: Decimal | None = None
    in_stock_only: bool = True
    sort_by: str = "relevance"

# ✅ Good - single parameter object
def search_products(filters: SearchFilters) -> list[Product]:
    results = filter_by_query(filters.query)

    if filters.category:
        results = filter_by_category(results, filters.category)

    if filters.min_price:
        results = filter_by_min_price(results, filters.min_price)

    if filters.max_price:
        results = filter_by_max_price(results, filters.max_price)

    if filters.in_stock_only:
        results = filter_in_stock(results)

    return sort_results(results, filters.sort_by)

# ❌ Bad - many individual parameters
def search_products_bad(
    query: str,
    category: str | None = None,
    min_price: Decimal | None = None,
    max_price: Decimal | None = None,
    in_stock_only: bool = True,
    sort_by: str = "relevance"
) -> list[Product]:
    pass  # Same logic but harder to call and modify
```

When adding parameters, just update the dataclass - no function signatures change.

### Nested Immutable Structures

For collections, use frozen sets and tuples.

```python
from typing import FrozenSet

@dataclass(frozen=True)
class Department:
    name: str
    manager_id: str
    employee_ids: frozenset[str] = frozenset()
    budgets: tuple[Decimal, ...] = ()

# ✅ Good - return new instance with modified collection
def add_employee(dept: Department, employee_id: str) -> Department:
    new_employee_ids = dept.employee_ids | {employee_id}
    return dataclass.replace(dept, employee_ids=new_employee_ids)

# ✅ Good - frozen collections prevent mutation
dept = Department(name="Engineering", manager_id="123")
# dept.employee_ids.add("456")  # AttributeError - frozenset has no add()
```

## Type Safety

### Modern Type Hints

Use Python 3.10+ union syntax and built-in generics.

```python
from collections.abc import Callable, Sequence
from datetime import datetime

# ✅ Good - modern syntax
def process_items(
    items: list[str],
    validator: Callable[[str], bool],
    max_count: int | None = None
) -> tuple[list[str], list[str]]:
    """Process items, returning (valid, invalid) tuple."""
    valid: list[str] = []
    invalid: list[str] = []

    for item in items[:max_count]:
        if validator(item):
            valid.append(item)
        else:
            invalid.append(item)

    return valid, invalid

# ❌ Bad - old typing syntax
from typing import List, Optional, Tuple, Callable

def process_items_old(
    items: List[str],
    validator: Callable[[str], bool],
    max_count: Optional[int] = None
) -> Tuple[List[str], List[str]]:
    pass
```

### Protocol for Structural Typing

Use `Protocol` for duck typing and dependency injection.

```python
from typing import Protocol

class Serializable(Protocol):
    """Any object with to_json method."""
    def to_json(self) -> str: ...

class Cacheable(Protocol):
    """Any object with cache key."""
    @property
    def cache_key(self) -> str: ...

def cache_object(obj: Cacheable, ttl: int) -> None:
    """Cache any object with cache_key property."""
    cache.set(obj.cache_key, obj, ttl=ttl)

# Works with any class implementing the protocol
@dataclass(frozen=True)
class User:
    id: str
    name: str

    @property
    def cache_key(self) -> str:
        return f"user:{self.id}"

user = User(id="123", name="Alice")
cache_object(user, ttl=3600)  # Type checks!
```

### Strict Type Checking

Enable strict mypy checking to catch issues early.

```python
# mypy.ini or pyproject.toml
[tool.mypy]
python_version = "3.11"
strict = true
warn_return_any = true
warn_unused_configs = true
disallow_untyped_defs = true
```

## Function Organization

### Top-Down Decomposition

Start with the high-level function, break into meaningful steps, implement recursively.

```python
# Level 0: Main entry point
def generate_monthly_report(month: int, year: int) -> Report:
    """Generate comprehensive monthly report."""
    data = fetch_monthly_data(month, year)
    processed = process_monthly_data(data)
    visualizations = create_visualizations(processed)
    return assemble_report(processed, visualizations)

# Level 1: Major steps
def fetch_monthly_data(month: int, year: int) -> RawData:
    """Fetch all required data for the month."""
    sales = fetch_sales_data(month, year)
    inventory = fetch_inventory_data(month, year)
    expenses = fetch_expense_data(month, year)
    return RawData(sales=sales, inventory=inventory, expenses=expenses)

def process_monthly_data(data: RawData) -> ProcessedData:
    """Transform raw data into analysis-ready format."""
    sales_metrics = calculate_sales_metrics(data.sales)
    inventory_metrics = calculate_inventory_metrics(data.inventory)
    expense_metrics = calculate_expense_metrics(data.expenses)
    return ProcessedData(
        sales=sales_metrics,
        inventory=inventory_metrics,
        expenses=expense_metrics
    )

# Level 2: Specific calculations
def calculate_sales_metrics(sales: list[Sale]) -> SalesMetrics:
    """Calculate key sales metrics."""
    total_revenue = sum_revenue(sales)
    avg_order_value = calculate_avg_order_value(sales)
    top_products = identify_top_products(sales, limit=10)
    return SalesMetrics(
        total_revenue=total_revenue,
        avg_order_value=avg_order_value,
        top_products=top_products
    )

# Level 3: Atomic operations
def sum_revenue(sales: list[Sale]) -> Decimal:
    """Sum total revenue from sales."""
    return sum(sale.amount for sale in sales)

def calculate_avg_order_value(sales: list[Sale]) -> Decimal:
    """Calculate average order value."""
    if not sales:
        return Decimal("0")
    return sum_revenue(sales) / len(sales)
```

### Module Organization

Group related dataclasses and functions together.

```python
# models/order.py - Data structures
@dataclass(frozen=True)
class OrderItem:
    product_id: str
    quantity: int
    price: Decimal

@dataclass(frozen=True)
class Order:
    id: str
    items: frozenset[OrderItem]
    customer_id: str

# services/order_processing.py - Business logic
def validate_order(order: Order) -> Order:
    """Validate order data."""
    pass

def calculate_order_total(order: Order) -> Decimal:
    """Calculate order total."""
    pass

def process_payment(order: Order, payment_method: str) -> PaymentResult:
    """Process payment for order."""
    pass
```

## Error Handling in Pure Functions

### Return Result Types

Use result types for expected errors rather than exceptions.

```python
from dataclasses import dataclass
from typing import Generic, TypeVar

T = TypeVar('T')
E = TypeVar('E')

@dataclass(frozen=True)
class Ok(Generic[T]):
    value: T

@dataclass(frozen=True)
class Err(Generic[E]):
    error: E

Result = Ok[T] | Err[E]

# ✅ Good - explicit error handling
def parse_user_age(age_str: str) -> Result[int, str]:
    """Parse age string, returning Ok(age) or Err(message)."""
    try:
        age = int(age_str)
        if age < 0:
            return Err("Age cannot be negative")
        if age > 150:
            return Err("Age seems unrealistic")
        return Ok(age)
    except ValueError:
        return Err(f"Invalid age format: {age_str}")

# Usage
match parse_user_age(input_str):
    case Ok(age):
        print(f"User is {age} years old")
    case Err(error):
        print(f"Error: {error}")
```

### Raise for Truly Exceptional Cases

Reserve exceptions for truly exceptional situations that callers can't reasonably handle.

```python
class ConfigurationError(Exception):
    """Raised when system configuration is invalid."""
    pass

def load_database_config() -> DatabaseConfig:
    """Load database configuration.

    Raises:
        ConfigurationError: If required config values are missing
    """
    host = os.getenv("DB_HOST")
    if not host:
        raise ConfigurationError("DB_HOST environment variable not set")

    port = os.getenv("DB_PORT")
    if not port:
        raise ConfigurationError("DB_PORT environment variable not set")

    return DatabaseConfig(host=host, port=int(port))
```
