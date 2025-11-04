#!/bin/bash
################################################################################
# Script: ensure_auto_responder.sh
# Purpose: Ensure the Build1 auto-responder is running; start if not.
# Logs: /var/log/auto_respond_build1.log (responder)
#       /var/log/auto_responder_supervisor.log (this script via cron)
################################################################################
set -euo pipefail

# Resolve repository directory (prefer /root/Build in production)
if [ -d "/root/Build" ]; then
  REPO_DIR="/root/Build"
else
  REPO_DIR="/Builder2/Build"
fi

SCRIPT="$REPO_DIR/scripts/auto_respond_build1.sh"
LOG_FILE="/var/log/auto_respond_build1.log"

mkdir -p /var/log || true

if pgrep -f "bash $SCRIPT" >/dev/null 2>&1 || pgrep -f "$SCRIPT" >/dev/null 2>&1; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] auto-responder already running" 
  exit 0
fi

if [ ! -x "$SCRIPT" ]; then
  chmod +x "$SCRIPT" || true
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] starting auto-responder: $SCRIPT"
nohup "$SCRIPT" >> "$LOG_FILE" 2>&1 &
echo "[$(date '+%Y-%m-%d %H:%M:%S')] started with PID $!"
