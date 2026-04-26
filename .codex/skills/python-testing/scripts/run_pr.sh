#!/usr/bin/env bash
set -euo pipefail
pytest --profile pr --cov --cov-report=xml
diff-cover coverage.xml --fail-under=90
