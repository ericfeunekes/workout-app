"""
Pytest configuration with profiles, auto-marking, and test helpers.

Provides:
1) Profile system (--profile) with marker expressions
2) Auto-marking plugin (fixtures -> dependency markers; path -> stack markers)
3) Golden file helper
4) Network blocking (toggle via env; per-test override)
5) Budget decorator (time/memory)
6) Marker fallback registration when pytest.ini is absent
"""

import functools
import os
import time
from pathlib import Path

import pytest

# ============================================================================
# Profile System
# ============================================================================

PROFILE_MARKEXPR = {
    "fast": "(unit or component) and not perf",
    "pr": "(unit or component or behavior) and not (integration or e2e)",
    "nightly": "",  # All tests
    "agents": "agents",
    "api": "api",
    "pipelines": "pipelines",
}


def pytest_addoption(parser):
    parser.addoption(
        "--profile",
        action="store",
        default=None,
        help="Test profile to run: fast, pr, nightly, agents, api, pipelines",
    )


def pytest_configure(config):
    # Fallback: register markers if pytest.ini not loaded
    marker_lines = [
        # Scope
        "unit: Pure function tests with no I/O",
        "component: Single component with faked dependencies (hermetic)",
        "behavior: Public interface / contract tests (may use recorded I/O)",
        "integration: Real dependencies via containers or local services",
        "e2e: End-to-end in staging-like environment",
        # Risk
        "p0: Critical path (deployment blocking)",
        "p1: Important functionality",
        "p2: Nice-to-have",
        # Capability
        "perf: Performance / resource budgets",
        "security: Authentication/authorization/input validation",
        "migration: Schema/data migrations",
        "dq: Data quality assertions",
        "property: Property-based testing",
        "golden: Snapshot/golden tests",
        "recorded: Uses VCR/recorded HTTP",
        "requires_runtime_tokens: Requires short-lived runtime tokens",
        # Stack
        "agents: LangGraph/LLM agents",
        "api: FastAPI / HTTP APIs",
        "pipelines: Data pipelines / ETL",
        # Dependencies
        "db: Uses database",
        "redis: Uses Redis",
        "s3: Uses object storage",
        "kafka: Uses Kafka",
        "spark: Uses Spark",
        "network: Uses network",
        "docker: Uses Docker/Testcontainers",
    ]
    for line in marker_lines:
        config.addinivalue_line("markers", line)

    # Handle --profile, or treat -m <profile> as alias
    profile = config.getoption("--profile", default=None)
    if profile:
        if profile not in PROFILE_MARKEXPR:
            raise ValueError(
                f"Unknown profile: {profile}. Valid: {', '.join(PROFILE_MARKEXPR.keys())}"
            )
        config.option.markexpr = PROFILE_MARKEXPR[profile]
    else:
        markexpr = config.getoption("-m", default="")
        if markexpr in PROFILE_MARKEXPR:
            config.option.markexpr = PROFILE_MARKEXPR[markexpr]


# ============================================================================
# Auto-Marking Plugin
# ============================================================================

FIXTURE_TO_MARKER = {
    # Database fixtures
    "db": "db",
    "database": "db",
    "postgres": "db",
    "postgresql": "db",
    "mysql": "db",
    "duckdb": "db",
    "duckdb_conn": "db",
    # Cache fixtures
    "redis": "redis",
    "redis_client": "redis",
    "cache": "redis",
    # Storage fixtures
    "s3": "s3",
    "s3_client": "s3",
    "storage": "s3",
    # Messaging fixtures
    "kafka": "kafka",
    "kafka_producer": "kafka",
    "kafka_consumer": "kafka",
    # Processing fixtures
    "spark": "spark",
    "spark_session": "spark",
    # Network fixtures
    "requests_session": "network",
    "http_client": "network",
    # Container fixtures
    "postgres_container": "docker",
    "redis_container": "docker",
    "mongo_container": "docker",
}

PATH_TO_STACK = {"agents": "agents", "api": "api", "pipelines": "pipelines"}


def pytest_collection_modifyitems(config, items):
    for item in items:
        # Fixture-based dependency markers
        if hasattr(item, "fixturenames"):
            for fixture_name in item.fixturenames:
                if fixture_name in FIXTURE_TO_MARKER:
                    item.add_marker(getattr(pytest.mark, FIXTURE_TO_MARKER[fixture_name]))

            # Integration + docker if container fixtures used
            container_fixtures = [n for n in item.fixturenames if "container" in n.lower()]
            if container_fixtures:
                item.add_marker(pytest.mark.integration)
                item.add_marker(pytest.mark.docker)

        # Path-based stack markers
        test_path = str(item.fspath)
        for segment, stack_marker in PATH_TO_STACK.items():
            if f"/{segment}/" in test_path or f"/test_{segment}" in test_path:
                item.add_marker(getattr(pytest.mark, stack_marker))


# ============================================================================
# Golden File Helper
# ============================================================================


class GoldenHelper:
    def __init__(self, test_name: str, golden_dir: Path):
        self.test_name = test_name
        self.golden_dir = golden_dir
        self.golden_dir.mkdir(parents=True, exist_ok=True)

    def assert_match(self, content: str, filename: str):
        golden_path = self.golden_dir / filename
        normalized = content.rstrip() + "\n"

        if os.getenv("UPDATE_GOLDEN"):
            golden_path.write_text(normalized)
            return

        if not golden_path.exists():
            golden_path.write_text(normalized)
            pytest.skip(f"Created golden file: {golden_path}")
            return

        expected = golden_path.read_text()
        if normalized != expected:
            import difflib

            diff = difflib.unified_diff(
                expected.splitlines(keepends=True),
                normalized.splitlines(keepends=True),
                fromfile=str(golden_path),
                tofile="actual",
            )
            pytest.fail(
                f"Content doesn't match golden file: {golden_path}\n\n{''.join(diff)}\n\n"
                f"To update: UPDATE_GOLDEN=1 pytest {self.test_name}"
            )


@pytest.fixture
def golden(request):
    test_name = request.node.name
    test_dir = Path(request.fspath).parent
    golden_dir = test_dir / "golden"
    return GoldenHelper(test_name, golden_dir)


# ============================================================================
# Network Blocking (toggle + per-test override)
# ============================================================================

BLOCK_NET = os.getenv("BLOCK_TEST_NETWORK", "1") != "0"
_original_socket = None


@pytest.fixture(scope="session", autouse=True)
def block_network():
    """Block network by default unless BLOCK_TEST_NETWORK=0."""
    if not BLOCK_NET:
        return
    import socket

    global _original_socket
    _original_socket = socket.socket

    def guarded_socket(*args, **kwargs):
        raise RuntimeError(
            "Network blocked. Mark test with @pytest.mark.network or set BLOCK_TEST_NETWORK=0."
        )

    socket.socket = guarded_socket
    yield
    socket.socket = _original_socket


@pytest.fixture
def allow_network():
    """Temporarily allow network for this test."""
    if not BLOCK_NET:
        yield
        return
    import socket

    global _original_socket
    socket.socket = _original_socket
    try:
        yield
    finally:
        # Re-block after this test
        def guarded_socket(*args, **kwargs):
            raise RuntimeError(
                "Network blocked. Mark test with @pytest.mark.network or set BLOCK_TEST_NETWORK=0."
            )

        socket.socket = guarded_socket


# ============================================================================
# VCR Fixture for HTTP Recording
# ============================================================================


@pytest.fixture
def vcr_config():
    """Default VCR configuration."""
    return {
        "filter_headers": ["authorization", "x-api-key"],
        "record_mode": "once",
        "match_on": ["method", "scheme", "host", "port", "path", "query"],
        "cassette_library_dir": "examples/cassettes",
    }


@pytest.fixture
def vcr_cassette(request, vcr_config):
    """Auto-name cassettes by test name and record/replay HTTP."""
    cassette_name = f"{request.node.name}.yaml"
    import vcr

    with vcr.VCR(**vcr_config).use_cassette(cassette_name):
        yield


# ============================================================================
# Budget Decorator
# ============================================================================


def budget(max_time_ms: int | None = None, max_memory_mb: int | None = None):
    def decorator(func):
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            import tracemalloc

            start_time = time.perf_counter()
            tracemalloc.start()
            try:
                return func(*args, **kwargs)
            finally:
                elapsed_ms = (time.perf_counter() - start_time) * 1000
                current, peak = tracemalloc.get_traced_memory()
                tracemalloc.stop()
                peak_mb = peak / 1024 / 1024
                if max_time_ms and elapsed_ms > max_time_ms:
                    pytest.fail(f"Time budget exceeded: {elapsed_ms:.1f}ms > {max_time_ms}ms")
                if max_memory_mb and peak_mb > max_memory_mb:
                    pytest.fail(f"Memory budget exceeded: {peak_mb:.1f}MB > {max_memory_mb}MB")

        return wrapper

    return decorator
