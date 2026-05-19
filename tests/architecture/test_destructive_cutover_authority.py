from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SERVER_OWNED_CLEAR_SYMBOLS = (
    "workoutCache.clear(",
    "lastPerformedStore.clear(",
    "pushQueueStore.clear(",
    "syncMetadataStore.clearLastSyncAt(",
    "tokenStore.clear(",
    "authRecoveryStore.clearTokenRejected(",
)
DESTRUCTIVE_CUTOVER_DOCS = (
    "AGENTS.md",
    "docs/MIGRATIONS.md",
    "docs/WORKFLOW.md",
    "docs/specs/primitives-data-model.md",
    "docs/specs/primitives-data-model/cutover.md",
)
FORBIDDEN_PRESERVATION_CLAIMS = (
    "must preserve current local/server QA workout data",
    "preserve old primitive QA data",
    "migrate old primitive QA data",
    "keep legacy primitive authoring accepted",
    "fallback to legacy primitive authoring",
)


def test_migrations_doc_is_destructive_cutover_authority() -> None:
    migrations = (REPO_ROOT / "docs" / "MIGRATIONS.md").read_text()
    workflow = (REPO_ROOT / "docs" / "WORKFLOW.md").read_text()
    agents = (REPO_ROOT / "AGENTS.md").read_text()

    assert "## Destructive cutover exception" in migrations
    assert "destructive cutover exception" in workflow
    assert "destructive cutover exception" in agents


def test_destructive_cutover_docs_do_not_claim_legacy_preservation() -> None:
    violations: list[str] = []
    for relative in DESTRUCTIVE_CUTOVER_DOCS:
        text = (REPO_ROOT / relative).read_text().lower()
        for phrase in FORBIDDEN_PRESERVATION_CLAIMS:
            if phrase in text:
                violations.append(f"{relative}: {phrase}")

    assert not violations, (
        "Destructive cutover docs must not reintroduce legacy preservation "
        "requirements for disposable QA data:\n" + "\n".join(violations)
    )


def test_production_server_owned_reset_callers_use_reset_policy() -> None:
    allowed = "app/Packages/Shell/Sources/Shell/AppSyncLocalStateReset.swift"
    violations: list[str] = []
    for path in (REPO_ROOT / "app").rglob("*.swift"):
        relative = path.relative_to(REPO_ROOT).as_posix()
        if relative == allowed or "/Tests/" in relative:
            continue
        text = path.read_text()
        for symbol in SERVER_OWNED_CLEAR_SYMBOLS:
            if symbol in text:
                violations.append(f"{relative}: {symbol}")

    assert not violations, (
        "Production code must clear coupled server-owned local state through "
        "AppSyncLocalStateReset, not by clearing individual stores:\n" + "\n".join(violations)
    )


def test_primitive_cutover_does_not_reopen_pdm_gap_005() -> None:
    gap_map = (REPO_ROOT / "docs" / "feature-gap-map.md").read_text()
    cutover = (REPO_ROOT / "docs" / "specs" / "primitives-data-model" / "cutover.md").read_text()

    assert "PDM-GAP-005" not in gap_map
    assert "PDM-GAP-005` is closed" in cutover
