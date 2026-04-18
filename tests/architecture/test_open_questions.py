"""FF-10 · Open-questions hygiene.

docs/open-questions.md is the living gap register. Every item must carry a
machine-readable disposition so the register can't drift into prose. Items
marked 'resolved' must move out of the register within an ADR cycle.

See docs/architecture/fitness-functions.md § FF-10.
"""

from __future__ import annotations

import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
OPEN_QUESTIONS = REPO_ROOT / "docs" / "open-questions.md"

ALLOWED_DISPOSITIONS = {
    "decide-next",
    "defer-to-v1.1+",
    "resolve-in-code",
    "watchlist",
    "resolved",
}

# Find each `### Heading` (an item) and the nearest `**Disposition:**` line after it,
# up to the next `### ` or `## ` boundary.
_ITEM_RE = re.compile(r"^### (.+)$", re.MULTILINE)
_DISPOSITION_RE = re.compile(r"^\s*-\s*\*\*Disposition:\*\*\s*(.+?)\.?\s*$", re.MULTILINE)


def _items_and_dispositions() -> list[tuple[str, str | None]]:
    text = OPEN_QUESTIONS.read_text()
    lines = text.splitlines()
    items: list[tuple[str, str | None]] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        m = _ITEM_RE.match(line)
        if not m:
            i += 1
            continue
        heading = m.group(1).strip()
        # Scan forward for disposition, stopping at the next ### or ##.
        j = i + 1
        disposition: str | None = None
        while j < len(lines):
            next_line = lines[j]
            if next_line.startswith("### ") or next_line.startswith("## "):
                break
            dm = _DISPOSITION_RE.match(next_line)
            if dm:
                disposition = dm.group(1).strip()
                break
            j += 1
        items.append((heading, disposition))
        i = j
    return items


def test_every_item_has_a_disposition() -> None:
    items = _items_and_dispositions()
    missing = [heading for heading, disp in items if disp is None]
    assert not missing, (
        "Items in docs/open-questions.md are missing a **Disposition:** line. "
        "Each item must carry one of: "
        f"{sorted(ALLOWED_DISPOSITIONS)}. Missing: {missing}"
    )


def _leading_disposition(disposition_line: str) -> str:
    """Extract the disposition token from the start of the line.

    Longest-match against the allowed set so `defer-to-v1.1+` (which contains `.`)
    is matched correctly rather than split on the dot.
    """
    text = disposition_line.lstrip()
    for value in sorted(ALLOWED_DISPOSITIONS, key=len, reverse=True):
        if text.startswith(value):
            return value
    # Fall back to the first whitespace-separated token — used only for error messages.
    return text.split(None, 1)[0]


def test_dispositions_use_allowed_values() -> None:
    items = _items_and_dispositions()
    bad: list[tuple[str, str]] = []
    for heading, disp in items:
        if disp is None:
            continue
        token = _leading_disposition(disp)
        if token not in ALLOWED_DISPOSITIONS:
            bad.append((heading, token))
    assert not bad, (
        "docs/open-questions.md contains dispositions that aren't in the allowed set. "
        f"Allowed: {sorted(ALLOWED_DISPOSITIONS)}. "
        f"Violations (heading, value): {bad}"
    )


def test_resolved_items_are_not_lingering() -> None:
    """Items that move to 'resolved' must be deleted or moved into the appropriate doc.

    We permit a single grace period: the gap register may contain at most one
    'resolved' item at a time, and only to document a just-completed resolution.
    Anything beyond that signals the register is accumulating rot.
    """
    items = _items_and_dispositions()
    resolved = [
        heading for heading, disp in items if disp and _leading_disposition(disp) == "resolved"
    ]
    assert len(resolved) <= 1, (
        "docs/open-questions.md has multiple 'resolved' items. "
        "Resolved items should be removed from the register (the decision lives in its "
        f"home doc — ADR, spec, prescription, sync, app README). Resolved items found: {resolved}"
    )
