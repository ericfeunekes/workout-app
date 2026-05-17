"""FF-4 · Monorepo top-level shape.

The repo root should stay small. A 9th top-level directory requires an ADR.
See docs/architecture/fitness-functions.md and docs/architecture/boundaries.md
for the rule and the allowlist of sanctioned top-level directories.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent

# Top-level directories that are part of the architecture. Anything outside
# this set must either be added deliberately (with an ADR) or is agent/tool
# debris that should be gitignored. The test only inspects directories that
# git actually tracks (see `_top_level_dirs`) so local-only cruft —
# `scripts/`, `backups/`, IDE temp dirs — doesn't destabilize the gate.
ALLOWED_TOP_LEVEL_DIRS = {
    "server",
    "app",
    "schema",
    "tests",
    "docs",
    "deploy",
    "scratch",  # gitignored; tolerated if present during local work
    "planner",  # reserved for the upstream Claude CLI; may not exist yet
}

MAX_TOP_LEVEL_DIRS = 8


def _top_level_dirs() -> set[str]:
    """Return tracked top-level directories only.

    Two-stage filter:
    1. Enumerate directories under the repo root (ignoring dotfiles).
    2. Use `git check-ignore` to drop anything in `.gitignore`. The rule
       this test enforces is about *tracked* architectural shape — local
       cruft (editor snapshots, `backups/` from `make db-backup`, one-off
       `scripts/`) is fine as long as gitignore already knows about it.

    Falls back to "include all non-dotfile dirs" if git isn't available,
    so the test still runs in minimal environments.
    """
    candidates = [p for p in REPO_ROOT.iterdir() if p.is_dir() and not p.name.startswith(".")]
    if not candidates:
        return set()

    try:
        # `git check-ignore` returns 0 if any path is ignored, 1 if none are,
        # 128 on error. We pass every candidate and collect stdout — each
        # line is a path that IS ignored.
        result = subprocess.run(
            ["git", "-C", str(REPO_ROOT), "check-ignore", "--stdin"],
            input="\n".join(str(p.relative_to(REPO_ROOT)) for p in candidates),
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode not in (0, 1):
            # Error, not "some / none matched" — fall back.
            return {p.name for p in candidates}
        ignored_names = {
            line.strip().rstrip("/").split("/")[0]
            for line in result.stdout.splitlines()
            if line.strip()
        }
        return {p.name for p in candidates if p.name not in ignored_names}
    except FileNotFoundError:
        # No git binary — fall back to the full set.
        return {p.name for p in candidates}


def test_top_level_dir_count_is_bounded() -> None:
    dirs = _top_level_dirs()
    assert len(dirs) <= MAX_TOP_LEVEL_DIRS, (
        f"Repo root has {len(dirs)} top-level directories; cap is {MAX_TOP_LEVEL_DIRS}. "
        f"Found: {sorted(dirs)}. Either merge a concern, extract to a sibling repo, "
        f"or land an ADR explaining the 9th slot. "
        f"See docs/architecture/fitness-functions.md § FF-4."
    )


def test_top_level_dirs_are_all_sanctioned() -> None:
    dirs = _top_level_dirs()
    unexpected = dirs - ALLOWED_TOP_LEVEL_DIRS
    assert not unexpected, (
        f"Unexpected top-level directories: {sorted(unexpected)}. "
        f"Either add to ALLOWED_TOP_LEVEL_DIRS with an accompanying ADR "
        f"(docs/decisions/ADR-YYYY-MM-DD-{{slug}}.md), add to .gitignore if ephemeral, "
        f"or remove. See docs/architecture/fitness-functions.md § FF-4."
    )
