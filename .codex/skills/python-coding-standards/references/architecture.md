# Architecture Patterns

Service layer, repository pattern, and dependency injection for building maintainable applications.

## Table of Contents

1. [Architectural Layers](#architectural-layers)
2. [Service Layer Pattern](#service-layer-pattern)
3. [Repository Pattern](#repository-pattern)
4. [Dependency Injection](#dependency-injection)
5. [Configuration Management](#configuration-management)

## Architectural Layers

Clear separation of concerns across architectural boundaries.

```
┌─────────────────────────┐
│   HTTP/CLI/UI Layer     │  ← Handles protocols, never contains business logic
├─────────────────────────┤
│    Service Layer        │  ← Business logic, orchestrates operations
├─────────────────────────┤
│   Repository Layer      │  ← Data access abstraction
├─────────────────────────┤
│  External Systems       │  ← Databases, APIs, file systems
└─────────────────────────┘
```

**Key Principles:**
- Each layer depends only on layers below it
- Business logic never imports HTTP frameworks
- Services work with domain models, not database models
- Repositories abstract data access completely

## Service Layer Pattern

Services encapsulate business logic and orchestrate operations. They don't know about HTTP, databases, or external systems - they work with injected dependencies.

### Basic Service Structure

```python
from typing import Protocol

# Repository interface (dependency)
class UserRepository(Protocol):
    async def get_by_id(self, user_id: str) -> User | None: ...
    async def get_by_email(self, email: str) -> User | None: ...
    async def create(self, user: User) -> User: ...

# Service with injected dependencies
class UserService:
    """User business logic - no HTTP, no database imports."""

    def __init__(
        self,
        repo: UserRepository,
        cache: CacheService,
        email_service: EmailService
    ):
        self.repo = repo
        self.cache = cache
        self.email_service = email_service

    async def get_user(self, user_id: str) -> User:
        """Get user with caching."""
        # Check cache
        if cached := await self.cache.get(f"user:{user_id}"):
            return User.model_validate_json(cached)

        # Fetch from repository
        user = await self.repo.get_by_id(user_id)
        if not user:
            raise UserNotFoundError(user_id)

        # Cache for next time
        await self.cache.set(f"user:{user_id}", user.model_dump_json(), ttl=3600)

        return user

    async def create_user(self, email: str, name: str) -> User:
        """Create new user with validation and welcome email."""
        # Business validation
        if await self.repo.get_by_email(email):
            raise UserAlreadyExistsError(email)

        # Create user
        user = User(id=generate_id(), email=email, name=name)
        created_user = await self.repo.create(user)

        # Send welcome email (side effect)
        await self.email_service.send_welcome_email(created_user)

        return created_user
```

### Custom Exceptions

Services raise domain exceptions, not HTTP exceptions.

```python
# Domain exceptions
class UserNotFoundError(Exception):
    def __init__(self, user_id: str):
        self.user_id = user_id
        super().__init__(f"User {user_id} not found")

class UserAlreadyExistsError(Exception):
    def __init__(self, email: str):
        self.email = email
        super().__init__(f"User with email {email} already exists")

# HTTP layer converts to HTTP responses
@router.post("/users")
async def create_user(
    data: CreateUserRequest,
    service: Annotated[UserService, Depends(get_user_service)]
):
    try:
        user = await service.create_user(data.email, data.name)
        return user
    except UserAlreadyExistsError as e:
        raise HTTPException(status_code=409, detail=str(e))
```

### Service Composition

Services can depend on other services.

```python
class OrderService:
    def __init__(
        self,
        order_repo: OrderRepository,
        user_service: UserService,  # Service dependency
        payment_service: PaymentService,  # Service dependency
        inventory_service: InventoryService  # Service dependency
    ):
        self.order_repo = order_repo
        self.user_service = user_service
        self.payment_service = payment_service
        self.inventory_service = inventory_service

    async def place_order(self, order_data: OrderData) -> Order:
        """Place order with full validation and processing."""
        # Validate user exists
        user = await self.user_service.get_user(order_data.user_id)

        # Check inventory
        available = await self.inventory_service.check_availability(order_data.items)
        if not available:
            raise InsufficientInventoryError(order_data.items)

        # Process payment
        payment = await self.payment_service.process_payment(
            user_id=user.id,
            amount=order_data.total
        )

        # Create order
        order = Order(
            id=generate_id(),
            user_id=user.id,
            items=order_data.items,
            payment_id=payment.id,
            status="confirmed"
        )

        return await self.order_repo.create(order)
```

## Repository Pattern

Repositories provide an abstraction over data access. Services depend on repository interfaces, not implementations.

### Repository Interface

```python
from typing import Protocol

class ArticleRepository(Protocol):
    """Interface for article data access."""

    async def get_by_id(self, article_id: int) -> Article | None:
        """Get article by ID."""
        ...

    async def list_by_author(self, author_id: str, limit: int) -> list[Article]:
        """List articles by author."""
        ...

    async def create(self, article: Article) -> Article:
        """Create new article."""
        ...

    async def update(self, article: Article) -> Article:
        """Update existing article."""
        ...

    async def delete(self, article_id: int) -> None:
        """Delete article."""
        ...
```

### Repository Implementation

```python
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

class SQLAlchemyArticleRepository:
    """SQLAlchemy implementation of ArticleRepository."""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_by_id(self, article_id: int) -> Article | None:
        """Get article by ID."""
        result = await self.db.execute(
            select(ArticleModel).where(ArticleModel.id == article_id)
        )
        model = result.scalar_one_or_none()

        if not model:
            return None

        return self._to_domain(model)

    async def list_by_author(self, author_id: str, limit: int) -> list[Article]:
        """List articles by author."""
        result = await self.db.execute(
            select(ArticleModel)
            .where(ArticleModel.author_id == author_id)
            .limit(limit)
        )
        models = result.scalars().all()

        return [self._to_domain(model) for model in models]

    async def create(self, article: Article) -> Article:
        """Create new article."""
        model = self._to_model(article)
        self.db.add(model)
        await self.db.commit()
        await self.db.refresh(model)

        return self._to_domain(model)

    @staticmethod
    def _to_domain(model: ArticleModel) -> Article:
        """Convert database model to domain model."""
        return Article(
            id=model.id,
            title=model.title,
            content=model.content,
            author_id=model.author_id,
            published=model.published
        )

    @staticmethod
    def _to_model(article: Article) -> ArticleModel:
        """Convert domain model to database model."""
        return ArticleModel(
            id=article.id,
            title=article.title,
            content=article.content,
            author_id=article.author_id,
            published=article.published
        )
```

### Test Repository

For testing, create an in-memory implementation.

```python
class InMemoryArticleRepository:
    """In-memory implementation for testing."""

    def __init__(self):
        self.articles: dict[int, Article] = {}
        self.next_id = 1

    async def get_by_id(self, article_id: int) -> Article | None:
        return self.articles.get(article_id)

    async def list_by_author(self, author_id: str, limit: int) -> list[Article]:
        articles = [
            a for a in self.articles.values()
            if a.author_id == author_id
        ]
        return articles[:limit]

    async def create(self, article: Article) -> Article:
        article_id = self.next_id
        self.next_id += 1

        new_article = dataclass.replace(article, id=article_id)
        self.articles[article_id] = new_article

        return new_article

    async def update(self, article: Article) -> Article:
        self.articles[article.id] = article
        return article

    async def delete(self, article_id: int) -> None:
        del self.articles[article_id]
```

## Dependency Injection

Framework-agnostic dependency injection through constructor injection and factory functions.

### Constructor Injection

```python
# ✅ Good - dependencies injected through constructor
class OrderService:
    def __init__(
        self,
        order_repo: OrderRepository,
        user_service: UserService,
        payment_service: PaymentService
    ):
        self.order_repo = order_repo
        self.user_service = user_service
        self.payment_service = payment_service

# ❌ Bad - service creates its own dependencies
class OrderServiceBad:
    def __init__(self):
        self.order_repo = SQLAlchemyOrderRepository(get_db())
        self.user_service = UserService()
        self.payment_service = PaymentService()
```

### Factory Functions

Create factory functions to wire dependencies.

```python
# factories.py
from collections.abc import AsyncGenerator
from sqlalchemy.ext.asyncio import AsyncSession

# Database session factory
async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session_maker() as session:
        yield session

# Repository factories
def get_user_repository(db: AsyncSession) -> UserRepository:
    return SQLAlchemyUserRepository(db)

def get_order_repository(db: AsyncSession) -> OrderRepository:
    return SQLAlchemyOrderRepository(db)

# Service factories
def get_user_service(
    db: AsyncSession,
    cache: CacheService
) -> UserService:
    repo = get_user_repository(db)
    return UserService(repo=repo, cache=cache)

def get_order_service(
    db: AsyncSession,
    cache: CacheService
) -> OrderService:
    user_service = get_user_service(db, cache)
    payment_service = get_payment_service()
    order_repo = get_order_repository(db)

    return OrderService(
        order_repo=order_repo,
        user_service=user_service,
        payment_service=payment_service
    )
```

### Integration with Frameworks

**FastAPI:**
```python
from fastapi import Depends
from typing import Annotated

@router.get("/users/{user_id}")
async def get_user(
    user_id: str,
    service: Annotated[UserService, Depends(get_user_service)]
) -> User:
    return await service.get_user(user_id)
```

**Flask (with manual wiring):**
```python
@app.route("/users/<user_id>")
async def get_user(user_id: str):
    db = await get_db()
    cache = get_cache_service()
    service = get_user_service(db, cache)

    return await service.get_user(user_id)
```

**Testing:**
```python
async def test_user_service_caching():
    # Inject test doubles
    repo = InMemoryUserRepository()
    cache = MockCacheService()
    service = UserService(repo=repo, cache=cache)

    # Test caching behavior
    user = await service.get_user("123")
    assert cache.get_calls == 1

    # Second call should hit cache
    user2 = await service.get_user("123")
    assert cache.get_calls == 2
    assert repo.get_by_id_calls == 1  # Only called once
```

## Configuration Management

Use Pydantic for type-safe configuration with environment variable support.

### Configuration Models

```python
from pydantic_settings import BaseSettings
from pydantic import Field

class DatabaseConfig(BaseSettings):
    host: str = Field(..., env="DB_HOST")
    port: int = Field(5432, env="DB_PORT")
    name: str = Field(..., env="DB_NAME")
    user: str = Field(..., env="DB_USER")
    password: str = Field(..., env="DB_PASSWORD")

    @property
    def url(self) -> str:
        return f"postgresql://{self.user}:{self.password}@{self.host}:{self.port}/{self.name}"

class RedisConfig(BaseSettings):
    host: str = Field("localhost", env="REDIS_HOST")
    port: int = Field(6379, env="REDIS_PORT")
    db: int = Field(0, env="REDIS_DB")

class AppConfig(BaseSettings):
    environment: str = Field("development", env="ENVIRONMENT")
    debug: bool = Field(False, env="DEBUG")

    database: DatabaseConfig = Field(default_factory=DatabaseConfig)
    redis: RedisConfig = Field(default_factory=RedisConfig)

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False

# Load configuration at startup
config = AppConfig()
```

### Environment-Specific Configuration

```python
from enum import Enum

class Environment(str, Enum):
    DEVELOPMENT = "development"
    STAGING = "staging"
    PRODUCTION = "production"

class AppConfig(BaseSettings):
    environment: Environment = Field(Environment.DEVELOPMENT, env="ENVIRONMENT")

    @property
    def is_production(self) -> bool:
        return self.environment == Environment.PRODUCTION

    @property
    def is_development(self) -> bool:
        return self.environment == Environment.DEVELOPMENT

    @property
    def log_level(self) -> str:
        return "DEBUG" if self.is_development else "INFO"

# Use configuration
if config.is_production:
    # Production-only setup
    setup_sentry()
    setup_monitoring()
```

### Secrets Management

Never hardcode secrets. Use environment variables or secret managers.

```python
from pydantic import SecretStr, Field

class SecretsConfig(BaseSettings):
    api_key: SecretStr = Field(..., env="API_KEY")
    database_password: SecretStr = Field(..., env="DB_PASSWORD")
    jwt_secret: SecretStr = Field(..., env="JWT_SECRET")

    def get_api_key(self) -> str:
        """Get plaintext API key."""
        return self.api_key.get_secret_value()

    def get_database_password(self) -> str:
        """Get plaintext database password."""
        return self.database_password.get_secret_value()

# Secrets never printed accidentally
config = SecretsConfig()
print(config)  # Shows SecretStr('**********')
```

### Configuration Validation

Validate configuration at startup to fail fast.

```python
class AppConfig(BaseSettings):
    def validate_config(self) -> None:
        """Validate configuration at startup."""
        if self.is_production:
            # Require production secrets
            if not self.jwt_secret:
                raise ValueError("JWT_SECRET required in production")

            if not self.sentry_dsn:
                raise ValueError("SENTRY_DSN required in production")

        # Validate database connection
        if not self.database.host:
            raise ValueError("Database host required")

# At application startup
config = AppConfig()
config.validate_config()
```
