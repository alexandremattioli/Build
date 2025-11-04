#!/bin/bash
# Stop enhanced heartbeat daemon for Build2 if running; remove PID file.
set -euo pipefail

SERVER_ID="${1:-build2}"
PID_FILE="/var/run/enhanced_heartbeat_${SERVER_ID}.pid"

if [ ! -f "$PID_FILE" ]; then
  echo "No PID file found for $SERVER_ID"
  exit 0
fi

PID=$(cat "$PID_FILE")
if kill -0 "$PID" 2>/dev/null; then
  kill "$PID" || true
  sleep 1
  if kill -0 "$PID" 2>/dev/null; then
    echo "Process still running; sending SIGKILL"
    kill -9 "$PID" || true
  fi
fi
rm -f "$PID_FILE"
echo "Stopped enhanced heartbeat daemon for $SERVER_ID"
