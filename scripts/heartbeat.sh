#!/bin/bash
# heartbeat.sh - Send heartbeat for this server
# Usage: ./heartbeat.sh <server_id>

set -euo pipefail

SERVER_ID="${1:-build2}"
REPO_DIR="/root/Build"

cd "$REPO_DIR"

# Pull latest
git pull origin main --rebase --autostash >/dev/null 2>&1 || true

# Get current timestamp and uptime
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
UPTIME=$(cat /proc/uptime | cut -d' ' -f1 | cut -d'.' -f1)

# Update heartbeat file
HEARTBEAT_FILE="$SERVER_ID/heartbeat.json"

jq --arg ts "$TIMESTAMP" \
   --argjson uptime "$UPTIME" \
   '.timestamp = $ts | .uptime_seconds = $uptime | .healthy = true' \
   "$HEARTBEAT_FILE" > tmp.json

mv tmp.json "$HEARTBEAT_FILE"

# Commit and push
git add "$HEARTBEAT_FILE"
git commit -m "[$SERVER_ID] Heartbeat $(date -u +%H:%M:%S)" >/dev/null 2>&1
git push origin main >/dev/null 2>&1

echo "Heartbeat sent: $SERVER_ID at $TIMESTAMP"
