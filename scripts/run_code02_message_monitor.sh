#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR%/scripts}"
PYTHON="${PYTHON:-python3}"
SERVER_ID="${1:-code2}"
INTERVAL="${2:-10}"
LOG_PATH="$REPO_ROOT/logs/watch_messages.log"
STATE_PATH="$REPO_ROOT/.watch_messages_state_${SERVER_ID}.json"
WATCH_METRICS_PATH="$REPO_ROOT/logs/watch_metrics.json"
AUTORESPONDER_METRICS_PATH="$REPO_ROOT/logs/autoresponder_metrics.json"
WATCH_HEARTBEAT="/var/run/watch_messages.heartbeat"
AUTORESPONDER_HEARTBEAT="/var/run/autoresponder_${SERVER_ID}.heartbeat"

printf "Starting Code02 message monitor for %s (interval %ss)\n" "$SERVER_ID" "$INTERVAL"
exec "$PYTHON" "$REPO_ROOT/Communications/Implementation/message_monitor.py" \
    --repo "$REPO_ROOT" \
    --server "$SERVER_ID" \
    --interval "$INTERVAL" \
    --log "$LOG_PATH" \
    --state "$STATE_PATH" \
    --watch-metrics "$WATCH_METRICS_PATH" \
    --autoresponder-metrics "$AUTORESPONDER_METRICS_PATH" \
    --watch-heartbeat "$WATCH_HEARTBEAT" \
    --autoresponder-heartbeat "$AUTORESPONDER_HEARTBEAT"
