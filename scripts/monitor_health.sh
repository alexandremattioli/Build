#!/bin/bash
# monitor_health.sh - Check system health and alert on issues
# Usage: ./monitor_health.sh

set -euo pipefail

REPO_DIR="/root/Build"
cd "$REPO_DIR"

for server in build1 build2; do
    HEARTBEAT_FILE="$server/heartbeat.json"
    if [ ! -f "$HEARTBEAT_FILE" ]; then
        ./scripts/log_error.sh "monitor_health" "$server missing heartbeat file"
        continue
    fi
    LAST_BEAT=$(jq -r '.timestamp' "$HEARTBEAT_FILE")
    LAST_BEAT_TS=$(date -d "$LAST_BEAT" +%s 2>/dev/null || echo 0)
    NOW_TS=$(date +%s)
    AGE=$((NOW_TS - LAST_BEAT_TS))
    if [ "$AGE" -gt 300 ]; then
        ./scripts/log_error.sh "monitor_health" "$server heartbeat stale ($AGE seconds)"
        ./scripts/send_message.sh "system" "all" "warning" "$server heartbeat stale" "$server has not sent a heartbeat in $AGE seconds"
    fi
    # Check for unprocessed messages older than 1 hour
    OLD_MESSAGES=$(jq '[.messages[] | select(.read == false and ((now | tonumber) - (.timestamp | fromdateiso8601)) > 3600)] | length' coordination/messages.json)
    if [ "$OLD_MESSAGES" -gt 0 ]; then
        ./scripts/log_error.sh "monitor_health" "$OLD_MESSAGES unread messages older than 1 hour for $server"
    fi
    # Could add more checks here
    sleep 1
    done
