#!/usr/bin/env bash
set -euo pipefail
# Re-record all tests that use VCR by deleting cassettes and rerunning the subset
rm -f examples/cassettes/*.yaml || true
pytest --profile pr -k http_client
