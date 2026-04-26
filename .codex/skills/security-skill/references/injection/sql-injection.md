# SQL Injection Prevention

SQL injection occurs when user input is concatenated into SQL queries, allowing attackers to modify query logic or extract data.

## The Problem

```python
# VULNERABLE - string formatting
query = f"SELECT * FROM users WHERE id = {user_id}"
conn.execute(query)

# VULNERABLE - string concatenation
query = "SELECT * FROM users WHERE name = '" + name + "'"

# VULNERABLE - % formatting
cursor.execute("SELECT * FROM users WHERE id = %s" % user_id)
```

## Primary Defense: Parameterized Queries

The database treats parameters as data, never as SQL code.

### asyncpg (Postgres)

```python
# SAFE - positional parameters ($1, $2, etc.)
async def get_user(conn, user_id: int):
    return await conn.fetchrow(
        "SELECT * FROM users WHERE id = $1",
        user_id
    )

async def create_user(conn, name: str, email: str):
    return await conn.execute(
        "INSERT INTO users (name, email) VALUES ($1, $2)",
        name, email
    )

# SAFE - fetch with multiple conditions
async def search_users(conn, status: str, min_age: int):
    return await conn.fetch(
        "SELECT * FROM users WHERE status = $1 AND age >= $2",
        status, min_age
    )
```

### SQLAlchemy ORM

```python
from sqlalchemy import select
from sqlalchemy.orm import Session

# SAFE - ORM query methods handle parameterization
def get_user_by_email(session: Session, email: str) -> User | None:
    return session.execute(
        select(User).where(User.email == email)
    ).scalar_one_or_none()

# SAFE - filter_by with keyword arguments
def get_users_by_status(session: Session, status: str) -> list[User]:
    return session.query(User).filter_by(status=status).all()

# SAFE - filter with comparison
def get_active_users(session: Session, min_age: int) -> list[User]:
    return session.query(User).filter(
        User.is_active == True,
        User.age >= min_age
    ).all()
```

### SQLAlchemy Core with text()

```python
from sqlalchemy import text

# SAFE - bound parameters with :name syntax
result = conn.execute(
    text("SELECT * FROM users WHERE id = :user_id AND status = :status"),
    {"user_id": user_id, "status": status}
)

# SAFE - text() with bindparams
from sqlalchemy import bindparam
stmt = text("SELECT * FROM users WHERE id = :id").bindparams(
    bindparam("id", type_=Integer)
)
```

### psycopg2 / psycopg3

```python
# SAFE - tuple parameter (psycopg2)
cursor.execute(
    "SELECT * FROM users WHERE id = %s AND status = %s",
    (user_id, status)
)

# SAFE - dict parameter (psycopg2)
cursor.execute(
    "SELECT * FROM users WHERE id = %(id)s",
    {"id": user_id}
)

# SAFE - psycopg3 positional
cursor.execute(
    "SELECT * FROM users WHERE id = %s",
    [user_id]
)
```

## Dynamic Identifiers (Table/Column Names)

Parameterization only works for values, not identifiers. Use allowlists.

### Allowlist Approach

```python
ALLOWED_SORT_COLUMNS = {"name", "created_at", "email", "id"}
ALLOWED_SORT_ORDERS = {"ASC", "DESC"}

def get_sorted_users(
    session: Session,
    sort_by: str,
    order: str = "ASC"
) -> list[User]:
    # Validate against allowlist
    if sort_by not in ALLOWED_SORT_COLUMNS:
        raise ValueError(f"Invalid sort column: {sort_by}")
    if order.upper() not in ALLOWED_SORT_ORDERS:
        raise ValueError(f"Invalid sort order: {order}")

    # Safe to use validated values
    return session.execute(
        text(f"SELECT * FROM users ORDER BY {sort_by} {order}")
    ).fetchall()
```

### Using sql.Identifier (psycopg2)

```python
from psycopg2 import sql

# SAFE - sql.Identifier for identifiers
def get_from_table(cursor, table_name: str, record_id: int):
    # Validate table name first
    if table_name not in ALLOWED_TABLES:
        raise ValueError(f"Invalid table: {table_name}")

    query = sql.SQL("SELECT * FROM {} WHERE id = %s").format(
        sql.Identifier(table_name)
    )
    cursor.execute(query, (record_id,))
    return cursor.fetchone()
```

## IN Clauses

```python
# asyncpg - use ANY with array
user_ids = [1, 2, 3, 4, 5]
await conn.fetch(
    "SELECT * FROM users WHERE id = ANY($1::int[])",
    user_ids
)

# SQLAlchemy - use in_()
session.query(User).filter(User.id.in_(user_ids)).all()

# psycopg2 - tuple expansion
cursor.execute(
    "SELECT * FROM users WHERE id IN %s",
    (tuple(user_ids),)
)
```

## LIKE Queries

```python
# SAFE - parameterize the pattern
search_term = "john"

# asyncpg
await conn.fetch(
    "SELECT * FROM users WHERE name ILIKE $1",
    f"%{search_term}%"
)

# SQLAlchemy
session.query(User).filter(User.name.ilike(f"%{search_term}%")).all()

# Escape special characters if needed
import re
def escape_like(s: str) -> str:
    return re.sub(r"([%_\\])", r"\\\1", s)

safe_term = escape_like(user_input)
```

## Vulnerable Patterns to Detect

| Pattern | Risk Level | Example |
|---------|------------|---------|
| `f"SELECT...{var}"` | Critical | `f"SELECT * FROM users WHERE id = {id}"` |
| `"SELECT..." + var` | Critical | `"SELECT * FROM " + table` |
| `"...".format(var)` | Critical | `"WHERE id = {}".format(id)` |
| `"..." % var` | Critical | `"WHERE id = %s" % id` |
| `execute(string_var)` | High | Variable query without params |
| `text(f"...")` | Critical | `text(f"SELECT * FROM {table}")` |

## Semgrep Rules

```bash
# Check for SQL injection patterns
semgrep --config p/python.sqlalchemy.security
semgrep --config r/python.lang.security.audit.formatted-sql-query
```

## Defense in Depth

1. **Parameterized queries** — Primary defense
2. **Least privilege** — DB user has minimal permissions
3. **Input validation** — Validate types and formats before use
4. **Allowlists for identifiers** — Never interpolate user input as table/column names
5. **ORM usage** — Prefer ORM methods over raw SQL
6. **Prepared statements** — For frequently-run queries

## Testing

```python
# Test that injection is blocked
def test_sql_injection_blocked():
    malicious_input = "'; DROP TABLE users; --"

    # This should NOT execute the DROP
    result = get_user_by_name(session, malicious_input)

    # Table should still exist
    assert session.execute(text("SELECT 1 FROM users LIMIT 1"))
```

## References

- OWASP SQL Injection Prevention Cheat Sheet
- asyncpg documentation
- SQLAlchemy security patterns
