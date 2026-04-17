"""Unit tests for workoutdb_server.config."""

from pathlib import Path

import pytest

from workoutdb_server.config import Settings, get_settings


def test_settings_load_with_env(monkeypatch: pytest.MonkeyPatch) -> None:
    get_settings.cache_clear()
    monkeypatch.setenv("WORKOUTDB_BEARER_TOKEN", "test-token-1234567890")
    monkeypatch.setenv("WORKOUTDB_DB_PATH", "/tmp/test.db")
    monkeypatch.setenv("WORKOUTDB_PORT", "9090")

    settings = Settings()

    assert settings.bearer_token.get_secret_value() == "test-token-1234567890"
    assert settings.db_path == Path("/tmp/test.db")
    assert settings.port == 9090
    assert settings.debug is False  # default


def test_settings_requires_bearer_token(monkeypatch: pytest.MonkeyPatch) -> None:
    get_settings.cache_clear()
    monkeypatch.delenv("WORKOUTDB_BEARER_TOKEN", raising=False)

    # _env_file=None disables .env fallback so the missing var is visible to validation.
    with pytest.raises(ValueError):
        Settings(_env_file=None)  # type: ignore[call-arg]


def test_settings_rejects_short_bearer_token(monkeypatch: pytest.MonkeyPatch) -> None:
    get_settings.cache_clear()
    monkeypatch.setenv("WORKOUTDB_BEARER_TOKEN", "too-short")

    with pytest.raises(ValueError):
        Settings(_env_file=None)  # type: ignore[call-arg]
