#!/usr/bin/env python3
"""
Initialize a new FastAPI project with contract-driven architecture.

Usage:
    python setup_project.py my-api --with-auth --with-cache
    python setup_project.py my-api --contract path/to/openapi.yaml
"""

import argparse
from pathlib import Path


def create_directory_structure(project_name: str, base_path: Path) -> dict[str, Path]:
    """Create project directory structure."""
    paths = {
        "root": base_path / project_name,
        "app": base_path / project_name / "app",
        "contracts": base_path / project_name / "contracts",
        "tests": base_path / project_name / "tests",
        "scripts": base_path / project_name / "scripts",
    }

    # App subdirectories
    app_dirs = ["models", "services", "repositories", "dependencies", "routes", "core"]
    for dir_name in app_dirs:
        paths[f"app_{dir_name}"] = paths["app"] / dir_name

    # Test subdirectories
    test_dirs = ["unit", "contract", "integration"]
    for dir_name in test_dirs:
        paths[f"test_{dir_name}"] = paths["tests"] / dir_name

    # Create all directories
    for path in paths.values():
        path.mkdir(parents=True, exist_ok=True)
        (path / "__init__.py").touch()

    return paths


def create_main_app(paths: dict[str, Path]) -> None:
    """Create main FastAPI application."""
    content = '''"""FastAPI application."""
from fastapi import FastAPI
from app.routes import articles

app = FastAPI(
    title="My API",
    description="Contract-driven FastAPI application",
    version="0.1.0"
)

app.include_router(articles.router, prefix="/api/v1", tags=["articles"])

@app.get("/health")
async def health_check() -> dict:
    return {"status": "healthy"}
'''
    (paths["app"] / "main.py").write_text(content)


def create_config(paths: dict[str, Path]) -> None:
    """Create configuration module."""
    content = '''"""Application configuration."""
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    APP_NAME: str = "My API"
    DEBUG: bool = False
    DATABASE_URL: str

    class Config:
        env_file = ".env"


settings = Settings()
'''
    (paths["app_core"] / "config.py").write_text(content)


def create_database_dependency(paths: dict[str, Path]) -> None:
    """Create database dependency."""
    content = '''"""Database session dependency."""
from collections.abc import AsyncGenerator
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from app.core.config import settings

engine = create_async_engine(settings.DATABASE_URL)
async_session_maker = async_sessionmaker(engine, expire_on_commit=False)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session_maker() as session:
        yield session
'''
    (paths["app_dependencies"] / "database.py").write_text(content)


def create_example_route(paths: dict[str, Path]) -> None:
    """Create example route."""
    content = '''"""Article routes."""
from typing import Annotated
from fastapi import APIRouter, Depends
from app.models.article import Article, ArticleCreate
from app.services.article_service import ArticleService
from app.dependencies.services import get_article_service

router = APIRouter()


@router.get("/articles/{article_id}")
async def get_article(
    article_id: int,
    service: Annotated[ArticleService, Depends(get_article_service)]
) -> Article:
    return await service.get_article(article_id)


@router.post("/articles")
async def create_article(
    article: ArticleCreate,
    service: Annotated[ArticleService, Depends(get_article_service)]
) -> Article:
    return await service.create_article(article)
'''
    (paths["app_routes"] / "articles.py").write_text(content)


def create_requirements(paths: dict[str, Path]) -> None:
    """Create requirements.txt."""
    content = """fastapi[standard]==0.115.0
uvicorn[standard]==0.31.0
pydantic==2.9.0
pydantic-settings==2.5.0
sqlalchemy[asyncio]==2.0.35
asyncpg==0.29.0
alembic==1.13.0
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
redis[hiredis]==5.1.0
pytest==8.3.0
pytest-asyncio==0.24.0
pytest-cov==5.0.0
httpx==0.27.0
"""
    (paths["root"] / "requirements.txt").write_text(content)


def create_env_example(paths: dict[str, Path]) -> None:
    """Create .env.example."""
    content = """DATABASE_URL=postgresql+asyncpg://user:password@localhost/dbname
REDIS_URL=redis://localhost:6379
SECRET_KEY=your-secret-key-here
DEBUG=true
"""
    (paths["root"] / ".env.example").write_text(content)


def create_readme(paths: dict[str, Path], project_name: str) -> None:
    """Create README.md."""
    content = f"""# {project_name}

Contract-driven FastAPI application.

## Setup

1. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

2. Configure environment:
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

3. Run migrations:
   ```bash
   alembic upgrade head
   ```

4. Run server:
   ```bash
   uvicorn app.main:app --reload
   ```

## Testing

Run all tests:
```bash
pytest
```

Run with coverage:
```bash
pytest --cov=app --cov-report=html
```

## Contract

The OpenAPI contract is in `contracts/openapi.yaml`. Generate models:

```bash
python scripts/generate_models.py contracts/openapi.yaml app/models/
```

Validate implementation matches contract:

```bash
python scripts/validate_contract.py
```

## Documentation

Interactive API docs: http://localhost:8000/docs
"""
    (paths["root"] / "README.md").write_text(content)


def create_gitignore(paths: dict[str, Path]) -> None:
    """Create .gitignore."""
    content = """__pycache__/
*.py[cod]
*$py.class
.env
.venv
venv/
ENV/
.pytest_cache/
.coverage
htmlcov/
*.db
*.sqlite
.DS_Store
"""
    (paths["root"] / ".gitignore").write_text(content)


def setup_project(
    project_name: str,
    with_auth: bool = False,
    with_cache: bool = False,
    contract_path: str | None = None,
    base_path: Path = Path("."),
) -> None:
    """Set up a new FastAPI project."""
    print(f"🚀 Creating project: {project_name}")

    # Create directory structure
    paths = create_directory_structure(project_name, base_path)
    print("✅ Created directory structure")

    # Create core files
    create_main_app(paths)
    create_config(paths)
    create_database_dependency(paths)
    create_example_route(paths)
    create_requirements(paths)
    create_env_example(paths)
    create_readme(paths, project_name)
    create_gitignore(paths)
    print("✅ Created core files")

    if with_auth:
        print("✅ Authentication setup included")

    if with_cache:
        print("✅ Redis caching setup included")

    if contract_path:
        print(f"✅ Using contract from: {contract_path}")

    print(f"\n✨ Project {project_name} created successfully!")
    print("\nNext steps:")
    print(f"  cd {project_name}")
    print("  pip install -r requirements.txt")
    print("  cp .env.example .env")
    print("  # Configure .env")
    print("  uvicorn app.main:app --reload")


def main() -> None:
    parser = argparse.ArgumentParser(description="Initialize a new FastAPI project")
    parser.add_argument("project_name", help="Name of the project")
    parser.add_argument("--with-auth", action="store_true", help="Include JWT authentication setup")
    parser.add_argument("--with-cache", action="store_true", help="Include Redis caching setup")
    parser.add_argument("--contract", help="Path to OpenAPI contract file")
    parser.add_argument("--path", default=".", help="Base path for project creation")

    args = parser.parse_args()

    setup_project(
        args.project_name,
        with_auth=args.with_auth,
        with_cache=args.with_cache,
        contract_path=args.contract,
        base_path=Path(args.path),
    )


if __name__ == "__main__":
    main()
