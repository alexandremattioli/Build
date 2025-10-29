#!/bin/bash
# heartbeat_daemon.sh - Run heartbeat in a loop
# Usage: ./heartbeat_daemon.sh <server_id> [interval_seconds]

set -euo pipefail

SERVER_ID="${1:-build2}"
INTERVAL="${2:-300}"

echo "Starting heartbeat daemon for $SERVER_ID (interval: ${INTERVAL}s)"
echo "Press Ctrl+C to stop"

while true; do
    ./heartbeat.sh "$SERVER_ID" || echo "Heartbeat failed at $(date)"
    sleep "$INTERVAL"
done
