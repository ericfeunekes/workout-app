from __future__ import annotations

import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
WORKOUTKIT_IMPORT = re.compile(r"^\s*import\s+WorkoutKit\s*$", re.MULTILINE)
FORBIDDEN_ADAPTER_BYPASS_SYMBOLS = (
    "WorkoutKitDiagnosticProbeRunner",
    "WorkoutKitPlanFactory",
    "LiveWorkoutKitSchedulingClient",
    "WorkoutKitSchedulingClient",
    "WorkoutKitPlanDescriptor",
)
FORBIDDEN_HEALTHKIT_DATA_ACCESS_SYMBOLS = (
    "HKHealthStore",
    "HKSampleQuery",
    "HKAnchoredObjectQuery",
    "HKLiveWorkoutBuilder",
    "HKWorkoutConfiguration",
    "authorizationStatus",
)
FORBIDDEN_TARGET_SPECIFIC_SOURCE_FACT_SYMBOLS = (
    "workoutkit_",
    "WorkoutKit",
    "healthkit_",
    "HealthKit",
    "strava_",
    "Strava",
    "apple_workout",
    "appleWorkout",
)


def _swift_files(root: Path) -> list[Path]:
    return [path for path in root.rglob("*.swift") if "/.build/" not in path.as_posix()]


def test_shell_targets_do_not_import_workoutkit_export_profile() -> None:
    """The app/watch shells trigger diagnostics; adapter owns export-plan fixtures."""

    roots = [
        REPO_ROOT / "app" / "WorkoutDB",
        REPO_ROOT / "app" / "WorkoutDBWatch",
    ]
    violations: list[str] = []
    for root in roots:
        for path in _swift_files(root):
            text = path.read_text()
            if "import WorkoutKitExportProfile" in text:
                violations.append(path.relative_to(REPO_ROOT).as_posix())

    assert not violations, (
        "Shell targets must not import WorkoutKitExportProfile directly. "
        "Move diagnostic fixtures or target-side translation into WorkoutKitAdapter:\n"
        + "\n".join(violations)
    )


def test_workoutkit_imports_stay_inside_adapter_package() -> None:
    """WorkoutKit side effects live in WorkoutKitAdapter, not feature/shell code."""

    allowed_prefix = "app/Packages/WorkoutKitAdapter/"
    violations: list[str] = []
    for path in _swift_files(REPO_ROOT / "app"):
        rel = path.relative_to(REPO_ROOT).as_posix()
        if rel.startswith(allowed_prefix):
            continue
        text = path.read_text()
        if WORKOUTKIT_IMPORT.search(text):
            violations.append(rel)

    assert not violations, (
        "WorkoutKit imports are only allowed inside app/Packages/WorkoutKitAdapter:\n"
        + "\n".join(violations)
    )


def test_shell_and_features_do_not_call_raw_workoutkit_adapter_bypasses() -> None:
    """Product callers use the coordinator/facade, not raw clients or descriptors."""

    allowed_prefixes = (
        "app/Packages/WorkoutKitAdapter/",
        "app/Packages/ExportProfile/",
    )
    violations: list[str] = []
    for path in _swift_files(REPO_ROOT / "app"):
        rel = path.relative_to(REPO_ROOT).as_posix()
        if rel.startswith(allowed_prefixes):
            continue
        text = path.read_text()
        for symbol in FORBIDDEN_ADAPTER_BYPASS_SYMBOLS:
            if symbol in text:
                violations.append(f"{rel}: {symbol}")

    assert not violations, (
        "App, watch, shell, and feature code must not call raw WorkoutKitAdapter "
        "bypass APIs. Use WorkoutKitPushCoordinator or the narrow DEBUG diagnostic facade:\n"
        + "\n".join(violations)
    )


def test_workoutkit_adapter_healthkit_usage_is_enum_only() -> None:
    """WorkoutKitAdapter may use HealthKit enum types, not HealthKit data access."""

    violations: list[str] = []
    root = REPO_ROOT / "app" / "Packages" / "WorkoutKitAdapter" / "Sources"
    for path in _swift_files(root):
        text = path.read_text()
        for symbol in FORBIDDEN_HEALTHKIT_DATA_ACCESS_SYMBOLS:
            if symbol in text:
                violations.append(f"{path.relative_to(REPO_ROOT).as_posix()}: {symbol}")

    assert not violations, (
        "WorkoutKitAdapter's HealthKit exception is limited to enum types required "
        "for WorkoutKit plan construction; HealthKit data access belongs in HealthKitBridge:\n"
        + "\n".join(violations)
    )


def test_activity_intent_source_facts_stay_vendor_neutral() -> None:
    """Primitive source facts stay neutral; target policy belongs in export adapters."""

    source_fact_files = [
        REPO_ROOT
        / "app"
        / "Packages"
        / "Core"
        / "Domain"
        / "Sources"
        / "CoreDomain"
        / "PrimitiveWorkout.swift",
        REPO_ROOT / "schema" / "Sources" / "WorkoutDBSchema" / "PrimitiveEntities.swift",
    ]
    violations: list[str] = []
    for path in source_fact_files:
        text = path.read_text()
        for symbol in FORBIDDEN_TARGET_SPECIFIC_SOURCE_FACT_SYMBOLS:
            if symbol in text:
                violations.append(f"{path.relative_to(REPO_ROOT).as_posix()}: {symbol}")

    schemas_text = (REPO_ROOT / "server" / "workoutdb_server" / "api" / "schemas.py").read_text()
    match = re.search(
        r"class ActivityIntentIn\(BaseModel\):(?P<body>.*?)(?=\n\nclass )",
        schemas_text,
        re.S,
    )
    assert match is not None, "ActivityIntentIn schema must exist"
    for symbol in FORBIDDEN_TARGET_SPECIFIC_SOURCE_FACT_SYMBOLS:
        if symbol in match.group("body"):
            violations.append(f"server/workoutdb_server/api/schemas.py: ActivityIntentIn {symbol}")

    assert not violations, (
        "activity_intent is a vendor-neutral primitive source fact. "
        "Do not add WorkoutKit/HealthKit/Strava/Apple-specific fields there:\n"
        + "\n".join(violations)
    )
