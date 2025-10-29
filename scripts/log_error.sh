#!/bin/bash
# log_error.sh - Centralized error logging
# Usage: ./log_error.sh <script> <message>

set -euo pipefail

SCRIPT="$1"
MESSAGE="$2"

LOG_FILE="/var/log/build-errors.log"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "[$TIMESTAMP] ERROR [$SCRIPT]: $MESSAGE" >> "$LOG_FILE"
echo "ERROR: $MESSAGE" >&2
