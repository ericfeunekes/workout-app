"""Contract test: Swift enum values in schema/ match the server's authoritative lists.

Parses Swift source files to extract enum raw values, then compares against the server's
Literal types and SQL CHECK constraints. Light-touch (regex-based) rather than a full Swift
parse — sufficient because enum definitions are well-structured in this repo.
"""

import re
import subprocess
from pathlib import Path

import pytest

_SCHEMA_ROOT = Path(__file__).resolve().parents[2] / "schema"
_ENUMS_FILE = _SCHEMA_ROOT / "Sources" / "WorkoutDBSchema" / "Enums.swift"


def _extract_enum_cases(swift_source: str, enum_name: str) -> set[str]:
    """Extract the raw-value set of a Swift `enum X: String` declaration."""
    enum_pattern = re.compile(
        rf"public enum {enum_name}[^{{]*\{{([^}}]+)\}}",
        re.DOTALL,
    )
    match = enum_pattern.search(swift_source)
    assert match, f"Could not find enum {enum_name} in Swift source"
    body = match.group(1)

    # Match cases in both forms:
    #   case foo           — raw value defaults to "foo"
    #   case bar = "baz"   — explicit raw value "baz"
    values: set[str] = set()
    for line in body.splitlines():
        line = line.strip()
        if not line.startswith("case "):
            continue
        name_and_value = line[5:].split("//")[0].strip().rstrip(",")
        if "=" in name_and_value:
            _, raw = name_and_value.split("=", 1)
            values.add(raw.strip().strip('"'))
        else:
            values.add(name_and_value)
    return values


@pytest.fixture(scope="module")
def swift_source() -> str:
    assert _ENUMS_FILE.exists(), f"{_ENUMS_FILE} missing"
    return _ENUMS_FILE.read_text()


def test_timing_mode_parity(swift_source: str) -> None:
    swift = _extract_enum_cases(swift_source, "TimingMode")
    expected = {
        "straight_sets",
        "superset",
        "circuit",
        "emom",
        "amrap",
        "for_time",
        "intervals",
        "tabata",
        "continuous",
        "custom",
        "rest",
    }
    assert swift == expected, f"TimingMode drift: swift={swift}, expected={expected}"


def test_workout_status_parity(swift_source: str) -> None:
    swift = _extract_enum_cases(swift_source, "WorkoutStatus")
    assert swift == {"planned", "active", "completed", "skipped"}


def test_workout_source_parity(swift_source: str) -> None:
    swift = _extract_enum_cases(swift_source, "WorkoutSource")
    assert swift == {"claude", "manual"}


def test_weight_unit_parity(swift_source: str) -> None:
    swift = _extract_enum_cases(swift_source, "WeightUnit")
    assert swift == {"kg", "lb"}


def test_user_parameter_source_parity(swift_source: str) -> None:
    swift = _extract_enum_cases(swift_source, "UserParameterSource")
    assert swift == {"claude", "app_log", "manual"}


def test_swift_tests_pass() -> None:
    """Defensive — if the Swift package itself is broken, it must fail the Python suite too.

    This makes `pytest` a one-stop signal: green pytest = server AND schema package healthy.
    Skipped when swift is unavailable (e.g., non-macOS CI).
    """
    if subprocess.run(["which", "swift"], capture_output=True).returncode != 0:
        pytest.skip("swift CLI not available")

    result = subprocess.run(
        ["swift", "test"],
        cwd=_SCHEMA_ROOT,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert (
        result.returncode == 0
    ), f"`swift test` failed in schema/:\n{result.stdout}\n{result.stderr}"
