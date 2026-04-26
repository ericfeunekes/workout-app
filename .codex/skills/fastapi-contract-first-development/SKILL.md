---
name: fastapi-contract-first-development
description: Contract-first FastAPI backend development that seamlessly integrates
---
# FastAPI Development

Build production-ready FastAPI backends that plug seamlessly into contract-driven frontend applications.

## Core Philosophy

**Contract-first development:** The OpenAPI specification is the source of truth. Backend and frontend teams work from the same contract, eliminating integration surprises.

**Service before connection:** Business logic lives in service classes that can be instantiated and tested independently. Database connections, authentication tokens, and external APIs are injected through FastAPI's dependency system.

**Clear separation of concerns:**
- Routes handle HTTP concerns (parsing, validation, response formatting)
- Services contain business logic
- Repositories abstract data access
- Dependencies manage cross-cutting concerns (auth, caching, logging)

## Quick Start

For a new FastAPI project:

```bash
uv run python scripts/setup_project.py my-api --with-auth --with-cache --contract contracts/api.yaml
```

This creates a complete project structure with:
- Contract-driven Pydantic models
- Service/repository layers
- JWT authentication via DI
- Redis caching setup
- Comprehensive tests

## Architecture Overview

```
project/
├── contracts/
│   └── openapi.yaml           # Source of truth
├── app/
│   ├── main.py               # FastAPI app
│   ├── models/               # Pydantic models (generated from contract)
│   ├── services/             # Business logic
│   ├── repositories/         # Data access
│   ├── dependencies/         # DI providers
│   └── routes/               # HTTP handlers
├── tests/
│   ├── contract/             # Contract validation tests
│   ├── unit/                 # Service/repository tests
│   └── integration/          # Full API tests
└── scripts/
    ├── generate_models.py    # Contract → Pydantic
    └── validate_contract.py  # Implementation → Contract
```

## Contract-Driven Development

**Start with the contract** - Define your API in OpenAPI before writing code:

```yaml
# contracts/openapi.yaml
paths:
  /articles/{article_id}:
    get:
      summary: Get article by ID
      parameters:
        - name: article_id
          in: path
          required: true
          schema:
            type: integer
      responses:
        '200':
          description: Article found
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Article'
```

**Generate models** from contract:

```bash
uv run python scripts/generate_models.py contracts/openapi.yaml app/models/
```

**Validate implementation** matches contract:

```bash
uv run python scripts/validate_contract.py
```

This runs contract tests ensuring your implementation matches the OpenAPI spec.

## Service Layer Pattern

Services encapsulate business logic and are injected into routes. They don't know about HTTP - they work with domain models.

```python
# app/services/article_service.py
from collections.abc import Callable

class ArticleService:
    def __init__(self, repo: ArticleRepository, cache: CacheService):
        self.repo = repo
        self.cache = cache

    async def get_article(self, article_id: int) -> Article:
        # Pure business logic - no HTTP concerns
        cached = await self.cache.get(f"article:{article_id}")
        if cached:
            return Article.model_validate_json(cached)

        article = await self.repo.get_by_id(article_id)
        await self.cache.set(f"article:{article_id}", article.model_dump_json())
        return article
```

Service functions are pure - same inputs always produce same outputs (modulo external state changes).

For detailed patterns, see `reference:fastapi-contract-first-development/service-layer.md`.

**Model boundary guidance:** Keep Pydantic models at the HTTP edge for parsing/validation, then convert into immutable dataclasses or plain domain objects before passing data into services. This keeps alignment with the repository’s functional-first guidelines while still leveraging FastAPI’s validation strengths.

## Repository Pattern

Repositories abstract data access. Services depend on repository interfaces, not concrete implementations.

```python
# app/repositories/article_repository.py
from abc import ABC, abstractmethod

class ArticleRepositoryInterface(ABC):
    @abstractmethod
    async def get_by_id(self, id: int) -> Article | None:
        pass

class ArticleRepository(ArticleRepositoryInterface):
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_by_id(self, id: int) -> Article | None:
        result = await self.db.execute(
            select(ArticleModel).where(ArticleModel.id == id)
        )
        return result.scalar_one_or_none()
```

For implementation details and testing patterns, see `reference:fastapi-contract-first-development/repository-pattern.md`.

## Dependency Injection

FastAPI's DI system wires everything together. Dependencies are declared as function parameters and FastAPI provides them.

**Core pattern:** Dependencies provide services, services use repositories, repositories use database sessions.

```python
# app/dependencies/database.py
async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session_maker() as session:
        yield session

# app/dependencies/repositories.py
def get_article_repo(db: Annotated[AsyncSession, Depends(get_db)]) -> ArticleRepository:
    return ArticleRepository(db)

# app/dependencies/services.py
def get_article_service(
    repo: Annotated[ArticleRepository, Depends(get_article_repo)],
    cache: Annotated[CacheService, Depends(get_cache_service)]
) -> ArticleService:
    return ArticleService(repo, cache)

# app/routes/articles.py
@router.get("/articles/{article_id}")
async def get_article(
    article_id: int,
    service: Annotated[ArticleService, Depends(get_article_service)]
) -> Article:
    return await service.get_article(article_id)
```

Routes only handle HTTP - no business logic, no database access, no authentication checking (that's in dependencies).

## Authentication via DI

JWT tokens are validated in a dependency. The dependency extracts user info and provides it to routes. Routes never touch tokens directly.

```python
# app/dependencies/auth.py
async def get_current_user(
    token: Annotated[str, Depends(oauth2_scheme)],
    user_service: Annotated[UserService, Depends(get_user_service)]
) -> User:
    payload = decode_jwt(token)
    user = await user_service.get_by_id(payload["sub"])
    if not user:
        raise HTTPException(status_code=401)
    return user

# app/routes/articles.py
@router.post("/articles")
async def create_article(
    article: ArticleCreate,
    user: Annotated[User, Depends(get_current_user)],  # Injected!
    service: Annotated[ArticleService, Depends(get_article_service)]
) -> Article:
    return await service.create_article(article, user_id=user.id)
```

The route function receives an authenticated User object. It never sees the token or calls any auth code. All authentication logic is encapsulated in the `get_current_user` dependency.

For complete JWT setup, token refresh, and role-based auth, see `reference:fastapi-contract-first-development/authentication.md`.

## Configuration Management

Manage configs across environments (local, dev, stage, prod) with file-based defaults that can be overridden by environment variables.

**Core pattern:** Config files define sensible defaults. Environment variables override for secrets and deployment-specific values.

```python
# app/config.py
from pydantic_settings import BaseSettings, SettingsConfigDict
from functools import lru_cache

class Settings(BaseSettings):
    # Defaults in code
    database_url: str = "postgresql://localhost/db"
    database_pool_size: int = 20
    redis_url: str = "redis://localhost:6379/0"

    # Secrets (override via env var)
    jwt_secret_key: str

    model_config = SettingsConfigDict(
        env_file=f".env.{os.getenv('ENV', 'local')}",
    )

@lru_cache
def get_settings() -> Settings:
    return Settings()

# Inject via DI
@app.get("/info")
def get_info(settings: Annotated[Settings, Depends(get_settings)]):
    return {"app_name": settings.app_name}
```

**Environment-specific configs:** Create `config/local.py`, `config/dev.py`, `config/staging.py`, `config/prod.py` with different defaults. Load based on `ENV` environment variable.

**Override priority:** Environment variables > .env file > config class defaults.

**Service limitations:** Some platforms limit env vars. Use config files for bulk settings, env vars for secrets only.

For complete patterns including nested configs, validation, secrets management, and testing, see `reference:fastapi-contract-first-development/config-management.md`. Run `uv run python scripts/config_example.py` for a working implementation.

## Server-Sent Events & Streaming

Stream responses for real-time updates, LLM token streaming, and long-running operations.

**Use SSE for:**
- LLM responses (token-by-token display)
- Progress updates for long operations
- Real-time data feeds
- Proxying streaming external APIs

```python
from sse_starlette.sse import EventSourceResponse

async def stream_llm_response(prompt: str, request: Request):
    async for chunk in llm_client.stream(prompt):
        # Check client disconnection
        if await request.is_disconnected():
            break

        yield {
            "event": "token",
            "data": chunk.content,
        }

    yield {"event": "done", "data": "complete"}

@router.post("/chat/stream")
async def chat_stream(prompt: str, request: Request):
    return EventSourceResponse(stream_llm_response(prompt, request))
```

**Key patterns:**
- Always check `request.is_disconnected()` to stop generation when client leaves
- Send keep-alive pings every 15-30s for proxies
- Handle errors gracefully with error events
- Configure reverse proxy to disable buffering
- Limit concurrent streams to prevent resource exhaustion

For LLM streaming, proxying external SSE APIs, keep-alive patterns, deployment config, and testing, see `reference:fastapi-contract-first-development/sse-streaming.md`.

## Connection Management

Manage database pools, external API clients, and singleton resources efficiently.

**Core principle:** One pool per worker, shared across requests. Create pools at startup, inject via dependencies.

**Database connection pooling:**

```python
# app/database.py
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker

# Created once per worker at module level
engine = create_async_engine(
    database_url,
    pool_size=20,              # Keep 20 connections open
    max_overflow=10,           # Up to 30 total when busy
    pool_timeout=30,           # Wait 30s for connection
    pool_pre_ping=True,        # Verify connections before use
)

async_session_maker = async_sessionmaker(engine, expire_on_commit=False)

async def get_db():
    async with async_session_maker() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
```

**External API client pooling:**

```python
# app/dependencies/http_client.py
from contextlib import asynccontextmanager

http_client: httpx.AsyncClient | None = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global http_client
    http_client = httpx.AsyncClient(
        timeout=30.0,
        limits=httpx.Limits(
            max_keepalive_connections=20,
            max_connections=100,
        ),
    )
    yield
    await http_client.aclose()

def get_http_client() -> httpx.AsyncClient:
    return http_client

# Usage
@app.get("/external-data")
async def fetch(client: Annotated[httpx.AsyncClient, Depends(get_http_client)]):
    return await client.get("https://api.example.com/data")
```

**When to use singletons:** Connection pools, HTTP clients, Redis clients, config objects. **Never** use for database sessions, request context, or per-request state.

For pool sizing formulas, Redis pooling, retry logic, health checks, read replicas, and production patterns, see `reference:fastapi-contract-first-development/connections.md`.

## Caching with Redis

Cache service is injected via DI. Services use it to cache expensive operations.

**Cache patterns supported:**
- Cache-aside (lazy loading)
- Write-through (update cache on write)
- Cache invalidation by pattern
- TTL-based expiration

```python
# app/dependencies/cache.py
def get_cache_service(redis_client: Annotated[Redis, Depends(get_redis)]) -> CacheService:
    return CacheService(redis_client)

# app/services/article_service.py
class ArticleService:
    async def get_trending_articles(self) -> list[Article]:
        cache_key = "trending:articles"

        # Try cache first
        cached = await self.cache.get(cache_key)
        if cached:
            return [Article.model_validate_json(a) for a in json.loads(cached)]

        # Compute if not cached
        articles = await self.repo.get_trending()

        # Cache for 5 minutes
        await self.cache.set(cache_key, json.dumps([a.model_dump_json() for a in articles]), ex=300)

        return articles
```

For advanced caching strategies, cache warming, and invalidation patterns, see `reference:fastapi-contract-first-development/caching.md`.

## Testing Strategy

Test at three levels: unit (services/repositories in milliseconds), integration (API + DB in seconds), and end-to-end (deployed API for smoke tests).

**Speed is critical:** Fast tests run often. Unit tests in milliseconds, integration tests under 3 seconds, full suite under 2 minutes.

```python
# tests/unit/test_article_service.py
async def test_get_article_uses_cache():
    mock_cache = Mock(CacheService)
    mock_cache.get.return_value = '{"id": 1, "title": "Test"}'

    service = ArticleService(repo=Mock(), cache=mock_cache)
    article = await service.get_article(1)

    assert article.id == 1
    mock_cache.get.assert_called_once_with("article:1")

# tests/integration/test_articles_api.py
@pytest.mark.asyncio
async def test_create_and_retrieve(async_client, test_db):
    response = await async_client.post(
        "/articles",
        json={"title": "Test", "content": "Content"}
    )
    assert response.status_code == 201

    article_id = response.json()["id"]
    response = await async_client.get(f"/articles/{article_id}")
    assert response.json()["title"] == "Test"

# tests/contract/test_openapi_compliance.py
def test_get_article_matches_contract():
    response = client.get("/articles/1")
    assert_matches_schema(response.json(), "Article", openapi_spec)
```

**Key tactics for fast tests:**
- Use in-memory SQLite for integration tests (10-50x faster than Postgres)
- Scope fixtures appropriately (`scope="module"` for TestClient)
- Run tests in parallel (`pytest -n auto`)
- Transaction rollback per test (don't recreate DB)
- Use factories for test data

**Testing async endpoints:**

```python
from httpx import AsyncClient

@pytest.fixture
async def async_client():
    async with AsyncClient(app=app, base_url="http://test") as ac:
        yield ac

@pytest.mark.asyncio
async def test_endpoint(async_client):
    response = await async_client.get("/articles/1")
    assert response.status_code == 200
```

**Dependency overrides for testing:**

```python
@pytest.fixture
def mock_auth(app):
    def override_get_current_user():
        return User(id=1, email="test@test.com")

    app.dependency_overrides[get_current_user] = override_get_current_user
    yield
    app.dependency_overrides.clear()
```

Run tests:

```bash
uv run pytest tests/unit         # Fast unit tests
uv run pytest tests/integration  # Integration tests with test DB
uv run pytest tests/contract     # OpenAPI validation
uv run pytest -m e2e             # Smoke tests on deployed API
```

For FastAPI-specific patterns including streaming tests, external API mocking, WebSocket testing, performance benchmarking, CI/CD setup, and common pitfalls, see `reference:fastapi-contract-first-development/testing-fastapi.md`. The original `reference:fastapi-contract-first-development/testing.md` covers core patterns.

## Frontend Integration

The OpenAPI contract ensures frontend and backend stay in sync:

**Backend team:**
1. Update `contracts/openapi.yaml`
2. Run `uv run python scripts/generate_models.py` to regenerate Pydantic models
3. Implement business logic in services
4. Run `uv run python scripts/validate_contract.py` to ensure compliance

**Frontend team:**
1. Uses same `contracts/openapi.yaml`
2. Generates TypeScript types from contract
3. Implements UI against contract
4. Mocks backend using contract examples

**Both teams work from the same source of truth.** If the backend violates the contract, tests fail before merge. If the frontend assumes fields not in the contract, TypeScript compilation fails.

## Production Deployment

For production setup, see `reference:fastapi-contract-first-development/deployment.md` which covers:
- Environment configuration and secrets
- Database migrations with Alembic
- Docker containerization
- Kubernetes manifests
- Health checks and monitoring
- Horizontal scaling
- CI/CD pipelines

## Resources

**Scripts:**
- `script:fastapi-contract-first-development/setup_project.py` - Initialize new FastAPI project (`uv run python scripts/setup_project.py …`)
- `script:fastapi-contract-first-development/generate_models.py` - Generate Pydantic models from OpenAPI (`uv run python scripts/generate_models.py …`)
- `script:fastapi-contract-first-development/validate_contract.py` - Validate implementation matches contract (`uv run python scripts/validate_contract.py`)
- `script:fastapi-contract-first-development/test_runner.py` - Run test suites (`uv run python scripts/test_runner.py`)
- `script:fastapi-contract-first-development/config_example.py` - Example configuration management setup

**Core References:**
- `reference:fastapi-contract-first-development/service-layer.md` - Service pattern implementation guide
- `reference:fastapi-contract-first-development/repository-pattern.md` - Repository pattern with interfaces
- `reference:fastapi-contract-first-development/authentication.md` - JWT auth setup and patterns
- `reference:fastapi-contract-first-development/caching.md` - Redis caching strategies
- `reference:fastapi-contract-first-development/testing.md` - Core testing patterns
- `reference:fastapi-contract-first-development/deployment.md` - Production deployment checklist

**Advanced References:**
- `reference:fastapi-contract-first-development/config-management.md` - Environment-based configuration with file defaults and env var overrides
- `reference:fastapi-contract-first-development/testing-fastapi.md` - FastAPI-specific testing patterns: speed optimization, async testing, streaming, mocking, CI/CD
- `reference:fastapi-contract-first-development/sse-streaming.md` - Server-Sent Events for LLM streaming, keep-alive, proxying external streams
- `reference:fastapi-contract-first-development/connections.md` - Database connection pooling, external API clients, singletons, resource management

**Assets:**
- `asset:fastapi-contract-first-development/openapi-template.yaml` - Starter OpenAPI template
- `asset:fastapi-contract-first-development/project-structure/` - Complete example project

## When to Read References

**Starting a new project?**
- Start with `service-layer.md` and `repository-pattern.md`
- Set up config: `config-management.md` and `script:fastapi-contract-first-development/config_example.py`
- Set up connections: `connections.md`

**Implementing auth?**
- Read `authentication.md`

**Need streaming?**
- Read `sse-streaming.md` for LLM responses or real-time updates

**Performance issues?**
- Read `caching.md` for caching strategies
- Read `connections.md` for connection pool tuning

**Writing tests?**
- Read `testing.md` for core patterns
- Read `testing-fastapi.md` for speed optimization and FastAPI-specific patterns

**Deploying?**
- Read `deployment.md`
- Review `config-management.md` for env-specific settings
- Check `connections.md` for pool sizing in production
