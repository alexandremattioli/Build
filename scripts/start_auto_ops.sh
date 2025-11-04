#!/bin/bash
# Start enhanced heartbeat daemon for Build2 if not running; create PID and log.
set -euo pipefail

SERVER_ID="${1:-build2}"
INTERVAL="${2:-300}"
PID_FILE="/var/run/enhanced_heartbeat_${SERVER_ID}.pid"
LOG_FILE="/var/log/enhanced_heartbeat_${SERVER_ID}.log"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "Daemon already running (PID $(cat "$PID_FILE"))"
  exit 0
fi

nohup bash "$(dirname "$0")/enhanced_heartbeat_daemon.sh" "$SERVER_ID" "$INTERVAL" >> "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"
echo "Started enhanced heartbeat daemon for $SERVER_ID (PID $(cat "$PID_FILE"), interval ${INTERVAL}s)"
