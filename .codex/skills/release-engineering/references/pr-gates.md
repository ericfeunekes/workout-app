# Pull Request Gates

See `frontend-dev/frontend-contract-first-development/references/ci-cd-integration.md` for comprehensive CI/CD integration patterns.

Additional PR gate configurations:

## Diff Coverage Gate

```yaml
# .github/workflows/pr-tests.yml
- name: Run tests with coverage
  run: |
    uv run pytest --cov=app --cov-report=xml

- name: Check diff coverage
  run: |
    uv run diff-cover coverage.xml --fail-under=90
```

## Breaking Change Detection

See `breaking-changes.md` for OpenAPI diff checking and database migration safety.

## Security Scanning

```yaml
- name: Security scan
  run: |
    uv run bandit -r app/
    npm audit --audit-level=high
```
