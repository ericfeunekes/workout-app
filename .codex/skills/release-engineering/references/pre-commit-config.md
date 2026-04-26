# Pre-Commit Configuration

Fast local quality gates before code leaves your machine.

## Installation

```bash
uv add --dev pre-commit
pre-commit install
```

## Configuration (.pre-commit-config.yaml)

```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.6.0
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format

  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.11.0
    hooks:
      - id: mypy
        args: [--strict]
        additional_dependencies: [types-all]

  - repo: local
    hooks:
      - id: fast-tests
        name: Fast unit tests
        entry: uv run pytest -m unit --maxfail=1 -x
        language: system
        pass_filenames: false
        always_run: true
```

## Time Budget

- Formatting: <2s
- Type checking: <5s
- Unit tests: <10s
- **Total target:** <20s

## Bypass (Emergencies Only)

```bash
git commit --no-verify -m "Emergency fix"
```

Document all bypasses in commit message.
