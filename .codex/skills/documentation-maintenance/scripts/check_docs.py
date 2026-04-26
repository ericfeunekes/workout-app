"""Validate documentation front matter, freshness, and hygiene."""

from __future__ import annotations

import re
import sys
from datetime import date, timedelta
from pathlib import Path

REQUIRED_KEYS = {"title", "status", "last_reviewed", "purpose"}
STALE_DAYS = 90
MAX_LINES = 800
FORBID_FLAT_WHEN_FOLDER = {"testing", "infra"}
CRITICAL = {
    "docs/index.md",
    "docs/runbooks/incident-response.md",
    "docs/infra/environments.md",
}
SECRET_PATTERNS = (
    r"AKIA[0-9A-Z]{16}",
    r"-----BEGIN [A-Z ]+PRIVATE KEY-----",
    r"sk-[A-Za-z0-9]{20,}",
)
FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---", re.S)


def parse_front_matter(text: str) -> dict[str, str]:
    match = FRONTMATTER_RE.match(text)
    if not match:
        return {}
    values: dict[str, str] = {}
    for line in match.group(1).splitlines():
        if ":" in line:
            key, value = line.split(":", 1)
            values[key.strip()] = value.strip().strip('"')
    return values


def is_stale(ymd: str, days: int) -> bool:
    year, month, day = map(int, ymd.split("-"))
    return date.today() - date(year, month, day) > timedelta(days=days)


def main() -> int:
    problems: list[str] = []
    docs_dir = Path("docs")
    if not docs_dir.exists():
        print("docs/ directory not found")
        return 1

    for topic in FORBID_FLAT_WHEN_FOLDER:
        flat = docs_dir / f"{topic}.md"
        folder = docs_dir / topic
        if folder.exists() and flat.exists():
            problems.append(
                f"Duplicate: {flat} and {folder}/ coexist; keep the folder with index.md"
            )

    for path in docs_dir.rglob("*.md"):
        text = path.read_text(encoding="utf-8")
        fm = parse_front_matter(text)
        missing = REQUIRED_KEYS - set(fm)
        if missing:
            problems.append(f"{path}: missing front-matter keys {sorted(missing)}")
        rel = str(path).replace("\\", "/")
        if rel in CRITICAL and "last_reviewed" in fm:
            try:
                if is_stale(fm["last_reviewed"], STALE_DAYS):
                    problems.append(f"{path}: last_reviewed is stale (> {STALE_DAYS}d)")
            except Exception:
                problems.append(f"{path}: invalid last_reviewed date")
        if text.count("\n") + 1 > MAX_LINES:
            problems.append(f"{path}: exceeds {MAX_LINES} lines; split the content")
        for pattern in SECRET_PATTERNS:
            if re.search(pattern, text):
                problems.append(f"{path}: potential secret-like content detected")

    if problems:
        print("\n".join(problems))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
