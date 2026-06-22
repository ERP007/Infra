#!/usr/bin/env bash
set -euo pipefail

KEEP_UNTIL="${KEEP_UNTIL:-24h}"

echo "Before:"
docker system df

docker builder prune -af --filter "until=${KEEP_UNTIL}"

echo "After:"
docker system df
df -h /
