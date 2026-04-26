#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["semgrep"]
# ///
"""
Security scan using Semgrep for AST-based pattern detection.

Usage:
    uv run scripts/security_scan.py [path]
    uv run scripts/security_scan.py --help

Runs targeted security rules for Python and JavaScript/TypeScript codebases.
Outputs findings as leads for review, not confirmed vulnerabilities.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

# Semgrep rulesets to run, in priority order
# See: https://semgrep.dev/r
RULESETS: list[str] = [
    # Python
    "p/python",
    # JavaScript/TypeScript
    "p/javascript",
    # OWASP patterns
    "p/owasp-top-ten",
    # Secrets detection
    "p/secrets",
]

# Specific high-value rules to always include
# These cover the patterns from our research
SPECIFIC_RULES: list[str] = [
    # SQL injection
    "python.sqlalchemy.security.sqlalchemy-execute-raw-query",
    "python.lang.security.audit.formatted-sql-query",
    # Command injection
    "python.lang.security.audit.dangerous-subprocess-use",
    "python.lang.security.audit.subprocess-shell-true",
    # Deserialization
    "python.lang.security.deserialization.avoid-pickle",
    "python.lang.security.deserialization.avoid-pyyaml-load",
    # SSRF
    "python.lang.security.audit.ssrf.requests-ssrf",
    # Path traversal
    "python.lang.security.audit.path-traversal",
    # Dangerous defaults
    "python.lang.security.audit.insecure-transport.requests-no-verify",
    # JWT issues
    "python.jwt.security.unverified-jwt-decode",
    # React/JS output safety
    "javascript.react.security.audit.react-dangerouslysetinnerhtml",
]


def run_semgrep(
    target: Path,
    *,
    use_rulesets: bool = True,
    json_output: bool = False,
    verbose: bool = False,
) -> int:
    """Run semgrep with security-focused rules."""
    cmd = ["semgrep", "scan"]

    # Add rulesets
    if use_rulesets:
        for ruleset in RULESETS:
            cmd.extend(["--config", ruleset])
    else:
        # Use only specific high-value rules
        for rule in SPECIFIC_RULES:
            cmd.extend(["--config", f"r/{rule}"])

    # Output format
    if json_output:
        cmd.append("--json")

    # Verbosity
    if not verbose:
        cmd.append("--quiet")

    # Target
    cmd.append(str(target))

    if verbose:
        print(f"Running: {' '.join(cmd)}", file=sys.stderr)

    try:
        result = subprocess.run(cmd, check=False)
        return result.returncode
    except FileNotFoundError:
        print(
            "Error: semgrep not found. Run with 'uv run' to auto-install.",
            file=sys.stderr,
        )
        return 2


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "target",
        nargs="?",
        default=".",
        help="Path to scan (default: current directory)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output findings as JSON",
    )
    parser.add_argument(
        "--fast",
        action="store_true",
        help="Run only high-priority rules (faster, fewer results)",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Show semgrep command and progress",
    )
    parser.add_argument(
        "--list-rules",
        action="store_true",
        help="List the rulesets and rules that will be run",
    )

    args = parser.parse_args(argv)

    if args.list_rules:
        print("Rulesets:")
        for ruleset in RULESETS:
            print(f"  - {ruleset}")
        print("\nSpecific rules (--fast mode):")
        for rule in SPECIFIC_RULES:
            print(f"  - {rule}")
        return 0

    target = Path(args.target).resolve()
    if not target.exists():
        print(f"Error: path does not exist: {target}", file=sys.stderr)
        return 2

    return run_semgrep(
        target,
        use_rulesets=not args.fast,
        json_output=args.json,
        verbose=args.verbose,
    )


if __name__ == "__main__":
    raise SystemExit(main())
