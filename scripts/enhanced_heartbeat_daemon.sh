#!/bin/bash
# enhanced_heartbeat_daemon.sh - Run enhanced heartbeat with message checking
# Usage: ./enhanced_heartbeat_daemon.sh <server_id> [interval_seconds]

set -euo pipefail

SERVER_ID="${1:-build2}"
INTERVAL="${2:-60}"

echo "Starting enhanced heartbeat daemon for $SERVER_ID (interval: ${INTERVAL}s)"
echo "This will check for messages on each heartbeat cycle"
echo "Messages will be logged to: /var/log/build-messages-$SERVER_ID.log"
echo "Press Ctrl+C to stop"
echo ""

while true; do
    ./enhanced_heartbeat.sh "$SERVER_ID" || echo "Heartbeat cycle failed at $(date)"
    sleep "$INTERVAL"
done
