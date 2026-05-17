"""FF-7 · No RPE resurrection.

The RIR cutover (ADR-2026-04-17-rir-autoreg-sync) replaced RPE across the
production surface. Historical narration in ADRs and reference material in
the design bundle is allowed; nothing else is.

See docs/architecture/fitness-functions.md § FF-7.
"""

from __future__ import annotations

import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent

# Surfaces that must be RPE-free. Paths are relative to the repo root.
RPE_FREE_PATHS = [
    "server",
    "app",
    "schema",
    "docs/prescription.md",
    "docs/sync.md",
    "docs/specs/v2-architecture.md",
    "docs/ARCHITECTURE.md",
    "docs/open-questions.md",
    "app/README.md",
]

# Paths allowed to mention RPE (historical narration, reference bundle, this test).
ALLOWED_PATHS = {
    "docs/decisions",  # ADRs narrating why RPE was replaced
    "docs/design",  # reference-not-spec bundle
    "docs/specs/data-model-exploration.md",  # pre-decision exploration doc
    "tests/architecture/test_no_rpe.py",  # this file
    # Migrations are append-only historical records. 001 created the rpe column;
    # 004 drops it. Both legitimately reference rpe by name and cannot be rewritten.
    "server/db/migrations/001_initial.sql",
    "server/db/migrations/004_rir_cutover.sql",
    # SwiftLint rule whose entire purpose is to catch RPE leaks in app Swift
    # sources — it must mention RPE to forbid it.
    "app/.swiftlint.yml",
}

# Pattern matches RPE field names (rpe, rpe_target) and RPE as a scale label.
# Matches word-boundary RPE/rpe, specifically avoiding false positives like
# "grape" or "wrapper". Case-sensitive on RPE (acronym) or isolated 'rpe'.
_RPE_PATTERN = re.compile(r"\bRPE\b|\brpe\b|\brpe_target\b")

# Lines where RPE appears alongside RIR are explicitly contrasting the two
# (e.g., "RIR-only, no RPE" or "replaced RPE"). Prose docs are allowed to
# reference the rename so long as the line itself names RIR as the replacement.
# Code files never get this allowance — the rule is "no RPE in code, period."
_RIR_PATTERN = re.compile(r"\bRIR\b|\brir\b")

# Code paths are strict — no RPE at all, regardless of context.
CODE_PATH_PREFIXES = ("server/", "app/", "schema/")


def _is_allowed_path(path: Path) -> bool:
    rel = path.relative_to(REPO_ROOT).as_posix()
    return any(rel == allowed or rel.startswith(allowed + "/") for allowed in ALLOWED_PATHS)


def _scan(path: Path) -> list[tuple[str, int, str]]:
    """Return (file, line_no, line) for each RPE match in files under path."""
    hits: list[tuple[str, int, str]] = []
    target = REPO_ROOT / path
    if target.is_file():
        files = [target]
    elif target.is_dir():
        files = [
            p
            for p in target.rglob("*")
            if p.is_file()
            and p.suffix in {".py", ".swift", ".md", ".json", ".sql", ".toml", ".yml", ".yaml"}
            and "/__pycache__/" not in p.as_posix()
            and "/.build/" not in p.as_posix()
            and "/node_modules/" not in p.as_posix()
        ]
    else:
        return []

    for f in files:
        if _is_allowed_path(f):
            continue
        try:
            text = f.read_text()
        except (UnicodeDecodeError, PermissionError):
            continue
        rel = f.relative_to(REPO_ROOT).as_posix()
        is_code = any(rel.startswith(prefix) for prefix in CODE_PATH_PREFIXES)
        for lineno, line in enumerate(text.splitlines(), start=1):
            if not _RPE_PATTERN.search(line):
                continue
            # Docs get an allowance when the line explicitly names RIR —
            # a contrasting line like "RIR-only, no RPE" is valid prose.
            # Code files never get the allowance.
            if not is_code and _RIR_PATTERN.search(line):
                continue
            hits.append((rel, lineno, line.strip()))
    return hits


def test_no_rpe_in_production_surfaces() -> None:
    all_hits: list[tuple[str, int, str]] = []
    for target in RPE_FREE_PATHS:
        all_hits.extend(_scan(Path(target)))

    if all_hits:
        summary = "\n".join(f"  {f}:{ln}  {line[:120]}" for f, ln, line in all_hits[:30])
        overflow = f"\n  ... and {len(all_hits) - 30} more" if len(all_hits) > 30 else ""
        raise AssertionError(
            "RPE references found outside the allowed historical/reference surfaces. "
            "The system is RIR-only per ADR-2026-04-17-rir-autoreg-sync. "
            f"Either: (a) remove the reference, (b) move to docs/decisions/ as narration, "
            f"or (c) add the path to ALLOWED_PATHS with a justifying comment.\n"
            f"Violations ({len(all_hits)}):\n{summary}{overflow}"
        )
