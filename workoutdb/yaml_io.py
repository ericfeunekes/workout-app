from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml
from pydantic import ValidationError

from .yaml_models import LibraryYaml


def load_yaml(path: Path) -> dict[str, Any]:
    return yaml.safe_load(path.read_text(encoding="utf-8")) or {}


def validate_yaml(path: Path) -> LibraryYaml:
    data = load_yaml(path)
    try:
        return LibraryYaml.model_validate(data)
    except ValidationError as exc:
        raise ValueError(_format_validation_error(exc)) from exc


def _format_validation_error(exc: ValidationError) -> str:
    lines = ["YAML validation failed:"]
    for err in exc.errors():
        loc = ".".join(str(part) for part in err.get("loc", []))
        msg = err.get("msg", "Invalid value")
        if loc:
            lines.append(f"- {loc}: {msg}")
        else:
            lines.append(f"- {msg}")
    return "\n".join(lines)
