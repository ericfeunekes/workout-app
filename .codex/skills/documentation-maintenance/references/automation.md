# Automation And Quality Gates

Use these scripts and workflows to keep docs trustworthy.

## Local Checks

1. Run `uv run python scripts/check_docs.py` to enforce front matter, freshness, file size, and secret scanning across `docs/`.
2. Run `uv run python scripts/check_readmes.py` to ensure required leaf folders carry a `README.md` and that the root README links into `docs/`.
3. Use `uv run python scripts/should_make_doc.py` when deciding whether a topic needs a new page or folder.

## GitHub Workflow

Configure `.github/workflows/docs.yml`:

```yaml
name: Docs checks
on: [push, pull_request]
jobs:
  docs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run docs checks
        run: |
          uv run python scripts/check_docs.py
          uv run python scripts/check_readmes.py
```

## Ownership

- Add CODEOWNERS entries for each doc subtree (`docs/runbooks/*`, `docs/features/*`, etc.) so reviewers with domain context respond quickly.
- List maintainers in `docs/MAINTAINERS.md` when teams need human escalation routes.

## Review Cadence

- Schedule a quarterly doc review; fail CI if `last_reviewed` breaches 90 days on `docs/index.md`, `docs/runbooks/incident-response.md`, and `docs/infra/environments.md`.
- Track doc freshness in engineering metrics dashboards.
