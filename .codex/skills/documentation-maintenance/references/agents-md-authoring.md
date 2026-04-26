# AGENTS.md Authoring Guide

How to write effective AGENTS.md files that guide AI agents in your codebase.

## Purpose

AGENTS.md (symlinked to CLAUDE.md) tells agents how to work in a directory. It's the most impactful documentation for agent-assisted development.

**AGENTS.md answers**: "What conventions, patterns, and anti-patterns should I follow here?"

**It does NOT cover**: What the code does (that's docs/), how to get started (that's README).

---

## Structure

### Root AGENTS.md

Located at repository root. Covers global conventions.

**Target length**: 100-200 lines with examples.

**Sections to include**:

1. Core coding values (with examples)
2. Global tooling preferences
3. Testing philosophy (with examples)
4. Error handling patterns (with examples)
5. Anti-patterns to avoid (with examples)

### Directory AGENTS.md

Located in subdirectories with specific conventions.

**Target length**: 30-100 lines.

**Sections to include**:

1. How this directory differs from root
2. Patterns specific to this area (with examples)
3. Common tasks (with examples)
4. Anti-patterns specific to this context

---

## Best Practices

From the prompting skill:

### 1. Examples for Every Key Behavior

Rules without examples leave room for interpretation. Use 2-4 diverse examples per key behavior.

<examples_required>
**Bad** (rule only):
```markdown
Use dependency injection for all clients.
```

**Good** (rule + example):
```markdown
Use dependency injection for all clients.

```python
# Good - injected
def fetch_user(client: AuthClient, user_id: str) -> User:
    return client.get_user(user_id)

# Bad - instantiated
def fetch_user(user_id: str) -> User:
    client = AuthClient(Settings())  # Don't do this
    return client.get_user(user_id)
```
```
</examples_required>

### 2. Good/Bad Contrast Examples

Side-by-side comparison eliminates ambiguity.

<good_bad_contrast>
```markdown
## Error Handling

<error_patterns>
Good:
```python
try:
    result = await client.fetch(id)
except ClientError as e:
    raise AppError(f"Failed to fetch {id}: {e}") from e
```

Bad:
```python
try:
    result = await client.fetch(id)
except Exception:  # Too broad
    return None  # Silent failure
```
</error_patterns>
```
</good_bad_contrast>

### 3. Quantitative Constraints

"3-6 sentences" beats "be concise". Measurable constraints reduce ambiguity.

<quantitative>
**Bad**:
```markdown
Keep functions short and focused.
```

**Good**:
```markdown
Functions should be ≤30 lines. If longer, split into smaller functions.
```
</quantitative>

### 4. XML-Like Section Tags

Group related rules with tags. Helps agents find relevant guidance.

<xml_sections>
```markdown
<testing_conventions>
- Unit tests in `tests/unit/`, no I/O
- Integration tests in `tests/integration/`, use respx
- Fixtures in `conftest.py`, never in test files
</testing_conventions>

<error_handling>
- Wrap external errors in AppError
- Log at handler level, not in business logic
- Never swallow exceptions silently
</error_handling>
```
</xml_sections>

### 5. Omit What Models Know

Don't explain git, markdown, or programming basics. Focus on YOUR conventions.

<omit_obvious>
**Bad** (explains obvious things):
```markdown
## Git Usage

Git is a version control system. Use `git add` to stage files,
`git commit` to save changes, and `git push` to upload.
```

**Good** (explains YOUR conventions):
```markdown
## Git Conventions

- Branch names: `<type>/<slug>` (e.g., `feat/add-auth`)
- Commit messages: imperative, ≤72 chars, reference issue
- Never force push to main
```
</omit_obvious>

### 6. Imperative Tone

"Use X" not "You should use X". Direct, commanding language.

<imperative>
**Bad**:
```markdown
You should consider using dependency injection when creating clients.
It would be a good idea to avoid instantiating Settings directly.
```

**Good**:
```markdown
Use dependency injection for all clients. Never instantiate Settings directly.
```
</imperative>

---

## Complete Example: Root AGENTS.md

```markdown
# Project Conventions

## Core Values

When I say "core values":

- **Simplicity** - Pruning > adding layers. Simplify before creating.
- **Maintainability** - Respect boundaries. Intuitive to future readers.
- **Efficiency** - No unnecessary work at runtime or dev time.
- **Safety** - No race conditions, lock contention, or error handling gaps.

## Tooling

- Python: `uv` for all commands
- Linting: `ruff`
- Type checking: `ty`
- Postgres: `asyncpg`

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

- Unit tests: Pure functions, no I/O, no mocking
- Integration: Use `respx` for HTTP, `vcr` for recordings
- Smoke: Hit real endpoints, mark with `@pytest.mark.smoke`

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
```

---

## Complete Example: Directory AGENTS.md

```markdown
# testing/ Conventions

Inherits from root AGENTS.md. Testing-specific patterns.

## Directory Structure

| Directory | Purpose | I/O | Markers |
|-----------|---------|-----|---------|
| `unit/` | Pure functions | None | — |
| `integration/` | Service interactions | Fakes | — |
| `smoke/` | Real endpoints | Live | `@pytest.mark.smoke` |

## Running Tests

```bash
uv run pytest testing/unit           # Fast, no I/O
uv run pytest testing/integration    # Needs Docker
uv run pytest -m smoke               # Hits real endpoints
```

## Fixtures

<test_fixtures>
All fixtures in `conftest.py` at appropriate level.

- `testing/conftest.py` — Shared across all test types
- `testing/unit/conftest.py` — Unit-specific
- `testing/integration/conftest.py` — Integration-specific

Never define fixtures in test files.
</test_fixtures>

## Integration Test Patterns

<respx_patterns>
Use respx for HTTP mocking. Match real API structure.

Good:
```python
@respx.mock
async def test_fetch_user(auth_client: AuthClient):
    respx.get("/users/123").respond(json={"id": "123", "name": "Test"})
    user = await auth_client.get_user("123")
    assert user.name == "Test"
```

Bad:
```python
async def test_fetch_user():
    with patch("httpx.AsyncClient.get"):  # Don't use patch for HTTP
        ...
```
</respx_patterns>

## Common Mistakes

- Adding `@pytest.mark.skipif` for missing credentials → Use fixtures with fakes
- Mocking internal functions → Inject dependencies instead
- Tests depending on execution order → Each test must be independent
```

---

## Checklist

Before finalizing AGENTS.md:

- [ ] Every key behavior has 2-4 examples
- [ ] Good/bad contrasts for non-obvious patterns
- [ ] Quantitative constraints where applicable
- [ ] XML-like tags group related rules
- [ ] No explanation of obvious things (git, Python basics)
- [ ] Imperative tone throughout
- [ ] Root: 100-200 lines, Directory: 30-100 lines
