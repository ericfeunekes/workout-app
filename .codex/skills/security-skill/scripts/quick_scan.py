#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""
Quick scan (lead generation) for common security review hotspots.

Run ripgrep patterns for likely secrets and dangerous sinks. Treat matches as leads
to review, not as confirmed vulnerabilities.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Pattern:
    id: str
    description: str
    regex: str


PATTERNS: list[Pattern] = [
    Pattern(
        id="secret.aws_access_key_id",
        description="Possible AWS Access Key ID",
        regex=r"AKIA[0-9A-Z]{16}",
    ),
    Pattern(
        id="secret.private_key",
        description="Possible private key material",
        regex=r"-----BEGIN (?:RSA|EC|OPENSSH|DSA) PRIVATE KEY-----",
    ),
    Pattern(
        id="secret.generic_assignment",
        description="Potential hardcoded credential assignment (high-noise lead)",
        regex=r"(?i)\b(?:password|passwd|pwd|secret|api[_-]?key|token)\b\s*[:=]\s*['\"][^'\"]{6,}['\"]",
    ),
    Pattern(
        id="sink.eval",
        description="Dynamic code execution via eval()",
        regex=r"\beval\s*\(",
    ),
    Pattern(
        id="sink.yaml_load",
        description="Potential unsafe YAML load() usage",
        regex=r"\byaml\.load\s*\(",
    ),
    Pattern(
        id="sink.pickle_loads",
        description="Deserialization via pickle.loads()",
        regex=r"\bpickle\.loads\s*\(",
    ),
    Pattern(
        id="sink.subprocess_shell_true",
        description="subprocess with shell=True (command injection risk)",
        regex=r"\bshell\s*=\s*True\b",
    ),
]


def _run_rg(*, repo: Path, pattern: Pattern, max_matches: int) -> list[str]:
    cmd = [
        "rg",
        "--no-heading",
        "--line-number",
        "--color",
        "never",
        "--max-count",
        str(max_matches),
        "--",
        pattern.regex,
        str(repo),
    ]

    try:
        proc = subprocess.run(
            cmd,
            check=False,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        raise RuntimeError("ripgrep (rg) not found on PATH") from None

    if proc.returncode not in (0, 1):
        stderr = proc.stderr.strip()
        raise RuntimeError(f"rg failed for {pattern.id}: {stderr or 'unknown error'}")

    lines = [line for line in proc.stdout.splitlines() if line.strip()]
    return lines


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "repo",
        nargs="?",
        default=".",
        help="Path to repo/workdir to scan (default: .)",
    )
    parser.add_argument(
        "--max-matches",
        type=int,
        default=50,
        help="Maximum matches per pattern (default: 50)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit JSON output (default: human-readable)",
    )
    args = parser.parse_args(argv)

    repo = Path(args.repo).resolve()
    if not repo.exists():
        print(f"Repo path does not exist: {repo}", file=sys.stderr)
        return 2

    results: dict[str, dict[str, object]] = {}
    for pattern in PATTERNS:
        matches = _run_rg(repo=repo, pattern=pattern, max_matches=args.max_matches)
        if matches:
            results[pattern.id] = {
                "description": pattern.description,
                "match_count": len(matches),
                "matches": matches,
            }

    if args.json:
        json.dump(
            {
                "repo": str(repo),
                "results": results,
            },
            sys.stdout,
            indent=2,
            sort_keys=True,
        )
        sys.stdout.write("\n")
        return 0

    if not results:
        print("No matches found for built-in patterns.")
        return 0

    print(f"Repo: {repo}")
    print("Matches (review leads):")
    for pattern_id, payload in results.items():
        description = str(payload.get("description", ""))
        match_count = int(payload.get("match_count", 0))
        print(f"- {pattern_id} ({match_count}) — {description}")
    print("\nTip: re-run with --json to capture matches for triage without re-scanning.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
