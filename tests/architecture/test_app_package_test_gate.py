from __future__ import annotations

import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
APP_PACKAGES = REPO_ROOT / "app" / "Packages"

EXECUTABLE_TARGET = re.compile(r"\.executableTarget\s*\(\s*name:\s*\"([^\"]+)\"")
XCTEST_TARGET = re.compile(r"\.testTarget\s*\(")


def test_make_test_app_packages_covers_all_package_test_targets() -> None:
    """Keep the hardcoded app package gate from drifting as packages are added."""

    makefile = (REPO_ROOT / "Makefile").read_text()
    missing: list[str] = []

    for package_file in sorted(APP_PACKAGES.glob("**/Package.swift")):
        package_dir = package_file.parent
        rel_dir = package_dir.relative_to(REPO_ROOT)
        manifest = package_file.read_text()

        for target in EXECUTABLE_TARGET.findall(manifest):
            if not target.endswith("Tests"):
                continue
            command = f"cd {rel_dir} && swift run {target}"
            if command not in makefile:
                missing.append(command)

        if XCTEST_TARGET.search(manifest):
            command = f"cd {rel_dir} && swift test"
            if command not in makefile:
                missing.append(command)

    assert not missing, "Missing app package test gate commands:\n" + "\n".join(missing)
