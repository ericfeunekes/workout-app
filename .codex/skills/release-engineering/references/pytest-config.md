# pytest Configuration

See `scratch/python-testing.md` for comprehensive pytest patterns including:
- Markers and profiles
- Conftest plugins
- Parallel execution
- Coverage configuration

## Quick Start

```toml
# pyproject.toml
[tool.pytest.ini_options]
testpaths = ["tests"]
python_files = ["test_*.py"]
addopts = [
    "-v",
    "--strict-markers",
    "--tb=short",
    "-n", "auto",
    "--testmon",
    "--cov=app",
    "--cov-report=term-missing",
    "--cov-fail-under=80",
]

markers = [
    "unit: Fast unit tests",
    "integration: Integration tests",
    "e2e: End-to-end tests",
    "slow: Tests taking >5s",
    "quarantine: Flaky tests",
]
```
