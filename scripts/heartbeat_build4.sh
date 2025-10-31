#!/bin/bash
# Heartbeat script for Build4

REPO_DIR="/root/Build"
SERVER_ID="build4"

while true; do
  cd "$REPO_DIR"
  git pull origin main -q
  
  jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     --arg uptime "$(cat /proc/uptime | cut -d' ' -f1 | cut -d'.' -f1)" \
     '.timestamp = $ts | .uptime_seconds = ($uptime | tonumber) | .healthy = true' \
     ${SERVER_ID}/heartbeat.json > /tmp/heartbeat.json
  mv /tmp/heartbeat.json ${SERVER_ID}/heartbeat.json
  
  git add ${SERVER_ID}/heartbeat.json
  git commit -q -m "Heartbeat: ${SERVER_ID} $(date -u +%H:%M:%S)" || true
  git push origin main -q || true
  
  sleep 60
done
