# GitHub Actions Templates

See `frontend-dev/frontend-contract-first-development/references/ci-cd-integration.md` for comprehensive workflow examples.

## Complete PR Validation Workflow

```yaml
name: PR Validation
on: [pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install uv
        uses: astral-sh/setup-uv@v3

      - name: Install dependencies
        run: uv sync

      - name: Lint
        run: uv run ruff check .

      - name: Type check
        run: uv run mypy app/

      - name: Run tests
        run: uv run pytest --testmon -n auto -m "not slow" --cov=app --cov-report=xml

      - name: Check diff coverage
        run: uv run diff-cover coverage.xml --fail-under=90

      - name: Security scan
        run: uv run bandit -r app/
```
