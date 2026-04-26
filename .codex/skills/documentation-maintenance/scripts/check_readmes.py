"""Ensure required leaf folders ship with README.md and root links to docs."""

from __future__ import annotations

import sys
from pathlib import Path

REQUIRED_LEAFS = ["tests", "scripts", "migrations", "infra"]


def main() -> int:
    problems: list[str] = []
    root = Path(".")

    for name in REQUIRED_LEAFS:
        directory = root / name
        if directory.exists() and directory.is_dir():
            if not (directory / "README.md").exists():
                problems.append(f"{directory}/ missing README.md")

    root_readme = root / "README.md"
    if root_readme.exists():
        text = root_readme.read_text(encoding="utf-8")
        if "docs/index.md" not in text:
            problems.append("Root README.md should include a link to docs/index.md")
    else:
        problems.append("Missing root README.md")

    if problems:
        print("\n".join(problems))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
