#!/usr/bin/env python3
"""
Example configuration management setup for FastAPI.
Demonstrates environment-based config with file defaults and env var overrides.
"""

import os
from functools import lru_cache
from pathlib import Path

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class BaseConfig(BaseSettings):
    """Base configuration shared across all environments"""

    # App metadata
    app_name: str = "FastAPI Application"
    api_version: str = "1.0.0"

    # Logging
    log_level: str = Field(default="INFO", pattern="^(DEBUG|INFO|WARNING|ERROR|CRITICAL)$")

    # CORS
    cors_origins: list[str] = Field(default_factory=lambda: ["http://localhost:3000"])

    # Timeouts
    api_timeout: int = Field(default=30, ge=1, le=300)

    model_config = SettingsConfigDict(
        case_sensitive=False,
        env_file_encoding="utf-8",
    )

    @field_validator("cors_origins", mode="before")
    @classmethod
    def parse_cors_origins(cls, v):
        """Parse comma-separated CORS origins from env var"""
        if isinstance(v, str):
            return [origin.strip() for origin in v.split(",") if origin.strip()]
        return v


class LocalConfig(BaseConfig):
    """Local development configuration"""

    environment: str = "local"
    debug: bool = True
    log_level: str = "DEBUG"

    # Local database (SQLite for easy dev)
    database_url: str = "sqlite+aiosqlite:///./local.db"
    database_pool_size: int = 5
    database_max_overflow: int = 5

    # Local Redis
    redis_url: str = "redis://localhost:6379/0"
    redis_max_connections: int = 10

    # Dev-mode JWT
    jwt_secret_key: str = "local-dev-secret-DO-NOT-USE-IN-PRODUCTION"
    jwt_algorithm: str = "HS256"
    jwt_expiration_minutes: int = 1440  # 24 hours for dev convenience

    # Feature flags
    enable_caching: bool = False  # Disable for dev to see fresh data
    enable_rate_limiting: bool = False

    model_config = SettingsConfigDict(
        env_file=".env.local",
        env_file_encoding="utf-8",
    )


class DevConfig(BaseConfig):
    """Development environment configuration"""

    environment: str = "dev"
    debug: bool = True
    log_level: str = "DEBUG"

    # Dev database (must be set via env var)
    database_url: str = Field(..., description="Required: DEV database URL")
    database_pool_size: int = 10
    database_max_overflow: int = 5

    # Dev Redis (must be set via env var)
    redis_url: str = Field(..., description="Required: DEV Redis URL")
    redis_max_connections: int = 20

    # Dev JWT (must be set via env var)
    jwt_secret_key: str = Field(..., min_length=32, description="Required: JWT secret")
    jwt_algorithm: str = "HS256"
    jwt_expiration_minutes: int = 60

    # Feature flags
    enable_caching: bool = True
    enable_rate_limiting: bool = False

    model_config = SettingsConfigDict(
        env_file=".env.dev",
        env_file_encoding="utf-8",
    )


class StagingConfig(BaseConfig):
    """Staging environment configuration"""

    environment: str = "staging"
    debug: bool = False
    log_level: str = "INFO"

    # Staging database (must be set via env var)
    database_url: str = Field(..., description="Required: STAGING database URL")
    database_pool_size: int = 30
    database_max_overflow: int = 10

    # Staging Redis (must be set via env var)
    redis_url: str = Field(..., description="Required: STAGING Redis URL")
    redis_max_connections: int = 50

    # Staging JWT (must be set via env var)
    jwt_secret_key: str = Field(..., min_length=32, description="Required: JWT secret")
    jwt_algorithm: str = "HS256"
    jwt_expiration_minutes: int = 60

    # Feature flags
    enable_caching: bool = True
    enable_rate_limiting: bool = True

    model_config = SettingsConfigDict(
        env_file=".env.staging",
        env_file_encoding="utf-8",
    )

    @field_validator("jwt_secret_key")
    @classmethod
    def validate_production_secret(cls, v: str) -> str:
        """Ensure production secret is not a dev default"""
        forbidden_secrets = [
            "local-dev-secret-DO-NOT-USE-IN-PRODUCTION",
            "dev-secret-change-in-production",
            "secret",
            "password",
        ]
        if v.lower() in forbidden_secrets:
            raise ValueError("JWT secret must be a strong, unique value in staging/production")
        return v


class ProdConfig(BaseConfig):
    """Production environment configuration"""

    environment: str = "production"
    debug: bool = False
    log_level: str = "WARNING"

    # Production database (must be set via env var)
    database_url: str = Field(..., description="Required: PROD database URL")
    database_pool_size: int = 50
    database_max_overflow: int = 20
    database_pool_timeout: int = 30

    # Production Redis (must be set via env var)
    redis_url: str = Field(..., description="Required: PROD Redis URL")
    redis_max_connections: int = 100

    # Production JWT (must be set via env var)
    jwt_secret_key: str = Field(..., min_length=32, description="Required: JWT secret")
    jwt_algorithm: str = "HS256"
    jwt_expiration_minutes: int = 60

    # Feature flags
    enable_caching: bool = True
    enable_rate_limiting: bool = True

    model_config = SettingsConfigDict(
        env_file=".env.prod",
        env_file_encoding="utf-8",
    )

    @field_validator("jwt_secret_key")
    @classmethod
    def validate_production_secret(cls, v: str) -> str:
        """Ensure production secret is not a dev default"""
        forbidden_secrets = [
            "local-dev-secret-DO-NOT-USE-IN-PRODUCTION",
            "dev-secret-change-in-production",
            "secret",
            "password",
        ]
        if v.lower() in forbidden_secrets:
            raise ValueError("JWT secret must be a strong, unique value in production")
        if len(v) < 32:
            raise ValueError("JWT secret must be at least 32 characters in production")
        return v


def get_settings_class() -> type[BaseSettings]:
    """
    Get the appropriate settings class based on ENV environment variable.

    Set ENV to: local, dev, staging, or production
    """
    env = os.getenv("ENV", "local").lower()

    config_map = {
        "local": LocalConfig,
        "dev": DevConfig,
        "development": DevConfig,
        "staging": StagingConfig,
        "stage": StagingConfig,
        "production": ProdConfig,
        "prod": ProdConfig,
    }

    settings_class = config_map.get(env)

    if settings_class is None:
        raise ValueError(
            f"Invalid ENV value: {env}. Must be one of: {', '.join(config_map.keys())}"
        )

    return settings_class


@lru_cache
def get_settings() -> BaseSettings:
    """
    Get cached settings instance.

    Usage in FastAPI:
        from fastapi import Depends
        from typing import Annotated

        @app.get("/info")
        def get_info(settings: Annotated[BaseSettings, Depends(get_settings)]):
            return {"app_name": settings.app_name}
    """
    settings_class = get_settings_class()
    return settings_class()


def create_env_example():
    """Create .env.example file showing all available config options"""
    example_content = """# Environment Configuration
# Copy this file to .env.local for local development
# For other environments, create .env.dev, .env.staging, .env.prod

# Environment selector (local, dev, staging, production)
ENV=local

# Database
DATABASE_URL=postgresql+asyncpg://user:password@localhost:5432/db_name
DATABASE_POOL_SIZE=20
DATABASE_MAX_OVERFLOW=10

# Redis
REDIS_URL=redis://localhost:6379/0
REDIS_MAX_CONNECTIONS=50

# JWT Authentication
JWT_SECRET_KEY=your-secret-key-minimum-32-characters-long
JWT_ALGORITHM=HS256
JWT_EXPIRATION_MINUTES=60

# CORS (comma-separated)
CORS_ORIGINS=http://localhost:3000,http://localhost:8000

# Logging
LOG_LEVEL=INFO

# Feature Flags
ENABLE_CACHING=true
ENABLE_RATE_LIMITING=false

# Timeouts
API_TIMEOUT=30
"""

    env_example_path = Path(".env.example")
    env_example_path.write_text(example_content)
    print(f"Created {env_example_path}")


if __name__ == "__main__":
    # Demo usage
    print("FastAPI Configuration Management Demo\n")

    # Create .env.example
    create_env_example()
    print()

    # Load settings based on ENV
    try:
        settings = get_settings()
        print(f"Loaded configuration for environment: {settings.environment}")
        print(f"Debug mode: {settings.debug}")
        print(f"Database pool size: {settings.database_pool_size}")
        print(f"Caching enabled: {settings.enable_caching}")
        print(f"CORS origins: {settings.cors_origins}")
    except Exception as e:
        print(f"Error loading settings: {e}")
        print("\nTip: Set ENV environment variable or create .env.local file")
