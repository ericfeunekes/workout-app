# Project Conventions

## Core Values

When I say "core values":

- **Simplicity** - Pruning > adding layers. Simplify before creating.
- **Maintainability** - Respect boundaries. Intuitive to future readers.
- **Efficiency** - No unnecessary work at runtime or dev time.
- **Safety** - No race conditions, lock contention, or error handling gaps.

## Tooling

<!-- List your project's tools -->
- Python: `uv` for all commands
- Linting: `ruff`
- Type checking: `ty`

## Code Patterns

<dependency_injection>
Inject clients, settings, config. Never instantiate in functions.

Good:
```python
async def fetch_user(client: AuthClient, user_id: str) -> User:
    return await client.get(user_id)
```

Bad:
```python
async def fetch_user(user_id: str) -> User:
    client = AuthClient(Settings())  # Don't instantiate
    return await client.get(user_id)
```
</dependency_injection>

<error_handling>
Wrap external errors in AppError. Log at handler level.

Good:
```python
try:
    result = await external_api.call()
except ExternalError as e:
    raise AppError(f"External call failed: {e}") from e
```

Bad:
```python
try:
    result = await external_api.call()
except Exception:
    pass  # Never swallow errors
```
</error_handling>

## Testing

<!-- Define your test structure -->
| Directory | Purpose | I/O | Markers |
|-----------|---------|-----|---------|
| `unit/` | Pure functions | None | — |
| `integration/` | Service interactions | Fakes | — |
| `smoke/` | Real endpoints | Live | `@pytest.mark.smoke` |

<fixture_patterns>
Fixtures in `conftest.py`. Never in test files.

Good:
```python
# conftest.py
@pytest.fixture
def auth_client(settings: Settings) -> AuthClient:
    return AuthClient(settings)
```

Bad:
```python
# test_auth.py
@pytest.fixture  # Don't put here
def auth_client():
    return AuthClient(Settings())
```
</fixture_patterns>

## Anti-Patterns

- Don't create test gating (`@pytest.mark.skipif(not HAS_KEY)`)
- Don't invent new env vars—use existing config
- Don't mock what you can inject
- Don't add legacy/fallback code unless explicitly requested
