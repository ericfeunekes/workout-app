"""FF-5 · ADR index parity.

Every file in docs/decisions/ must be referenced in docs/AGENTS.md.
Every ADR referenced in docs/AGENTS.md must exist on disk. No orphans.

See docs/architecture/fitness-functions.md § FF-5.
"""

from __future__ import annotations

import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
DECISIONS_DIR = REPO_ROOT / "docs" / "decisions"
NAVIGATOR = REPO_ROOT / "docs" / "AGENTS.md"

_ADR_FILENAME_RE = re.compile(r"ADR-\d{4}-\d{2}-\d{2}-[a-z0-9-]+\.md")


def _adr_files() -> set[str]:
    return {p.name for p in DECISIONS_DIR.iterdir() if _ADR_FILENAME_RE.fullmatch(p.name)}


def _adrs_referenced_in_navigator() -> set[str]:
    text = NAVIGATOR.read_text()
    return set(_ADR_FILENAME_RE.findall(text))


def test_every_adr_on_disk_is_listed_in_navigator() -> None:
    on_disk = _adr_files()
    listed = _adrs_referenced_in_navigator()
    missing = on_disk - listed
    assert not missing, (
        f"ADRs exist on disk but aren't referenced in docs/AGENTS.md: {sorted(missing)}. "
        f"Add a bullet to the 'decisions/' entry in docs/AGENTS.md so the ADR is discoverable."
    )


def test_every_adr_in_navigator_exists_on_disk() -> None:
    on_disk = _adr_files()
    listed = _adrs_referenced_in_navigator()
    phantom = listed - on_disk
    assert not phantom, (
        f"docs/AGENTS.md references ADRs that don't exist on disk: {sorted(phantom)}. "
        f"Either create the ADR or remove the reference."
    )
