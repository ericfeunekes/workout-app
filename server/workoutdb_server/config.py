"""Configuration layer. Settings loaded from env via pydantic-settings.

Foundation layer — must not import from any other repo-local module.
Enforced by the import-linter contract in pyproject.toml.
"""

from functools import lru_cache
from pathlib import Path

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="WORKOUTDB_",
        env_file=".env",
        extra="ignore",
        case_sensitive=False,
    )

    bearer_token: SecretStr = Field(
        min_length=16,
        description="Shared secret the iOS app presents on every request. "
        "Generated with `python -c 'import secrets; print(secrets.token_urlsafe(48))'`. "
        "Minimum 16 characters — catches the obvious 'foo' / 'test' footgun.",
    )
    user_id: str = Field(
        min_length=1,
        description="The app_user UUID this bearer token authenticates as. "
        "Per ADR-2026-04-17, endpoints resolve user_id from the token — the client "
        "never sends it. Generate once with `python -c 'import uuid; print(uuid.uuid4())'` "
        "and paste into both .env and the iOS app's setup. A row is auto-created on "
        "first startup if missing, named per `user_name`.",
    )
    user_name: str = Field(
        default="Eric",
        description="Display name used when bootstrapping the app_user row.",
    )
    db_path: Path = Field(
        default=Path("./workout.db"),
        description="Absolute path to the SQLite file on the home server.",
    )
    host: str = Field(
        default="0.0.0.0", description="Bind address; Tailscale handles reachability."
    )
    port: int = Field(default=8080)
    debug: bool = Field(default=False, description="Verbose logging; never enable in prod.")
    event_log_retention_days: int = Field(
        default=90,
        description="How many days of `event_log` rows to retain. The startup "
        "sweep deletes rows with `ts` older than this. 90 days gives plenty of "
        "runway for post-hoc debugging of 'what happened at the gym last week' "
        "without letting the table grow unbounded on a single-user home server. "
        "Set to 0 to purge everything on every boot (useful in tests / fresh deploys).",
    )


@lru_cache
def get_settings() -> Settings:
    """Cached settings accessor. Call `get_settings.cache_clear()` in tests using monkeypatch."""
    return Settings()
