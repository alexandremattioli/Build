#!/bin/bash
# heartbeat_cron.sh - One-shot enhanced heartbeat for cron usage
# Usage: ./heartbeat_cron.sh [server_id]
# Env:
#   HEARTBEAT_BRANCH       Branch name, or 1/auto for heartbeat-<server>. Default: auto
#   HEARTBEAT_PUSH_EVERY   Push every N beats (>=2). Default: 5

set -euo pipefail

SERVER_ID="${1:-build2}"
REPO_DIR="/root/Build"

# Defaults suitable for cron usage
export HEARTBEAT_BRANCH="${HEARTBEAT_BRANCH:-auto}"
export HEARTBEAT_PUSH_EVERY="${HEARTBEAT_PUSH_EVERY:-5}"

exec "$REPO_DIR/scripts/enhanced_heartbeat.sh" "$SERVER_ID"
