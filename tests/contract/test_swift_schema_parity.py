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
_PRIMITIVE_FILE = _SCHEMA_ROOT / "Sources" / "WorkoutDBSchema" / "PrimitiveEntities.swift"


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


@pytest.fixture(scope="module")
def primitive_swift_source() -> str:
    assert _PRIMITIVE_FILE.exists(), f"{_PRIMITIVE_FILE} missing"
    return _PRIMITIVE_FILE.read_text()


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
        "accumulate",
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


def test_set_log_side_parity(swift_source: str) -> None:
    swift = _extract_enum_cases(swift_source, "SetLogSide")
    assert swift == {"left", "right", "bilateral"}


def test_user_parameter_source_parity(swift_source: str) -> None:
    swift = _extract_enum_cases(swift_source, "UserParameterSource")
    assert swift == {"claude", "app_log", "manual"}


def test_primitive_timing_mode_parity(primitive_swift_source: str) -> None:
    swift = _extract_enum_cases(primitive_swift_source, "PrimitiveTimingMode")
    assert swift == {"set_bounded", "time_bounded", "cap_bounded", "target_bounded"}


def test_primitive_traversal_parity(primitive_swift_source: str) -> None:
    swift = _extract_enum_cases(primitive_swift_source, "PrimitiveTraversal")
    assert swift == {"sequential", "round_robin", "amrap"}


def test_primitive_metric_parity(primitive_swift_source: str) -> None:
    swift = _extract_enum_cases(primitive_swift_source, "PrimitiveMetric")
    assert swift == {"reps", "duration", "distance", "rounds", "completion", "load_carried"}


def test_primitive_value_form_parity(primitive_swift_source: str) -> None:
    swift = _extract_enum_cases(primitive_swift_source, "PrimitiveValueForm")
    assert swift == {"single", "range", "open"}


def test_primitive_work_role_parity(primitive_swift_source: str) -> None:
    swift = _extract_enum_cases(primitive_swift_source, "PrimitiveWorkRole")
    assert swift == {"completion", "observation"}


def test_primitive_load_unit_parity(primitive_swift_source: str) -> None:
    swift = _extract_enum_cases(primitive_swift_source, "PrimitiveLoadUnit")
    assert swift == {"kg", "lb", "1rm", "bodyweight"}


def test_primitive_load_unit_type_parity(primitive_swift_source: str) -> None:
    swift = _extract_enum_cases(primitive_swift_source, "PrimitiveLoadUnitType")
    assert swift == {"absolute", "relative", "implicit_bodyweight"}


def test_primitive_stimulus_type_parity(primitive_swift_source: str) -> None:
    swift = _extract_enum_cases(primitive_swift_source, "PrimitiveStimulusType")
    assert swift == {"rir", "hr_zone"}


def test_activity_domain_parity(primitive_swift_source: str) -> None:
    swift = _extract_enum_cases(primitive_swift_source, "ActivityDomain")
    assert swift == {
        "running",
        "cycling",
        "rowing",
        "swimming",
        "walking",
        "hiking",
        "functional_strength",
        "traditional_strength",
        "hiit",
        "mobility",
        "mixed_modal",
        "carry",
        "other",
    }


def test_activity_environment_parity(primitive_swift_source: str) -> None:
    swift = _extract_enum_cases(primitive_swift_source, "ActivityEnvironment")
    assert swift == {"indoor", "outdoor", "unspecified"}


def test_activity_preservation_policy_parity(primitive_swift_source: str) -> None:
    swift = _extract_enum_cases(primitive_swift_source, "ActivityPreservationPolicy")
    assert swift == {
        "preserve_primary_activity",
        "preserve_structure",
        "preserve_elapsed_time",
        "preserve_distance",
        "preserve_mixed_modality",
    }


def test_primitive_log_role_parity(primitive_swift_source: str) -> None:
    swift = _extract_enum_cases(primitive_swift_source, "PrimitiveLogRole")
    assert swift == {"slot", "set_result", "block_result"}


def _has_xcode() -> bool:
    """Full Xcode (not just Command Line Tools) is required to run `swift test` on macOS.

    Swift Testing and XCTest ship their runtime dylibs only with Xcode. Plain CLT has
    the framework headers but the test bundle won't load at runtime.
    """
    result = subprocess.run(["xcode-select", "-p"], capture_output=True, text=True)
    if result.returncode != 0:
        return False
    path = result.stdout.strip()
    return path.endswith(".app/Contents/Developer") or "/Xcode" in path


def test_swift_package_healthy() -> None:
    """Defensive — if the Swift package itself is broken, it must fail the Python suite too.

    On machines with Xcode, run the Swift test suite (runtime validation of Codable
    round-trips and fixture decoding). On CLT-only machines, fall back to `swift build`
    which still catches compile-time drift in the DTOs. Skipped when swift is absent.
    """
    if subprocess.run(["which", "swift"], capture_output=True).returncode != 0:
        pytest.skip("swift CLI not available")

    command = ["swift", "test"] if _has_xcode() else ["swift", "build"]
    result = subprocess.run(
        command,
        cwd=_SCHEMA_ROOT,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"`{' '.join(command)}` failed in schema/:\n{result.stdout}\n{result.stderr}"
    )
