"""Validate skill: and playbook: references resolve to existing assets."""

from __future__ import annotations

import re
import sys
from pathlib import Path

SKILL_PATTERN = re.compile(r"skill:([A-Za-z0-9\-_/]+)")
PLAYBOOK_PATTERN = re.compile(r"playbook:([A-Za-z0-9\-_/]+)")
TARGET_ROOTS = [Path("docs"), Path("agents"), Path(".issues")]


def load_valid_names(root: Path, marker: str) -> set[str]:
    base = root / marker
    if not base.exists():
        return set()
    names: set[str] = set()
    for path in base.iterdir():
        if path.is_dir():
            names.add(path.name)
    return names


def scan_file(path: Path, skills: set[str], playbooks: set[str]) -> list[str]:
    problems: list[str] = []
    text = path.read_text(encoding="utf-8", errors="ignore")
    for match in SKILL_PATTERN.finditer(text):
        target = match.group(1)
        name = target.split("/")[0]
        if name not in skills:
            problems.append(f"{path}: unknown skill reference '{target}'")
    for match in PLAYBOOK_PATTERN.finditer(text):
        target = match.group(1)
        name = target.split("/")[0]
        if name not in playbooks:
            problems.append(f"{path}: unknown playbook reference '{target}'")
    return problems


def main() -> int:
    skills = load_valid_names(Path("agents"), "skills")
    playbooks = load_valid_names(Path("agents"), "playbooks")

    problems: list[str] = []
    for root in TARGET_ROOTS:
        if not root.exists():
            continue
        for path in root.rglob("*.md"):
            problems.extend(scan_file(path, skills, playbooks))

    if problems:
        print("\n".join(sorted(problems)))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
