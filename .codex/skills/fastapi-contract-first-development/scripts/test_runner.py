#!/usr/bin/env python3
"""
Run test suites for FastAPI application.

Usage:
    python test_runner.py --unit
    python test_runner.py --contract
    python test_runner.py --integration
    python test_runner.py --all
    python test_runner.py --coverage
"""

import argparse
import subprocess
import sys


def run_tests(test_type: str, with_coverage: bool = False) -> bool:
    """Run specified test suite."""
    test_paths = {
        "unit": "tests/unit/",
        "contract": "tests/contract/",
        "integration": "tests/integration/",
        "all": "tests/",
    }

    path = test_paths.get(test_type, "tests/")

    cmd = ["pytest", path, "-v"]

    if with_coverage:
        cmd.extend(["--cov=app", "--cov-report=html", "--cov-report=term"])

    print(f"🧪 Running {test_type} tests...")
    print(f"Command: {' '.join(cmd)}\n")

    try:
        result = subprocess.run(cmd, capture_output=False, text=True)
        return result.returncode == 0
    except FileNotFoundError:
        print("❌ pytest not found. Install with: pip install pytest pytest-cov")
        return False


def main() -> None:
    parser = argparse.ArgumentParser(description="Run FastAPI test suites")
    parser.add_argument("--unit", action="store_true", help="Run unit tests")
    parser.add_argument("--contract", action="store_true", help="Run contract tests")
    parser.add_argument("--integration", action="store_true", help="Run integration tests")
    parser.add_argument("--all", action="store_true", help="Run all tests")
    parser.add_argument("--coverage", action="store_true", help="Run with coverage report")

    args = parser.parse_args()

    if args.all or not (args.unit or args.contract or args.integration):
        success = run_tests("all", args.coverage)
    else:
        success = True
        if args.unit:
            success = success and run_tests("unit", args.coverage)
        if args.contract:
            success = success and run_tests("contract", args.coverage)
        if args.integration:
            success = success and run_tests("integration", args.coverage)

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
