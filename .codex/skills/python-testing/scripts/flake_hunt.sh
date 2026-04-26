#!/usr/bin/env bash
set -euo pipefail
# Run the suite multiple times with randomized order to surface flakes
COUNT="${1:-5}"
i=1
while [ "$i" -le "$COUNT" ]; do
  echo "Flake hunt pass $i/$COUNT"
  pytest --profile pr --random-order-bucket=module || exit 1
  i=$((i+1))
done
