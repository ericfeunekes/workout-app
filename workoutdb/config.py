from __future__ import annotations

import os
import stat
import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

DEFAULT_APP_HOME = Path("~/.workout-app")
DEFAULT_CONFIG_PATH = DEFAULT_APP_HOME.expanduser() / "config.toml"


@dataclass
class GoogleConfig:
    client_secret_path: Path | None = None
    token_path: Path | None = None


@dataclass
class CalendarConfig:
    default_id: str | None = None


@dataclass
class PathsConfig:
    app_home: Path
    config_path: Optional[Path] = None


@dataclass
class ResolvedPaths:
    app_home: Path
    config_path: Path


@dataclass
class AppConfig:
    paths: PathsConfig
    google: GoogleConfig
    calendar: CalendarConfig


class ConfigError(RuntimeError):
    pass


def _expand_path(value: str | Path | None) -> Optional[Path]:
    if value is None:
        return None
    return Path(value).expanduser()


def _ensure_private_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    try:
        path.chmod(stat.S_IRWXU)
    except OSError:
        pass


def resolve_paths(path: Optional[Path] = None) -> ResolvedPaths:
    env_home = os.getenv("WORKOUT_APP_HOME")
    app_home = Path(env_home).expanduser() if env_home else DEFAULT_APP_HOME.expanduser()

    config_path = (
        path
        or _expand_path(os.getenv("WORKOUT_APP_CONFIG"))
        or (app_home / "config.toml")
    )

    _ensure_private_dir(app_home)

    return ResolvedPaths(
        app_home=app_home,
        config_path=Path(config_path).expanduser(),
    )


def load_config(path: Optional[Path] = None) -> AppConfig:
    resolved = resolve_paths(path)
    config_path = resolved.config_path
    if not config_path.exists():
        raise ConfigError(
            f"Config not found at {config_path}. Create it (see README)."
        )

    data = tomllib.loads(config_path.read_text())

    paths_raw = data.get("paths", {})
    configured_app_home = _expand_path(paths_raw.get("app_home"))

    paths = PathsConfig(
        app_home=configured_app_home or resolved.app_home,
        config_path=config_path,
    )

    google_raw = data.get("google", {})
    token_path = (configured_app_home or resolved.app_home) / "tokens" / "google-oauth.json"
    google = GoogleConfig(
        client_secret_path=_expand_path(google_raw.get("client_secret_path")),
        token_path=token_path,
    )

    calendar_raw = data.get("calendar", {})
    calendar = CalendarConfig(
        default_id=calendar_raw.get("default_id"),
    )

    if google.client_secret_path is None:
        raise ConfigError("google.client_secret_path is required")
    if not google.client_secret_path.exists():
        raise ConfigError(f"Google client secret not found: {google.client_secret_path}")
    if google.token_path is None:
        raise ConfigError("google.token_path could not be resolved")

    return AppConfig(
        paths=paths,
        google=google,
        calendar=calendar,
    )


def config_example() -> str:
    return """
[paths]
app_home = "/Users/ericfeunekes/.workout-app"

[google]
client_secret_path = "/Users/ericfeunekes/.workout-app/google-client.json"

[calendar]
default_id = "primary"
""".strip()
