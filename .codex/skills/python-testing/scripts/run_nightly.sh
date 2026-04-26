#!/usr/bin/env bash
set -euo pipefail
pytest --profile nightly --cov --cov-report=html
mutmut run --paths-to-mutate=src/core/ || true
