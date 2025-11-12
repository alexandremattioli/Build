#!/bin/bash
# validate_all.sh - Validate key coordination and state JSON files
# Usage: ./validate_all.sh

set -euo pipefail

REPO_DIR="/root/Build"
cd "$REPO_DIR"

pass=true

err() {
  echo "ERROR: $1" >&2
  pass=false
}

ok() {
  echo "[OK] $1"
}

# Validate build status files
for f in build1/status.json build2/status.json; do
  if [ -f "$f" ]; then
    if jq -e '.server and .ip and .status and .timestamp' "$f" >/dev/null 2>&1; then
      ok "$f valid (server, ip, status, timestamp)"
    else
      err "$f missing required fields (server, ip, status, timestamp)"
    fi
  else
    err "$f not found"
  fi
done

# Validate heartbeat files
for f in build1/heartbeat.json build2/heartbeat.json; do
  if [ -f "$f" ]; then
    if jq -e '.server and .timestamp and (.uptime_seconds | type=="number") and (.healthy | type=="boolean")' "$f" >/dev/null 2>&1; then
      ok "$f valid (server, timestamp, uptime_seconds, healthy)"
    else
      err "$f missing required heartbeat fields"
    fi
  else
    err "$f not found"
  fi
done

# Validate jobs.json structure
if [ -f coordination/jobs.json ]; then
  if [ "$(jq -r '.jobs | type' coordination/jobs.json 2>/dev/null || echo)" = "array" ]; then
    ok "coordination/jobs.json has .jobs array"
  else
    err "coordination/jobs.json must contain .jobs as array"
  fi
else
  err "coordination/jobs.json not found"
fi

# Validate messages.json structure (expect object with .messages array)
if [ -f coordination/messages.json ]; then
  if [ "$(jq -r '.messages | type' coordination/messages.json 2>/dev/null || echo)" = "array" ]; then
    ok "coordination/messages.json has .messages array"
  else
    err "coordination/messages.json must contain .messages as array"
  fi
else
  err "coordination/messages.json not found"
fi

# Validate locks.json structure
if [ -f coordination/locks.json ]; then
  if [ "$(jq -r '.locks | type' coordination/locks.json 2>/dev/null || echo)" = "object" ]; then
    ok "coordination/locks.json has .locks object"
  else
    err "coordination/locks.json must contain .locks object"
  fi
else
  err "coordination/locks.json not found"
fi

# Optional: message_stats.json basic shape
if [ -f coordination/message_stats.json ]; then
  if jq -e '.last_updated and .total_messages and .by_server and .by_recipient and .recent_activity' coordination/message_stats.json >/dev/null 2>&1; then
    ok "coordination/message_stats.json basic fields present"
  else
    err "coordination/message_stats.json missing basic fields"
  fi
fi

if $pass; then
  echo "All validations passed"
  exit 0
else
  echo "Validation failures detected" >&2
  exit 1
fi
