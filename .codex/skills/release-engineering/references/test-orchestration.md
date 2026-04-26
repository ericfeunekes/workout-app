# Test Orchestration

Multi-tier test coordination with parallelism, change-based selection, and flake management.

## Change-Based Test Selection

Run only tests affected by code changes for faster feedback loops.

### Python (pytest-testmon)

**Install:**
```bash
uv add --dev pytest-testmon
```

**Usage:**
```bash
# First run: establishes baseline
pytest --testmon

# Subsequent runs: only affected tests
pytest --testmon

# Force full run
pytest --testmon-noselect
```

**Configuration in pyproject.toml:**
```toml
[tool.pytest.ini_options]
addopts = ["--testmon"]  # Enable by default
```

**CI Integration:**
```yaml
# GitHub Actions
- name: Run affected tests
  run: pytest --testmon --testmon-nocache

# Always run full suite on main
- name: Run all tests
  if: github.ref == 'refs/heads/main'
  run: pytest --testmon-noselect
```

### JavaScript (Jest)

**Usage:**
```bash
# Watch mode with change detection
jest --watch --onlyChanged

# CI: only changed files
jest --onlyChanged --bail --coverage
```

**Configuration:**
```javascript
// jest.config.js
module.exports = {
  collectCoverageFrom: ['src/**/*.{js,jsx,ts,tsx}'],
  coveragePathIgnorePatterns: ['/node_modules/', '/dist/'],
  onlyChanged: process.env.CI === 'true',
};
```

## Parallel Test Execution

### Python (pytest-xdist)

**Install:**
```bash
uv add --dev pytest-xdist
```

**Basic usage:**
```bash
# Auto-detect CPU count
pytest -n auto

# Specific worker count
pytest -n 4

# Load balancing mode (default)
pytest -n auto --dist loadscope
```

**Advanced configuration:**
```toml
[tool.pytest.ini_options]
addopts = [
    "-n", "auto",  # Parallel by default
    "--dist", "loadscope",  # Balance by test scope
]

# Markers for serial execution
markers = [
    "serial: Run test serially (not in parallel)",
    "integration: Integration test (limit parallelism)",
]
```

**Controlling parallelism by test type:**
```python
# conftest.py
def pytest_collection_modifyitems(config, items):
    """Limit integration test parallelism."""
    for item in items:
        if "integration" in item.keywords:
            # Limit to 2 workers for integration tests
            item.add_marker(pytest.mark.xdist_group(name="integration"))
```

**Coverage with parallel execution:**
```bash
# Combine coverage from all workers
pytest -n auto --cov=app --cov-report=term-missing
```

### JavaScript (Jest)

**Configuration:**
```javascript
// jest.config.js
module.exports = {
  maxWorkers: process.env.CI ? 2 : '50%',  // Limit in CI
  testTimeout: 10000,  // 10s timeout per test
};
```

## Test Profiling & Performance

### Find Slow Tests

**pytest:**
```bash
# Show 10 slowest tests
pytest --durations=10

# Show all tests taking >1s
pytest --durations=0 --durations-min=1.0
```

**Jest:**
```bash
# Verbose timing
jest --verbose --testTimeout=5000
```

### Performance Budgets

**Per-test budgets:**
```python
import pytest
import time

@pytest.mark.perf_budget(seconds=0.5)
def test_fast_operation():
    start = time.perf_counter()
    result = expensive_operation()
    duration = time.perf_counter() - start
    assert duration < 0.5, f"Took {duration:.3f}s, budget 0.5s"
```

**Suite-level budgets:**
```yaml
# GitHub Actions
- name: Run tests with timeout
  run: pytest --timeout=300  # 5 min max
  timeout-minutes: 6  # Kill after 6 min
```

## Flake Management

### Automatic Flake Detection

**Strategy:**
1. Test fails → Re-run 3 times
2. If passes on retry → Mark as flaky
3. Report but don't fail build
4. Track flake rate over time

**pytest plugin (conftest.py):**
```python
import pytest

def pytest_runtest_makereport(item, call):
    """Detect and mark flaky tests."""
    if call.excinfo is not None and call.when == "call":
        # Test failed, check if it's flaky
        if not hasattr(item, "_flake_count"):
            item._flake_count = 0
        item._flake_count += 1

        if item._flake_count < 3:
            # Retry up to 3 times
            pytest.xfail(f"Flaky test (attempt {item._flake_count})")

@pytest.fixture(autouse=True)
def track_flakes(request):
    """Track flake rate."""
    if hasattr(request.node, "_flake_count") and request.node._flake_count > 1:
        # Log flaky test for metrics
        print(f"FLAKY: {request.node.nodeid} (retries: {request.node._flake_count})")
```

**pytest-flakefinder:**
```bash
# Run tests multiple times to find flakes
uv add --dev pytest-flakefinder
pytest --flake-finder --flake-runs=10
```

### Quarantine Flaky Tests

**Mark quarantined tests:**
```python
@pytest.mark.quarantine(reason="Flaky due to timing, ticket #123")
def test_flaky_operation():
    pass
```

**Skip quarantined in CI:**
```toml
[tool.pytest.ini_options]
addopts = [
    "-m", "not quarantine",  # Skip quarantined by default
]

markers = [
    "quarantine: Flaky test quarantined until fixed",
]
```

**Allow running quarantined locally:**
```bash
# Run quarantined tests to debug
pytest -m quarantine

# Run everything including quarantined
pytest -m ""
```

## Test Organization by Speed

### Marker-Based Profiles

**pytest.ini:**
```ini
[pytest]
markers =
    unit: Fast unit tests (<1s each)
    integration: Integration tests with external deps
    e2e: End-to-end tests
    slow: Tests taking >5s
```

**Run by profile:**
```bash
# Pre-commit: only unit tests
pytest -m unit

# PR: unit + integration
pytest -m "unit or integration"

# Nightly: everything
pytest
```

**GitHub Actions matrix:**
```yaml
strategy:
  matrix:
    test-type: [unit, integration, e2e]
steps:
  - name: Run ${{ matrix.test-type }} tests
    run: pytest -m ${{ matrix.test-type }}
```

## CI/CD Integration Patterns

### PR Validation
```yaml
name: PR Tests
on: [pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Need history for testmon

      - name: Install dependencies
        run: uv sync

      - name: Run affected tests
        run: uv run pytest --testmon -n auto -m "not slow"

      - name: Check coverage
        run: uv run diff-cover coverage.xml --fail-under=90
```

### Nightly Full Suite
```yaml
name: Nightly Tests
on:
  schedule:
    - cron: '0 2 * * *'  # 2 AM daily

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Run full test suite
        run: uv run pytest --testmon-noselect -n auto

      - name: Run flake finder
        run: uv run pytest --flake-finder --flake-runs=5

      - name: Upload results
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: test-results/
```

## Performance Optimization Checklist

- [ ] Enable parallel execution (pytest-xdist, Jest workers)
- [ ] Implement change-based selection (testmon, --onlyChanged)
- [ ] Profile test suite to identify slow tests
- [ ] Move slow tests to integration/nightly tiers
- [ ] Use test fixtures effectively (scope=session for expensive setup)
- [ ] Mock external services (no real network calls in unit tests)
- [ ] Use in-memory databases for unit tests (SQLite :memory:)
- [ ] Implement test data factories (avoid fixture bloat)
- [ ] Set appropriate timeouts (fail fast on hangs)
- [ ] Clean up resources properly (avoid test pollution)
- [ ] Monitor test duration trends (alert on regressions)
- [ ] Quarantine flaky tests immediately
