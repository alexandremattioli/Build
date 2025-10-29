#!/bin/bash
# recover_stale_heartbeat.sh - Auto-restart heartbeat daemon if stale
# Usage: ./recover_stale_heartbeat.sh <server_id>

set -euo pipefail

SERVER_ID="${1:-build2}"
REPO_DIR="/root/Build"
HEARTBEAT_FILE="$REPO_DIR/$SERVER_ID/heartbeat.json"

if [ ! -f "$HEARTBEAT_FILE" ]; then
    echo "No heartbeat file found"
    exit 1
fi

LAST_BEAT=$(jq -r '.timestamp' "$HEARTBEAT_FILE")
LAST_BEAT_TS=$(date -d "$LAST_BEAT" +%s 2>/dev/null || echo 0)
NOW_TS=$(date +%s)
AGE=$((NOW_TS - LAST_BEAT_TS))

if [ $AGE -gt 300 ]; then
    echo "Heartbeat stale ($AGE seconds), restarting daemon..."
    pkill -f "enhanced_heartbeat_daemon.sh $SERVER_ID" || true
    sleep 2
    nohup "$REPO_DIR/scripts/enhanced_heartbeat_daemon.sh" "$SERVER_ID" 60 > "/var/log/heartbeat-$SERVER_ID.log" 2>&1 &
    echo "Heartbeat daemon restarted (PID: $!)"
else
    echo "Heartbeat is fresh ($AGE seconds old). No action needed."
fi
