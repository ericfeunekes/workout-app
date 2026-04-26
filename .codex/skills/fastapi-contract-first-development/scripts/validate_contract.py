#!/usr/bin/env python3
"""
Validate that API implementation matches OpenAPI contract.

Usage:
    python validate_contract.py
"""

import subprocess
import sys


def run_contract_tests() -> bool:
    """Run contract validation tests."""
    print("🔍 Validating implementation against contract...")
    print("\nRunning contract tests...")

    try:
        result = subprocess.run(["pytest", "tests/contract/", "-v"], capture_output=True, text=True)

        print(result.stdout)

        if result.returncode == 0:
            print("\n✅ All contract tests passed!")
            return True
        else:
            print("\n❌ Contract validation failed!")
            print(result.stderr)
            return False

    except FileNotFoundError:
        print("❌ pytest not found. Install with: pip install pytest")
        return False


def main() -> None:
    success = run_contract_tests()
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
